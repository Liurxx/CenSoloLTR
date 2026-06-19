#!/usr/bin/env bash
# =========================================================================
# CenSoloLTR v1.1.0 — Singularity Container Build Script
# =========================================================================
# Builds an Ubuntu 22.04 Singularity container with all pipeline dependencies.
# NO root required — uses fakeroot mode (Singularity >= 3.5) or sandbox.
#
# Usage:
#   bash build_singularity_container.sh
#
# Options:
#   -o PATH   Output SIF container path
#   -s PATH   CenSoloLTR R package source directory
#   -t PATH   Temporary build directory
#   -h        Show help
#
# After build:
#   singularity exec censololtr.sif CenSoloLTR -g genome.fa -c cen.bed -o ./output -t 16
# =========================================================================
set -euo pipefail

# =========================================================================
# Software Version Configuration
# =========================================================================
# Modify these values to pin or upgrade specific versions.
# "latest" means let conda/mamba pick the newest compatible version.

# --- Base system ---
UBUNTU_VERSION="22.04"               # Ubuntu LTS (jammy, glibc 2.35)
MINIFORGE3_VERSION="24.11.2-0"       # Miniforge3 release tag
MINIFORGE3_URL="https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE3_VERSION}/Miniforge3-${MINIFORGE3_VERSION}-Linux-x86_64.sh"

# --- Docker registry mirrors (tried in order, for China mainland servers) ---
# In sandbox mode, the script tries each mirror for docker:// pull.
# In fakeroot mode, only the first DOCKER_REGISTRY is used for Bootstrap.
# Mirrors only affect the Ubuntu base image pull; conda/mamba channels
# inside the container use separate conda mirrors (see below).
DOCKER_MIRRORS=(
    "docker.io"                              # Official (fastest outside China)
    "docker.m.daocloud.io"                   # DaoCloud (fast inside China)
    "dockerproxy.com"                        # dockerproxy
    "hub-mirror.c.163.com"                   # NetEase
    "mirror.baidubce.com"                    # Baidu
    "docker.nju.edu.cn"                      # Nanjing University
)
# Registry prefix for fakeroot definition file (single value, no fallback)
DOCKER_REGISTRY=""

# --- Conda mirrors (used inside the container for faster package downloads) ---
# Empty = use defaults (repo.anaconda.com + conda-forge.org)
# For China: set to "https://mirrors.tuna.tsinghua.edu.cn/anaconda"
# Or auto-detect based on connectivity:
CONDA_MIRROR=""

# --- Conda environment name ---
ENV_NAME="censololtr"

# --- Software tool minimum versions (informational, solver resolves exact) ---
R_VERSION_MIN="4.0"
LTR_FINDER_MIN="1.07"
LTR_FINDER_PARALLEL_MIN="1.4"
LTR_HARVEST_PARALLEL_MIN="1.3"
GENOMETOOLS_GT_MIN="1.6.6"
LTR_RETRIEVER_MIN="2.9.0"
TESORTER_MIN="1.3"
REPEATMASKER_MIN="4.1.2"
BLAST_MIN="2.9"
CDHIT_MIN="4.6"
SEQTK_MIN="1.4"
SAMTOOLS_MIN="1.9"

# --- CenSoloLTR ---
CENSOLOLTR_VERSION="1.1.0"

# --- Conda channels (in priority order) ---
# On Ubuntu 22.04 (glibc 2.35), modern conda-forge works perfectly
CONDA_CHANNEL_1="conda-forge"
CONDA_CHANNEL_2="bioconda"
CONDA_CHANNEL_3="defaults"

# =========================================================================
# Colors
# =========================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =========================================================================
# Helper functions
# =========================================================================
banner() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  CenSoloLTR v${CENSOLOLTR_VERSION} — Singularity Container Build              ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "  Base image:    ubuntu:${UBUNTU_VERSION}"
    echo -e "  Miniforge3:    ${MINIFORGE3_VERSION}"
    echo -e "  Conda env:     ${ENV_NAME}"
    echo ""
}

