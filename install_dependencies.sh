#!/usr/bin/env bash
# =========================================================================
# CenSoloLTR v1.1.0 — Dependency Installation Script
# =========================================================================
# Installs all dependencies (conda/mamba environment + R packages + CenSoloLTR)
# in a single run. Requires: mamba (recommended) or conda
#
# Usage:
#   bash install_dependencies.sh
#
# What this script does:
#   1. Creates conda environment 'censololtr' with all bioinformatics tools
#      (uses mamba for fast solving if available, falls back to conda)
#   2. Installs R Bioconductor packages (Biostrings)
#   3. Builds and installs the CenSoloLTR R package
#   4. Creates CLI wrapper 'CenSoloLTR' in conda env PATH
#
# Minimum version requirements for external tools:
#   ltr_finder             >= 1.07
#   LTR_FINDER_parallel    >= 1.4
#   LTR_HARVEST_parallel   >= 1.3
#   genometools (gt)       >= 1.6.6
#   LTR_retriever          >= 3.0.5
#   TEsorter               >= 1.5.1
#   RepeatMasker           >= 4.2
#   BLAST+                 >= 2.9
#   cd-hit                 >= 4.6
#   seqtk                  >= 1.4
#   samtools               >= 1.9
#   R                      >= 4.0
# =========================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_NAME="censololtr"

# ---- Colors ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

banner() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  CenSoloLTR v1.1.0 — Dependency Installation                ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

banner

# ---- Pre-check: mamba (preferred) or conda (fallback) ----
PKG_MGR=""
if command -v mamba &>/dev/null; then
    PKG_MGR="mamba"
    echo -e "${BLUE}mamba detected:${NC} $(mamba --version)"
elif command -v conda &>/dev/null; then
    PKG_MGR="conda"
    echo -e "${YELLOW}conda detected:${NC} $(conda --version)"
    echo -e "${YELLOW}  (mamba not found — install 'mamba' for faster solving: conda install -n base -c conda-forge mamba)${NC}"
else
    echo -e "${RED}ERROR: neither mamba nor conda found in PATH.${NC}"
    echo ""
    echo "Please install Miniconda3 or Miniforge first:"
    echo "  https://github.com/conda-forge/miniforge (recommended, includes mamba)"
    echo "  https://docs.conda.io/en/latest/miniconda.html"
    echo ""
    echo "Quick install (Miniforge, Linux x86_64):"
    echo "  wget https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh"
    echo "  bash Miniforge3-Linux-x86_64.sh"
    echo ""
    echo "Then install mamba into base:"
    echo "  conda install -n base -c conda-forge mamba"
    exit 1
fi
echo ""

# ---- Minimum version requirements (for reference) ----
echo "Tool version requirements (minimum):"
echo "  ltr_finder             >= 1.07"
echo "  LTR_FINDER_parallel    >= 1.4"
echo "  LTR_HARVEST_parallel   >= 1.3"
echo "  genometools (gt)       >= 1.6.6"
echo "  LTR_retriever          >= 3.0.5"
echo "  TEsorter               >= 1.5.1"
echo "  RepeatMasker           >= 4.2"
echo "  BLAST+                 >= 2.9"
echo "  cd-hit                 >= 4.6"
echo "  seqtk                  >= 1.4"
echo "  samtools               >= 1.9"
echo "  R                      >= 4.0"
echo ""

# ---- Step 1: Create/update conda environment ----
echo -e "${YELLOW}[1/4] Creating conda environment '${ENV_NAME}' (via ${PKG_MGR}) ...${NC}"

# Use an environment file with minimum version pins (>= instead of =)
ENV_YAML="${SCRIPT_DIR}/environment_latest.yaml"

if [ ! -f "${ENV_YAML}" ]; then
    # Generate environment file on-the-fly without version pins
    echo -e "${YELLOW}  environment_latest.yaml not found, generating from template ...${NC}"
    ENV_YAML="/tmp/censololtr_env_$$.yaml"
    cat > "${ENV_YAML}" << 'EOF'
name: censololtr
channels:
  - bioconda
  - conda-forge
  - defaults
dependencies:
  # R base
  - r-base

  # Core LTR Detection
  - ltr_finder
  - ltr_finder_parallel
  - ltr_harvest_parallel
  - genometools-genometools

  # LTR_retriever & SoloLTR
  - ltr_retriever
  - repeatmasker
  - blast

  # Classification & Clustering
  - tesorter
  - cd-hit

  # Utilities
  - seqtk
  - samtools

  # Perl
  - perl-bioperl

  # R packages (CRAN)
  - r-optparse
  - r-yaml
  - r-dplyr
  - r-stringr
  - r-readr
  - r-tidyr
  - r-ggplot2
  - r-scales

  # Bioconductor
  - bioconductor-biostrings

