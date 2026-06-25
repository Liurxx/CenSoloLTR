# =========================================================================
# LTRtrace - Configuration Management
# =========================================================================

#' Write a default YAML config file
#'
#' @param filepath Output file path
#' @export
write_default_config <- function(filepath) {
  yaml::write_yaml(list(
    # Required input
    genome_file   = "/path/to/genome.fa",
    cen_bed_file  = "/path/to/cen.bed",
    outdir        = "./LTRtrace_output",
    sample_name   = "auto",

    # Threads
    threads       = 8,
    ltr_threads   = NULL,

    # External tools
    conda_env          = NULL,
    ltr_finder_path    = NULL,
    gt_path            = NULL,
    ltr_retriever_path = NULL,
    ltr_retriever_dir  = NULL,
    tesorter_path      = NULL,
    seqtk_path         = NULL,
    cdhit_path         = NULL,
    blastn_path        = NULL,
    makeblastdb_path   = NULL,
    solo_script_dir    = NULL,

    # Fabaceae pre-built database
    fabaceae_db    = NULL,

    # CD-HIT parameters
    cdhit_identity = 0.80,
    cdhit_coverage = 0.80,

    # BLAST parameters
    blast_evalue         = 1e-5,
    blast_evalue_rescue  = 1.0,

    # LTR_retriever control
    ltr_retriever_timeout = 0,

    # CEN/Peri-CEN parameters
    peri_extension_bp = 500000,

    # Plot parameters
    top_families    = 15,

    # Pipeline control
    skip_phase0     = FALSE,
    skip_steps      = NULL,
    only_steps      = NULL,

    # Misc
    quiet           = FALSE
  ), filepath)
  invisible(filepath)
}

#' Create output directory structure
#' @noRd
setup_output_dirs <- function(params) {
  dirs <- list(
    out          = params$outdir,
    phase0       = file.path(params$outdir, "phase0_ltr_annotation"),
    phase1       = file.path(params$outdir, "phase1_ltr_library"),
    phase2       = file.path(params$outdir, "phase2_classification"),
    phase3       = file.path(params$outdir, "phase3_annotation"),
    phase4       = file.path(params$outdir, "phase4_output"),
    # Phase 0 subdirs
    finder       = file.path(params$outdir, "phase0_ltr_annotation", "finder"),
    harvest      = file.path(params$outdir, "phase0_ltr_annotation", "harvest"),
    retriever    = file.path(params$outdir, "phase0_ltr_annotation", "retriever"),
    tesorter     = file.path(params$outdir, "phase0_ltr_annotation", "tesorter"),
    sololtr      = file.path(params$outdir, "phase0_ltr_annotation", "sololtr_detect"),
    # Phase 1 subdirs
    complete_ltr = file.path(params$outdir, "phase1_ltr_library", "complete_ltr"),
    nr_lib       = file.path(params$outdir, "phase1_ltr_library", "nr_library"),
    # Phase 2 subdirs
    classify     = file.path(params$outdir, "phase2_classification"),
    # Phase 3 subdirs
    full_anno    = file.path(params$outdir, "phase3_annotation", "full_annotation"),
    cen_anno     = file.path(params$outdir, "phase3_annotation", "cen_pericen_annotation"),
    arm_anno     = file.path(params$outdir, "phase3_annotation", "arm_annotation"),
    # Phase 4 subdirs
    fasta_out    = file.path(params$outdir, "phase4_output", "fasta"),
    arm_fasta    = file.path(params$outdir, "phase4_output", "arm_fasta"),
    stats_out    = file.path(params$outdir, "phase4_output", "stats_plots")
  )
  for (d in dirs) dir.create(d, showWarnings = FALSE, recursive = TRUE)
  return(dirs)
}

#' Log a message (respects quiet mode, also writes to pipeline.log)
#' @noRd
log_msg <- function(params, ...) {
  msg <- paste(..., collapse = " ")
  if (!params$quiet) message(msg)
  # Append to pipeline log file
  if (!is.null(params$log_file) && nzchar(params$log_file)) {
    cat(msg, "\n", file = params$log_file, append = TRUE)
  }
}