print_config() {
    echo "Tool version requirements (minimum):"
    echo "  R                      >= ${R_VERSION_MIN}"
    echo "  ltr_finder             >= ${LTR_FINDER_MIN}"
    echo "  LTR_FINDER_parallel    >= ${LTR_FINDER_PARALLEL_MIN}"
    echo "  LTR_HARVEST_parallel   >= ${LTR_HARVEST_PARALLEL_MIN}"
    echo "  genometools (gt)       >= ${GENOMETOOLS_GT_MIN}"
    echo "  LTR_retriever          >= ${LTR_RETRIEVER_MIN}"
    echo "  TEsorter               >= ${TESORTER_MIN}"
    echo "  RepeatMasker           >= ${REPEATMASKER_MIN}"
    echo "  BLAST+                 >= ${BLAST_MIN}"
    echo "  cd-hit                 >= ${CDHIT_MIN}"
    echo "  seqtk                  >= ${SEQTK_MIN}"
    echo "  samtools               >= ${SAMTOOLS_MIN}"
    echo ""
}

# =========================================================================
# Build: fakeroot mode (Singularity >= 3.5)
# =========================================================================
build_via_fakeroot() {
    local BUILD_DIR="${TMPDIR}/fakeroot_build"
    local DEF_FILE="${BUILD_DIR}/CenSoloLTR.def"

    echo -e "${YELLOW}Building container via fakeroot mode ...${NC}"
    echo ""

    mkdir -p "${BUILD_DIR}"

    # Copy CenSoloLTR source into build context (for %files to pick up)
    cp -r "${CENSOLOLTR_SRC}" "${BUILD_DIR}/CenSoloLTR_src"

    write_definition_file "${DEF_FILE}"

    echo -e "${BLUE}Build directory:${NC} ${BUILD_DIR}"
    echo -e "${BLUE}Output SIF:${NC}      ${OUTPUT_SIF}"
    echo ""
    echo "Build log follows (5-20 min) ..."
    echo ""

    cd "${BUILD_DIR}"
    singularity build --fakeroot "${OUTPUT_SIF}" "${DEF_FILE}"

    rm -rf "${BUILD_DIR}"
}

# =========================================================================
# Build: sandbox mode (older Singularity, no fakeroot available)
# =========================================================================
build_via_sandbox() {
    local SANDBOX_DIR="${TMPDIR}/sandbox"
    local POST_SCRIPT="${TMPDIR}/post_install.sh"

    echo -e "${YELLOW}Building container via sandbox mode ...${NC}"
    echo ""

    # Step 1: Pull base image from Docker Hub (try mirrors if needed)
    echo -e "${BLUE}[1/3] Pulling ubuntu:${UBUNTU_VERSION} base image ...${NC}"
    local DOCKER_URI=""
    local PULL_OK=false

    for mirror in "${DOCKER_MIRRORS[@]}"; do
        if [ "${mirror}" = "docker.io" ]; then
            DOCKER_URI="docker://ubuntu:${UBUNTU_VERSION}"
        else
            DOCKER_URI="docker://${mirror}/ubuntu:${UBUNTU_VERSION}"
        fi
        echo -ne "  Trying ${mirror} ... "
        if singularity build --sandbox "${SANDBOX_DIR}" "${DOCKER_URI}" 2>&1; then
            echo -e "${GREEN}OK${NC}"
            PULL_OK=true
            break
        else
            echo -e "${YELLOW}failed${NC}"
            rm -rf "${SANDBOX_DIR}" 2>/dev/null || true
        fi
    done

    if [ "${PULL_OK}" = false ]; then
        echo ""
        echo -e "${RED}ERROR: Could not pull ubuntu:${UBUNTU_VERSION} from any Docker registry.${NC}"
        echo "All mirrors in DOCKER_MIRRORS failed. Check network or add more mirrors."
        exit 1
    fi

    # Step 2: Write and run post-install script
    echo ""
    echo -e "${BLUE}[2/3] Installing dependencies inside sandbox (5-20 min) ...${NC}"
    write_post_install_script "${POST_SCRIPT}"
    chmod +x "${POST_SCRIPT}"

    # Copy CenSoloLTR source
    local SRC_COPY="${SANDBOX_DIR}/tmp/CenSoloLTR_src"
    rm -rf "${SRC_COPY}"
    cp -r "${CENSOLOLTR_SRC}" "${SRC_COPY}"

    # Copy post_install script and source into the sandbox
    cp "${POST_SCRIPT}" "${SANDBOX_DIR}/tmp/post_install.sh"

    # Run the installation
    singularity exec --writable "${SANDBOX_DIR}" /bin/bash /tmp/post_install.sh

    # Step 3: Convert to final SIF
    echo ""
    echo -e "${BLUE}[3/3] Converting sandbox to final SIF ...${NC}"
    singularity build "${OUTPUT_SIF}" "${SANDBOX_DIR}"

    # Cleanup
    rm -rf "${SANDBOX_DIR}" "${POST_SCRIPT}"
}