EOF
fi

if conda env list 2>/dev/null | grep -q "^${ENV_NAME} "; then
    echo "  Environment '${ENV_NAME}' already exists."
    echo "  To recreate from scratch: conda env remove -n ${ENV_NAME} && bash $0"
    echo -e "${YELLOW}  Updating existing environment ...${NC}"
    set +e
    ENV_OUTPUT=$(${PKG_MGR} env update -f "${ENV_YAML}" --prune 2>&1)
    ENV_EXIT=$?
    set -e
else
    set +e
    ENV_OUTPUT=$(${PKG_MGR} env create -f "${ENV_YAML}" 2>&1)
    ENV_EXIT=$?
    set -e
fi

if [ $ENV_EXIT -ne 0 ]; then
    # openmpi post-link script may fail on servers whose /bin/sh layout
    # differs from the build host.  All packages (including openmpi) are
    # already installed; only the post-link cleanup script failed.
    # CenSoloLTR does not use MPI, so this is harmless.
    if echo "${ENV_OUTPUT}" | grep -q "pre/post link script.*openmpi"; then
        echo -e "${YELLOW}  openmpi post-link script failed (non-critical — CenSoloLTR${NC}"
        echo -e "${YELLOW}  does not use MPI).  Environment is usable.${NC}"
    else
        echo "${ENV_OUTPUT}"
        echo -e "${RED}ERROR: environment creation failed (see above).${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}  Done.${NC}"

# ---- Step 2: Activate environment ----
echo ""
echo -e "${YELLOW}[2/4] Activating environment ...${NC}"
eval "$(conda shell.bash hook)"
conda activate "${ENV_NAME}"

echo "  R:       $(which Rscript)"
echo "  BLAST:   $(which blastn 2>/dev/null || echo '(conda)')"
echo "  cd-hit:  $(which cd-hit 2>/dev/null || echo '(conda)')"

# ---- Step 3: Install additional R packages ----
echo ""
echo -e "${YELLOW}[3/4] Installing R packages ...${NC}"
Rscript -e '
required_pkgs <- c("optparse", "yaml", "dplyr", "stringr", "readr",
                   "tidyr", "ggplot2", "scales", "svglite")
for (pkg in required_pkgs) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg, repos = "https://cloud.r-project.org",
                     quiet = TRUE)
  }
}
if (!requireNamespace("Biostrings", quietly = TRUE)) {
  if (!requireNamespace("BiocManager", quietly = TRUE))
    install.packages("BiocManager", repos = "https://cloud.r-project.org",
                     quiet = TRUE)
  BiocManager::install("Biostrings", update = FALSE, ask = FALSE)
}
cat("  All R packages installed.\n")
'
echo -e "${GREEN}  Done.${NC}"

# ---- Step 4: Install CenSoloLTR R package ----
echo ""
echo -e "${YELLOW}[4/4] Installing CenSoloLTR v1.1.0 R package ...${NC}"

PKG_DIR="${SCRIPT_DIR}"
if [ -f "${SCRIPT_DIR}/../DESCRIPTION" ] && [ ! -f "${SCRIPT_DIR}/DESCRIPTION" ]; then
    # Running from inside a clone where the script is in a subdirectory
    PKG_DIR="${SCRIPT_DIR}/.."
fi

R CMD INSTALL --no-multiarch "${PKG_DIR}"

# ---- Create CLI wrapper ----
echo ""
echo -e "${YELLOW}Creating CLI wrapper in conda env bin/ ...${NC}"
PKG_BIN_DIR="$(dirname "$(which Rscript)")"
cat > "${PKG_BIN_DIR}/CenSoloLTR" << 'WRAPPER'
#!/usr/bin/env bash
exec Rscript --no-save --no-restore -e "CenSoloLTR::run_pipeline()" -- "$@"
WRAPPER
chmod +x "${PKG_BIN_DIR}/CenSoloLTR"

# ---- Done ----
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Installation Complete!                                     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Quick test:"
echo "  conda activate ${ENV_NAME}"
echo "  CenSoloLTR -v"
echo "  CenSoloLTR -h"
echo ""
echo "Run the pipeline:"
echo "  conda activate ${ENV_NAME}"
echo "  CenSoloLTR -g genome.fa -c cen.bed -o ./output -t 16"
echo ""
echo "Use with Fabaceae pre-built database:"
echo "  conda activate ${ENV_NAME}"
echo "  CenSoloLTR --list-db              # List available species"
echo "  CenSoloLTR -g genome.fa -c cen.bed -o ./output --fabaceae-db A17"
echo ""
