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

    # Copy RepeatMasker Libraries into build context (for %files to pick up)
    # Empty directory if not found — %files requires the source to exist
    if [ -n "${RMB_LIBRARIES}" ] && [ -d "${RMB_LIBRARIES}" ] && [ -f "${RMB_LIBRARIES}/Dfam.h5" ]; then
        echo -e "  ${GREEN}Including RepeatMasker Libraries from host${NC}"
        cp -r "${RMB_LIBRARIES}" "${BUILD_DIR}/RepeatMasker_Libraries"
    else
        mkdir -p "${BUILD_DIR}/RepeatMasker_Libraries"
    fi

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

    # Step 0: Remove old SIF if it exists (singularity build prompts for confirmation)
    rm -f "${OUTPUT_SIF}"

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

    # Step 2: Pre-download Miniforge3 installer on host (minimal Ubuntu
    # images lack wget/curl, and we can't apt-get without root in sandbox)
    echo ""
    echo -e "${BLUE}[2/3] Preparing installer and running sandbox build (5-20 min) ...${NC}"
    local MINIFORGE_INSTALLER="${TMPDIR}/Miniforge3.sh"
    if [ ! -f "${MINIFORGE_INSTALLER}" ]; then
        echo -ne "  Downloading Miniforge3 installer ... "
        if command -v wget &>/dev/null; then
            wget -q "${MINIFORGE3_URL}" -O "${MINIFORGE_INSTALLER}"
        elif command -v curl &>/dev/null; then
            curl -fsSL "${MINIFORGE3_URL}" -o "${MINIFORGE_INSTALLER}"
        else
            echo "FAIL"
            echo -e "${RED}ERROR: Neither wget nor curl found on host. Install one of them.${NC}"
            exit 1
        fi
        echo -e "${GREEN}OK${NC} (${MINIFORGE_INSTALLER})"
    else
        echo -e "  Using cached installer: ${MINIFORGE_INSTALLER}"
    fi

    write_post_install_script "${POST_SCRIPT}"
    chmod +x "${POST_SCRIPT}"

    # Prepare RepeatMasker Libraries bind mount (if available)
    local RMB_BIND=""
    if [ -n "${RMB_LIBRARIES}" ] && [ -d "${RMB_LIBRARIES}" ] && [ -f "${RMB_LIBRARIES}/Dfam.h5" ]; then
        RMB_BIND="--bind ${RMB_LIBRARIES}:/tmp/RepeatMasker_Libraries:ro"
        echo -e "  ${GREEN}Including RepeatMasker Libraries from host${NC}"
    fi

    # Use --bind to inject the script, Miniforge3 installer, and CenSoloLTR
    # source into the container. No network download needed inside the sandbox.
    singularity exec --writable \
        --bind "${POST_SCRIPT}:/tmp/post_install.sh:ro" \
        --bind "${MINIFORGE_INSTALLER}:/tmp/miniforge.sh:ro" \
        --bind "${CENSOLOLTR_SRC}:/tmp/CenSoloLTR_src:ro" \
        ${RMB_BIND} \
        "${SANDBOX_DIR}" \
        /bin/bash /tmp/post_install.sh

    # Step 3: Inject environment/runscript into sandbox (sandbox lacks %environment/%runscript)
    echo ""
    echo -e "${BLUE}[3/3] Setting up container environment and converting to SIF ...${NC}"
    local SIF_ENV_DIR="${SANDBOX_DIR}/.singularity.d/env"
    mkdir -p "${SIF_ENV_DIR}"
    cat > "${SIF_ENV_DIR}/90-environment.sh" << ENVEOF
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export CONDA_PREFIX=/opt/conda
. /opt/conda/etc/profile.d/conda.sh
conda activate ${ENV_NAME}
export PATH=/opt/conda/envs/${ENV_NAME}/bin:/opt/conda/bin:\$PATH
ENVEOF
    chmod +x "${SIF_ENV_DIR}/90-environment.sh"

    cat > "${SANDBOX_DIR}/.singularity.d/runscript" << RUNEOF