# =========================================================================
# Write Singularity definition file (for fakeroot mode)
# =========================================================================
write_definition_file() {
    local DEF_FILE="$1"

    cat > "${DEF_FILE}" << DEFEOF
Bootstrap: docker
From: ubuntu:${UBUNTU_VERSION}

%files
    # Copy CenSoloLTR R package source into container
    CenSoloLTR_src /tmp/CenSoloLTR_src

%environment
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    export CONDA_PREFIX=/opt/conda
    export PATH=/opt/conda/envs/${ENV_NAME}/bin:/opt/conda/bin:\$PATH

%post
    set -e
    export DEBIAN_FRONTEND=noninteractive
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8

    # --- System packages ---
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends \
        wget curl ca-certificates git build-essential \
        locales libglib2.0-0 libsm6 libxrender1 libxext6 \
        libfontconfig1 libfreetype6 libssl-dev \
        procps

    locale-gen en_US.UTF-8
    update-locale LANG=en_US.UTF-8

    # --- Install Miniforge3 ---
    wget -q "${MINIFORGE3_URL}" -O /tmp/miniforge.sh
    bash /tmp/miniforge.sh -b -p /opt/conda
    rm /tmp/miniforge.sh

    export PATH="/opt/conda/bin:\$PATH"
    mamba config --set always_yes yes
    mamba config --set channel_priority strict
    mamba config --prepend channels ${CONDA_CHANNEL_3}
    mamba config --prepend channels ${CONDA_CHANNEL_2}
    mamba config --prepend channels ${CONDA_CHANNEL_1}

    # --- Create conda environment ---
    cat > /tmp/env.yaml << 'ENVEOF'
name: ${ENV_NAME}
channels:
  - ${CONDA_CHANNEL_1}
  - ${CONDA_CHANNEL_2}
  - ${CONDA_CHANNEL_3}
dependencies:
  - r-base
  - ltr_finder
  - ltr_finder_parallel
  - ltr_harvest_parallel
  - genometools-genometools
  - ltr_retriever
  - repeatmasker
  - blast
  - tesorter
  - cd-hit
  - seqtk
  - samtools
  - perl-bioperl
  - r-optparse
  - r-yaml
  - r-dplyr
  - r-stringr
  - r-readr
  - r-tidyr
  - r-ggplot2
  - r-scales
  - r-systemfonts
  - r-textshaping
  - r-svglite
  - bioconductor-biostrings
ENVEOF

    mamba env create -f /tmp/env.yaml
    mamba clean -afy
    rm /tmp/env.yaml

    # --- Install CenSoloLTR R package ---
    . /opt/conda/etc/profile.d/conda.sh
    conda activate ${ENV_NAME}
    if [ -f /tmp/CenSoloLTR_src/DESCRIPTION ]; then
        R CMD INSTALL --no-multiarch /tmp/CenSoloLTR_src
    else
        echo "WARNING: CenSoloLTR source not found, skipping R package install"
    fi

    # --- Make conda env auto-available ---
    echo '. /opt/conda/etc/profile.d/conda.sh' >> /etc/bash.bashrc
    echo 'conda activate ${ENV_NAME}' >> /etc/bash.bashrc

    # --- Cleanup ---
    apt-get clean
    rm -rf /var/lib/apt/lists/* /tmp/*

%labels
    Author CenSoloLTR
    Version ${CENSOLOLTR_VERSION}
    Base_Ubuntu ${UBUNTU_VERSION}
    Miniforge3 ${MINIFORGE3_VERSION}

%runscript
    #!/bin/bash
    . /opt/conda/etc/profile.d/conda.sh
    conda activate ${ENV_NAME}
    exec "\$@"

%help
    CenSoloLTR v${CENSOLOLTR_VERSION} Singularity Container

    Quick test:
      singularity exec ${OUTPUT_SIF} CenSoloLTR --version
      singularity exec ${OUTPUT_SIF} CenSoloLTR --help

    Run pipeline:
      singularity exec ${OUTPUT_SIF} CenSoloLTR -g genome.fa -c cen.bed -o ./output -t 16
DEFEOF
}

# =========================================================================
# Write post-install script (for sandbox mode)
# =========================================================================
write_post_install_script() {
    local POST_SCRIPT="$1"

    cat > "${POST_SCRIPT}" << POSTEOF
#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# --- System packages ---
apt-get update -qq
apt-get install -y -qq --no-install-recommends \\
    wget curl ca-certificates git build-essential \\
    locales libglib2.0-0 libsm6 libxrender1 libxext6 \\
    libfontconfig1 libfreetype6 libssl-dev

locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

# --- Miniforge3 ---
wget -q "${MINIFORGE3_URL}" -O /tmp/miniforge.sh
bash /tmp/miniforge.sh -b -p /opt/conda
rm /tmp/miniforge.sh

export PATH="/opt/conda/bin:\${PATH}"
mamba config --set always_yes yes

# --- Conda environment ---
cat > /tmp/env.yaml << 'ENVEOF'
name: ${ENV_NAME}
channels:
  - ${CONDA_CHANNEL_1}
  - ${CONDA_CHANNEL_2}
  - ${CONDA_CHANNEL_3}
dependencies:
  - r-base
  - ltr_finder
  - ltr_finder_parallel
  - ltr_harvest_parallel
  - genometools-genometools
  - ltr_retriever
  - repeatmasker
  - blast
  - tesorter
  - cd-hit
  - seqtk
  - samtools
  - perl-bioperl
  - r-optparse
  - r-yaml
  - r-dplyr
  - r-stringr
  - r-readr
  - r-tidyr
  - r-ggplot2
  - r-scales
  - r-systemfonts
  - r-textshaping
  - r-svglite
  - bioconductor-biostrings
ENVEOF

mamba env create -f /tmp/env.yaml
mamba clean -afy
rm /tmp/env.yaml

# --- Auto-activate env ---
cat >> /etc/bash.bashrc << 'BASHRC'
. /opt/conda/etc/profile.d/conda.sh
conda activate ${ENV_NAME}
BASHRC

# --- Install CenSoloLTR ---
. /opt/conda/etc/profile.d/conda.sh
conda activate ${ENV_NAME}
if [ -f /tmp/CenSoloLTR_src/DESCRIPTION ]; then
    R CMD INSTALL --no-multiarch /tmp/CenSoloLTR_src
fi

# --- Cleanup ---
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/*
POSTEOF
}

# =========================================================================
# Create host-side wrapper script
# =========================================================================
write_wrapper() {
    local WRAPPER="${CENSOLOLTR_SRC}/CenSoloLTR_container"
    local CONTAINER_PATH="${OUTPUT_SIF}"

    cat > "${WRAPPER}" << WRAPEOF
#!/usr/bin/env bash
# CenSoloLTR container wrapper — auto-generated
# Usage: CenSoloLTR_container [args...]
exec singularity exec "${CONTAINER_PATH}" CenSoloLTR "\$@"
WRAPEOF
    chmod +x "${WRAPPER}"

    echo ""
    echo -e "${BLUE}Wrapper script:${NC} ${WRAPPER}"
}

# =========================================================================
# Main
# =========================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_SIF="${SCRIPT_DIR}/censololtr_v${CENSOLOLTR_VERSION}.sif"
CENSOLOLTR_SRC="${SCRIPT_DIR}"
TMPDIR="/tmp/censololtr_sif_build_$$"
FAKEROOT_AVAILABLE=false

usage() {
    cat << USAGEEOF
Usage: $0 [options]

Options:
  -o PATH   Output SIF container path [default: ${OUTPUT_SIF}]
  -s PATH   CenSoloLTR R package source directory [default: auto-detect]
  -t PATH   Temporary build directory [default: /tmp/censololtr_sif_build_XXXXX]
  -h        Show this help
USAGEEOF
    exit 0
}

while getopts "o:s:t:h" opt; do
    case ${opt} in
        o) OUTPUT_SIF="$(realpath "${OPTARG}")" ;;
        s) CENSOLOLTR_SRC="$(realpath "${OPTARG}")" ;;
        t) TMPDIR="${OPTARG}" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# --- Pre-flight ---
banner
print_config

# Check Singularity
if ! command -v singularity &>/dev/null; then
    echo -e "${RED}ERROR: 'singularity' not found in PATH.${NC}"
    echo ""
    echo "Load the Singularity module on your HPC cluster:"
    echo "  module load singularity"
    echo "  module avail singularity"
    exit 1
fi
SIF_VER=$(singularity --version 2>&1 || true)
echo -e "${BLUE}Singularity:${NC} ${SIF_VER}"

# Check CenSoloLTR source
if [ ! -f "${CENSOLOLTR_SRC}/DESCRIPTION" ]; then
    echo -e "${RED}ERROR: CenSoloLTR R package source not found.${NC}"
    echo "Expected DESCRIPTION at: ${CENSOLOLTR_SRC}/DESCRIPTION"
    echo "Use -s PATH to specify the correct directory."
    exit 1
fi
echo -e "${BLUE}CenSoloLTR source:${NC} ${CENSOLOLTR_SRC}"

# Check fakeroot capability
# Requires: Singularity >= 3.5 AND user subuid/subgid mappings in /etc
SIF_MAJOR=$(echo "${SIF_VER}" | grep -oP '\d+\.\d+' | head -1 | cut -d. -f1 || echo "0")
SIF_MINOR=$(echo "${SIF_VER}" | grep -oP '\d+\.\d+' | head -1 | cut -d. -f2 || echo "0")
if [ "${SIF_MAJOR}" -ge 4 ] || { [ "${SIF_MAJOR}" -eq 3 ] && [ "${SIF_MINOR}" -ge 5 ]; }; then
    # Real check: fakeroot needs /etc/subuid entry for the current user
    if grep -q "^$(whoami):" /etc/subuid 2>/dev/null && \
       grep -q "^$(whoami):" /etc/subgid 2>/dev/null; then
        FAKEROOT_AVAILABLE=true
    else
        echo -e "${YELLOW}  fakeroot installed but /etc/subuid missing entry for $(whoami)${NC}"
        echo -e "${YELLOW}  (requires admin: 'usermod --add-subuids ...' on the host)${NC}"
    fi
fi

if [ "${FAKEROOT_AVAILABLE}" = true ]; then
    echo -e "${GREEN}Build mode:${NC} fakeroot (fast)"
else
    echo -e "${YELLOW}Build mode:${NC} sandbox (no fakeroot support)"
fi
echo ""

# Check disk space (container build needs ~5 GB temp space)
AVAIL_GB=$(df "$(dirname "${TMPDIR}")" 2>/dev/null | awk 'NR==2 {print int($4/1024/1024)}' || echo "0")
if [ "${AVAIL_GB}" -lt 5 ]; then
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  WARNING: only ~${AVAIL_GB} GB available in $(dirname "${TMPDIR}")${NC}"
    echo -e "${YELLOW}║  Container build needs ~5 GB of temporary space.${NC}"
    echo -e "${YELLOW}║${NC}"
    echo -e "${YELLOW}║  Use -t to specify a directory with more space:${NC}"
    echo -e "${YELLOW}║    bash $0 -t /home/users/liurx/tmp_censololtr${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${RED}Aborting — insufficient disk space.${NC}"
    exit 1
fi

mkdir -p "${TMPDIR}"

# --- Build ---
if [ "${FAKEROOT_AVAILABLE}" = true ]; then
    build_via_fakeroot
else
    build_via_sandbox
fi

# --- Post-build ---
write_wrapper

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Container build complete!                                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Container:  ${GREEN}${OUTPUT_SIF}${NC}"
echo ""
echo "Verify:"
echo "  singularity exec ${OUTPUT_SIF} Rscript -e 'library(Biostrings); cat(\"OK\n\")'"
echo "  singularity exec ${OUTPUT_SIF} CenSoloLTR --version"
echo "  singularity exec ${OUTPUT_SIF} which ltr_finder blastn cd-hit"
echo ""
echo "Run pipeline:"
echo "  singularity exec ${OUTPUT_SIF} CenSoloLTR -g genome.fa -c cen.bed -o ./output -t 16"
echo ""

# Cleanup tmpdir if empty
rmdir "${TMPDIR}" 2>/dev/null || true
