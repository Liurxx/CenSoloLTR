# LTRtrace — CLAUDE.md

## Project Overview

LTRtrace v1.1.0 — Tracing LTR retrotransposons by integrating intact LTR-RT annotation, reusable LTR library construction, taxonomic classification, and automated SoloLTR detection.

GitHub: https://github.com/Liurxx/LTRtrace

## Critical Rules

### Contributors
- **NEVER include "Claude", "Claude Opus", "Anthropic", or any AI-related name in the Contributors section of any commit, README, or repository metadata.**
- **NEVER use `Co-Authored-By: Claude Opus` or similar trailers in git commit messages.**
- All commits must have `Liurxx` as both author and committer.
- This rule was established on 2026-06-20 after a previous incident where `Co-Authored-By` trailers caused an unwanted "Claude" entry in GitHub Contributors.

### Git Practices
- Use `git filter-branch` or `git rebase` to remove any `Co-Authored-By` trailers before pushing.
- Verify with: `git log --format="%B" --all | grep "Co-Authored"`
- If a force push is needed, always verify the remote is correct first: `git remote -v`

### Container
- Repository: `Liurxx/LTRtrace`
- Pre-built Singularity images are available upon request (contact corresponding author).
- The `build_singularity_container.sh` script handles both sandbox and fakeroot modes.
- Container includes RepeatMasker Libraries (~261MB) auto-detected from host conda environment via `-l` flag.
- TEsorter database (REXdb HMM files) is included in the conda package — no extra download needed.

## Key Files

| File | Purpose |
|------|---------|
| `R/phase0_ltr_annotation.R` | Steps 0a–0e: LTR_FINDER, LTR_HARVEST, LTR_retriever, TEsorter, SoloLTR |
| `R/phase1_ltr_library.R` | Steps 1–2: Complete LTR extraction, CD-HIT clustering |
| `R/phase2_classification.R` | Step 3: BLASTn classification |
| `R/phase3_annotation.R` | Steps 4–5: CEN/Peri-CEN annotation |
| `R/phase4_output.R` | Steps 6–7: FASTA extraction + plots |
| `R/phase5_arm_annotation.R` | Steps 8–9: Arm region annotation |
| `R/cli.R` | CLI argument parsing |
| `R/config.R` | Configuration management |
| `R/fabaceae_db.R` | Pre-built Fabaceae NR LTR database support |
| `install_dependencies.sh` | One-click conda environment + R package install |
| `build_singularity_container.sh` | Singularity container build (sandbox + fakeroot modes) |

## Known Issues & Fixes Applied

### v3.x Symlink Bug (Fixed 2026-06-19)
LTR_retriever v3.x outputs files with `.mod.` infix. The pipeline creates symlinks mapping v2.9.x names. The original code used `file.symlink(mf, ...)` where `mf` was a relative path from `list.files(full.names=TRUE)`, causing broken symlinks. Fixed by using `basename(mf)` as the symlink target since both files reside in the same directory.

### TEsorter Silent Failure (Fixed 2026-06-19)
`step0d_tesorter` only issued `warning()` when TEsorter failed, causing confusing errors downstream at Step 1. Changed to `stop()` with clear error messages for both seqtk and TEsorter failures.

### LTR_retriever Error Handling (Fixed 2026-06-19)
`step0c_ltr_retriever` non-zero exit codes were downgraded to warnings even when core outputs were missing. The essential files check now properly reports failures.

### LTR_retriever .mod.out Missing (Fixed 2026-06-23)
Step 0c polling only waited for pass.list+LTRlib.fa before killing LTR_retriever, sometimes missing the `.mod.out` file needed by step 0e. Fixed by adding `.out`/`.mod.out` to the polling condition. Step 0e fallback RepeatMasker now uses `stop()` on failure instead of silent `warning()`.

## Dependencies

All bioinformatics tools are installed via conda/mamba into the `ltrtrace` environment:
- LTR_FINDER, LTR_HARVEST, LTR_retriever, TEsorter, RepeatMasker
- BLAST+, CD-HIT, seqtk, samtools, GenomeTools
- R (>= 4.0) with Biostrings, tidyverse, ggplot2, optparse

System requirement: glibc >= 2.28 (CentOS 8+, Ubuntu 20.04+, Debian 10+).  
Older systems should use the Singularity container.