#!/bin/bash
. /opt/conda/etc/profile.d/conda.sh
conda activate ${ENV_NAME}
exec "\$@"
RUNEOF
    chmod +x "${SANDBOX_DIR}/.singularity.d/runscript"

    cat > "${SANDBOX_DIR}/.singularity.d/labels.json" << LABELSEOF
{
  "Author": "CenSoloLTR",
  "Version": "${CENSOLOLTR_VERSION}",
  "Base_Ubuntu": "${UBUNTU_VERSION}",
  "Miniforge3": "${MINIFORGE3_VERSION}"
}
LABELSEOF

    singularity build "${OUTPUT_SIF}" "${SANDBOX_DIR}"

    # Cleanup
    rm -rf "${SANDBOX_DIR}" "${POST_SCRIPT}"
}

# =========================================================================
# Write Singularity definition file (for fakeroot mode)
# =========================================================================
detect_docker_mirror() {
    # Quick test: try pulling a minimal image (or just check connectivity)
    # Returns the registry prefix to use (e.g. "docker.m.daocloud.io/" or "")
    echo -ne "  Checking Docker Hub connectivity ... "
    # Use a quick TCP check to registry-1.docker.io:443
    if timeout 5 bash -c 'echo >/dev/tcp/registry-1.docker.io/443' 2>/dev/null; then
        echo -e "${GREEN}direct${NC}"
        echo ""
    elif timeout 5 bash -c 'echo >/dev/tcp/docker.m.daocloud.io/443' 2>/dev/null; then
        echo -e "${YELLOW}via DaoCloud${NC}"
        echo "docker.m.daocloud.io/"
    elif timeout 5 bash -c 'echo >/dev/tcp/dockerproxy.com/443' 2>/dev/null; then
        echo -e "${YELLOW}via dockerproxy${NC}"
        echo "dockerproxy.com/"
    else
        echo -e "${YELLOW}unreachable (will try all mirrors at build time)${NC}"
        echo ""
    fi
}

