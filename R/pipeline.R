# =========================================================================
# CenSoloLTR - Pipeline Orchestrator
# =========================================================================

#' Run the complete CenSoloLTR pipeline
#'
#' This is the main entry point. It parses CLI arguments, sets up the
#' output directory, and executes the 5-phase / 10-step pipeline.
#'
#' When called without arguments (interactive R session), it uses
#' commandArgs(). When called with explicit arguments, it uses those.
#'
#' @param args Character vector of CLI arguments (default: commandArgs())
#' @return Invisibly returns the params list with output file paths
#' @export
#'
#' @examples
#' \dontrun{
#' # CLI mode (from shell):
#' # Rscript -e "CenSoloLTR::run_pipeline()" -- -g genome.fa -c cen.bed -o ./out
#'
#' # Programmatic mode:
#' params <- CenSoloLTR::run_pipeline(c(
#'   "-g", "genome.fa", "-c", "cen.bed", "-o", "./output", "-t", "16"
#' ))
#' }
run_pipeline <- function(args = commandArgs(trailingOnly = TRUE)) {

  # Strip Rscript -- separator if present (Rscript -e mode passes it through)
  if (length(args) > 0 && args[1] == "--") args <- args[-1]

  # ---- Parse arguments ----
  params <- parse_cli_args(args)
  print_banner()
  print_config_summary(params)

  # ---- Setup output directories and pipeline log ----
  dirs <- setup_output_dirs(params)
  params$dirs <- dirs
  params$log_file <- file.path(params$outdir, "pipeline.log")

  # ---- Load required packages ----
  log_msg(params, "Loading R packages ...")
  suppressPackageStartupMessages({
    require(Biostrings, quietly = TRUE)
    require(dplyr, quietly = TRUE)
    require(stringr, quietly = TRUE)
    require(readr, quietly = TRUE)
    require(tidyr, quietly = TRUE)
    require(ggplot2, quietly = TRUE)
    require(scales, quietly = TRUE)
    require(svglite, quietly = TRUE)
  })

  # ---- Determine sample short name ----
  sample_name <- params$sample_name
  short_name  <- gsub("^[A-Z][a-z]+_", "", sample_name)

  # ---- Build step manifest ----
  step_info <- data.frame(
    num   = 0:9,
    name  = c("LTR_FINDER+HARVEST+retriever+TEsorter+SoloLTR",
              "Extract_Complete_LTR", "Cluster_NR_Library",
              "Classify_SoloLTR", "Deep_Annotation",
              "Extract_CEN_Annotations", "Extract_CEN_FASTA",
              "Family_Stats_Plots",
              "Arm_Deep_Annotation", "Extract_Arm_FASTA"),
    stringsAsFactors = FALSE
  )

  # ---- Phase 0: De Novo LTR Annotation ----
  if (!params$skip_phase0) {
    log_msg(params, "\n", rep("=", 62))
    log_msg(params, "  PHASE 0: De Novo LTR Annotation")
    log_msg(params, rep("=", 62))

    step0a_ltr_finder(params)
    step0b_ltr_harvest(params)
    step0c_ltr_retriever(params)
    step0d_tesorter(params)
    step0e_sololtr_detect(params)
  } else {
    log_msg(params, "\n[SKIP] Phase 0: De Novo LTR Annotation")
  }

  # ---- Phase 1: LTR Library Construction ----
  log_msg(params, "\n", rep("=", 62))
  log_msg(params, "  PHASE 1: LTR Library Construction")
  log_msg(params, rep("=", 62))

  step1_extract_complete_ltr(params)
  if (is.null(params$fabaceae_db)) {
    step2_cluster_nr_library(params)
  } else {
    log_msg(params, sprintf("[SKIP] Step 2 (CD-HIT) — using pre-built Fabaceae DB (ID=%s).",
                            params$fabaceae_db))
  }

  # ---- Phase 2: SoloLTR Classification ----
  log_msg(params, "\n", rep("=", 62))
  log_msg(params, "  PHASE 2: SoloLTR Classification")
  log_msg(params, rep("=", 62))

  step3_classify_sololtr(params)

  # ---- Phase 3: CEN/Peri-CEN Deep Annotation ----
  log_msg(params, "\n", rep("=", 62))
  log_msg(params, "  PHASE 3: CEN/Peri-CEN Annotation")
  log_msg(params, rep("=", 62))

  step4_deep_annotation(params)
  step5_extract_cen_annotations(params)

  # ---- Phase 4: Output Generation ----
  log_msg(params, "\n", rep("=", 62))
  log_msg(params, "  PHASE 4: Output Generation")
  log_msg(params, rep("=", 62))

  step6_extract_cen_fasta(params)
  step7_family_stats_plot(params)

  # ---- Phase 5: Arm Region Annotation ----
  log_msg(params, "\n", rep("=", 62))
  log_msg(params, "  PHASE 5: Arm Region SoloLTR Annotation")
  log_msg(params, rep("=", 62))

  step8_arm_deep_annotation(params)
  step9_extract_arm_fasta(params)

  # ---- Final summary ----
  log_msg(params, "\n", rep("=", 62))
  log_msg(params, "  CenSoloLTR Pipeline Completed Successfully")
  log_msg(params, rep("=", 62))
  log_msg(params, sprintf("  All outputs saved under: %s", params$outdir))
  log_msg(params, sprintf("  - Phase 0: %s", dirs$phase0))
  log_msg(params, sprintf("  - Phase 1: %s", dirs$phase1))
  log_msg(params, sprintf("  - Phase 2: %s", dirs$phase2))
  log_msg(params, sprintf("  - Phase 3: %s", dirs$phase3))
  log_msg(params, sprintf("  - Phase 4: %s", dirs$phase4))
  log_msg(params, sprintf("  - Phase 5 (Arm): %s", dirs$arm_anno))
  log_msg(params, rep("=", 62), "\n")

  invisible(params)
}