# =========================================================================
# Write Singularity definition file (for fakeroot mode)
# =========================================================================
write_definition_file() {
    local DEF_FILE="$1"
    local FROM_IMAGE="ubuntu:${UBUNTU_VERSION}"
    if [ -n "${DOCKER_REGISTRY}" ]; then
        FROM_IMAGE="${DOCKER_REGISTRY}${FROM_IMAGE}"
    fi

    cat > "${DEF_FILE}" << DEFEOF
Bootstrap: docker
From: ${FROM_IMAGE}

%files
    # Copy CenSoloLTR R package source into container
    CenSoloLTR_src /tmp/CenSoloLTR_src
    # Copy RepeatMasker Libraries (if available on host)
    RepeatMasker_Libraries /tmp/RepeatMasker_Libraries

%environment
    export LANG=C.UTF-8
    export LC_ALL=C.UTF-8
    export CONDA_PREFIX=/opt/conda
    . /opt/conda/etc/profile.d/conda.sh
    conda activate ${ENV_NAME}

%post
    set -e
    export DEBIAN_FRONTEND=noninteractive
    export LANG=C.UTF-8
    export LC_ALL=C.UTF-8

    # --- System packages ---
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends \
        wget curl ca-certificates git build-essential \
        locales libglib2.0-0 libsm6 libxrender1 libxext6 \
        libfontconfig1 libfreetype6 libssl-dev \
        procps

    # Install proper locale for better R output
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen en_US.UTF-8 2>/dev/null || true

    # --- Install Miniforge3 ---
    wget -q "${MINIFORGE3_URL}" -O /tmp/miniforge.sh
    bash /tmp/miniforge.sh -b -p /opt/conda
    rm /tmp/miniforge.sh

    export PATH="/opt/conda/bin:\$PATH"
    conda config --set always_yes yes
    conda config --set channel_priority strict
    conda config --prepend channels ${CONDA_CHANNEL_3}
    conda config --prepend channels ${CONDA_CHANNEL_2}
    conda config --prepend channels ${CONDA_CHANNEL_1}

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

    # --- RepeatMasker Libraries (from host via %files) ---
    if [ -d /tmp/RepeatMasker_Libraries ] && [ -f /tmp/RepeatMasker_Libraries/Dfam.h5 ]; then
        echo "  Installing RepeatMasker Libraries into conda environment ..."
        cp -r /tmp/RepeatMasker_Libraries/* /opt/conda/envs/${ENV_NAME}/share/RepeatMasker/Libraries/
    fi

    # --- Install CenSoloLTR R package ---
    . /opt/conda/etc/profile.d/conda.sh
    conda activate ${ENV_NAME}
    if [ -f /tmp/CenSoloLTR_src/DESCRIPTION ]; then
        R CMD INSTALL --no-multiarch /tmp/CenSoloLTR_src
    else
        echo "WARNING: CenSoloLTR source not found, skipping R package install"
    fi

    # Create CenSoloLTR CLI wrapper
    BIN_DIR="\$(dirname "\$(which Rscript)")"
    cat > "\${BIN_DIR}/CenSoloLTR" << 'WRAPEOF'
#!/usr/bin/env bash
exec Rscript --no-save --no-restore -e "CenSoloLTR::run_pipeline()" -- "\$@"
WRAPEOF
    chmod +x "\${BIN_DIR}/CenSoloLTR"

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

# No apt-get or network tools needed — all files are bind-mounted from host.
# conda provides compilers, system libraries, and R self-contained.

# --- Miniforge3 (bind-mounted from host, copy to writable location) ---
cp /tmp/miniforge.sh /tmp/miniforge_install.sh
bash /tmp/miniforge_install.sh -b -p /opt/conda
rm -f /tmp/miniforge_install.sh

export PATH="/opt/conda/bin:\${PATH}"
conda config --set always_yes yes

# --- Conda environment ---
# Includes conda compilers (gcc, g++, gfortran) as replacement for
# build-essential; R CMD INSTALL needs them to compile the CenSoloLTR package.
cat > /tmp/env.yaml << 'ENVEOF'
name: ${ENV_NAME}
channels:
  - ${CONDA_CHANNEL_1}
  - ${CONDA_CHANNEL_2}
  - ${CONDA_CHANNEL_3}
dependencies:
  # Compilers (conda-provided, no system root needed)
  - c-compiler
  - cxx-compiler
  - gfortran
  - make
  # R and bioinformatics tools
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

# --- RepeatMasker Libraries (bind-mounted from host) ---
if [ -d /tmp/RepeatMasker_Libraries ] && [ -f /tmp/RepeatMasker_Libraries/Dfam.h5 ]; then
    echo "  Installing RepeatMasker Libraries into conda environment ..."
    cp -r /tmp/RepeatMasker_Libraries/* /opt/conda/envs/${ENV_NAME}/share/RepeatMasker/Libraries/
fi

# --- Install CenSoloLTR ---
. /opt/conda/etc/profile.d/conda.sh
set +u  # conda activate may reference unbound CONDA_BACKUP_* vars
conda activate ${ENV_NAME}
set -u
if [ -f /tmp/CenSoloLTR_src/DESCRIPTION ]; then
    R CMD INSTALL --no-multiarch /tmp/CenSoloLTR_src
fi

# Create CenSoloLTR CLI wrapper in the conda env bin/ directory
BIN_DIR="\$(dirname "\$(which Rscript)")"
cat > "\${BIN_DIR}/CenSoloLTR" << 'WRAPPEREOF'
#!/usr/bin/env bash
exec Rscript --no-save --no-restore -e "CenSoloLTR::run_pipeline()" -- "\$@"
WRAPPEREOF
chmod +x "\${BIN_DIR}/CenSoloLTR"
# /tmp/CenSoloLTR_src is bind-mounted, do not remove

# --- Cleanup ---
# Skip bind-mounted files (read-only); only remove writable temp files
find /tmp -maxdepth 1 -writable -name '*.sh' -delete 2>/dev/null || true
find /tmp -maxdepth 1 -writable -name '*.yaml' -delete 2>/dev/null || true
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
  -l PATH   RepeatMasker Libraries directory [default: auto-detect]
  -h        Show this help
USAGEEOF
    exit 0
}

RMB_LIBRARIES=""
while getopts "o:s:t:l:h" opt; do
    case ${opt} in
        o) OUTPUT_SIF="$(realpath "${OPTARG}")" ;;
        s) CENSOLOLTR_SRC="$(realpath "${OPTARG}")" ;;
        t) TMPDIR="${OPTARG}" ;;
        l) RMB_LIBRARIES="${OPTARG}" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Convert paths to absolute (prevents "cp into itself" errors)
TMPDIR="$(realpath -m "${TMPDIR}" 2>/dev/null || readlink -f "${TMPDIR}" 2>/dev/null || echo "${TMPDIR}")"
OUTPUT_SIF="$(realpath -m "${OUTPUT_SIF}" 2>/dev/null || readlink -f "${OUTPUT_SIF}" 2>/dev/null || echo "${OUTPUT_SIF}")"

# Safety: TMPDIR must NOT be inside CenSoloLTR source tree
if [[ "${TMPDIR}" == "${CENSOLOLTR_SRC}"/* ]]; then
    echo -e "${RED}ERROR: Temp directory must be OUTSIDE the CenSoloLTR source tree.${NC}"
    echo "  TMPDIR:     ${TMPDIR}"
    echo "  Source:     ${CENSOLOLTR_SRC}"
    echo ""
    echo "Use -t with an absolute path outside the repo, e.g.:"
    echo "  bash $0 -t ~/tmp_censololtr_build"
    exit 1
fi

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

# --- RepeatMasker Libraries auto-detection ---
if [ -z "${RMB_LIBRARIES}" ]; then
    # Auto-detect from conda environments (common locations)
    for candidate in \
        "${HOME}/miniconda3/envs/censololtr/share/RepeatMasker/Libraries" \
        "${HOME}/anaconda3/envs/censololtr/share/RepeatMasker/Libraries" \
        "/opt/conda/envs/censololtr/share/RepeatMasker/Libraries" \
        "$(conda info --envs 2>/dev/null | grep censololtr | awk '{print $NF}')/share/RepeatMasker/Libraries"; do
        if [ -d "${candidate}" ] && [ -f "${candidate}/Dfam.h5" ]; then
            RMB_LIBRARIES="${candidate}"
            break
        fi
    done
fi
if [ -n "${RMB_LIBRARIES}" ]; then
    echo -e "${GREEN}RepeatMasker Libraries:${NC} ${RMB_LIBRARIES}"
else
    echo -e "${YELLOW}RepeatMasker Libraries:${NC} NOT FOUND (use -l PATH to specify)"
    echo -e "${YELLOW}  Container will build but LTR_retriever will need runtime bind-mount:${NC}"
    echo -e "${YELLOW}    singularity exec --bind /path/to/Libraries:/opt/conda/envs/censololtr/share/RepeatMasker/Libraries ${OUTPUT_SIF} ...${NC}"
fi

# Check fakeroot capability
# Requires: Singularity >= 3.5 AND user subuid/subgid mappings in /etc
SIF_MAJOR=$(echo "${SIF_VER}" | grep -oP '\d+\.\d+' | head -1 | cut -d. -f1 || echo "0")
SIF_MINOR=$(echo "${SIF_VER}" | grep -oP '\d+\.\d+' | head -1 | cut -d. -f2 || echo "0")
if [ "${SIF_MAJOR}" -ge 4 ] || { [ "${SIF_MAJOR}" -eq 3 ] && [ "${SIF_MINOR}" -ge 5 ]; }; then
    # Real check: fakeroot needs /etc/subuid entry AND working mount namespace
    if grep -q "^$(whoami):" /etc/subuid 2>/dev/null && \
       grep -q "^$(whoami):" /etc/subgid 2>/dev/null; then
        # Quick smoke test: can we actually create a mount namespace?
        if unshare -U -m true 2>/dev/null || \
           singularity exec --fakeroot /dev/null true 2>/dev/null; then
            FAKEROOT_AVAILABLE=true
        else
            echo -e "${YELLOW}  subuid/subgid exist but mount namespace creation failed${NC}"
            echo -e "${YELLOW}  (kernel or Singularity install restricts unprivileged namespaces)${NC}"
        fi
    else
        echo -e "${YELLOW}  fakeroot installed but /etc/subuid missing entry for $(whoami)${NC}"
        echo -e "${YELLOW}  (requires admin: 'usermod --add-subuids ...' on the host)${NC}"
    fi
fi

if [ "${FAKEROOT_AVAILABLE}" = true ]; then
    echo -e "${GREEN}Build mode:${NC} fakeroot (fast)"
    # Detect working Docker registry for the fakeroot definition file
    DOCKER_REGISTRY=$(detect_docker_mirror)
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
