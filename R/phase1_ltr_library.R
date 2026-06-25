# =========================================================================
# LTRtrace - Phase 1: LTR Library Construction
# =========================================================================
# Step 1: Extract Complete LTR sequences from TEsorter .cls.tsv
# Step 2: CD-HIT clustering → Non-Redundant LTR library
# =========================================================================

#' Step 1: Extract Complete LTR sequences from TEsorter results
#'
#' Parses TEsorter .cls.tsv output, filters for Complete=yes entries,
#' extracts genomic sequences, and writes Complete_LTR.fasta.
#'
#' @param params LTRtraceConfig object
#' @export
step1_extract_complete_ltr <- function(params) {
  step_header(params, "1", 6, "Extract Complete LTR Sequences")
  if (!should_run_step(1, params)) {
    log_msg(params, "[SKIP] Step 1 disabled by user.")
    return(invisible(NULL))
  }

  sample    <- params$sample_name
  genome_fa <- params$genome_file

  out_fasta <- file.path(params$dirs$complete_ltr,
                         paste0(sample, "_Complete_LTR.fasta"))

  if (step_already_done(out_fasta)) {
    log_msg(params, sprintf("[RESUME] %s already exists, skipping.", basename(out_fasta)))
    return(invisible(out_fasta))
  }

  # Locate TEsorter .cls.tsv
  if (!params$skip_phase0) {
    cls_tsv <- file.path(params$dirs$tesorter,
                         paste0(sample, ".rawLTR.fa.rexdb-plant.cls.tsv"))
  } else {
    # Try to find in output dir or prompt
    cls_candidates <- list.files(params$outdir, pattern = "\\.cls\\.tsv$",
                                  recursive = TRUE, full.names = TRUE)
    if (length(cls_candidates) > 0) {
      cls_tsv <- cls_candidates[1]
    } else {
      stop("[Step 1] TEsorter .cls.tsv not found. Run Phase 0 or provide path.")
    }
  }

  if (!file.exists(cls_tsv)) {
    stop("[Step 1] TEsorter result not found: ", cls_tsv)
  }

  # Read TEsorter output
  df <- readr::read_tsv(cls_tsv, comment = "", show_col_types = FALSE)
  colnames(df)[1] <- "TE"

  df_complete <- df %>% dplyr::filter(Complete == "yes")

  if (nrow(df_complete) == 0) {
    warning("[Step 1] No Complete=yes LTRs found. Check TEsorter output.")
    return(invisible(NULL))
  }

  # Parse coordinates and build FASTA headers
  df_complete <- df_complete %>%
    tidyr::separate(TE, into = c("chr", "pos"), sep = ":", remove = FALSE) %>%
    tidyr::separate(pos, into = c("start", "end"), sep = "-", convert = TRUE) %>%
    dplyr::mutate(
      clean_domains = stringr::str_replace_all(Domains, "[ \\|]", "_"),
      fasta_header  = paste(Superfamily, Clade, clean_domains,
                            dplyr::row_number(), sep = "_")
    )

  log_msg(params, sprintf("Extracting %d complete LTR sequences ...", nrow(df_complete)))

  # Load genome
  genome_seqs <- Biostrings::readDNAStringSet(genome_fa)
  genome_seqs <- clean_fasta_names(genome_seqs)

  # Extract sequences
  seq_list <- list()
  for (i in seq_len(nrow(df_complete))) {
    chrom     <- as.character(df_complete$chr[i])
    start_pos <- as.numeric(df_complete$start[i])
    end_pos   <- as.numeric(df_complete$end[i])
    strand    <- as.character(df_complete$Strand[i])
    header    <- as.character(df_complete$fasta_header[i])

    if (!(chrom %in% names(genome_seqs))) next

    chr_len   <- length(genome_seqs[[chrom]])
    start_adj <- max(1, start_pos)
    end_adj   <- min(chr_len, end_pos)

    seq_slice <- Biostrings::subseq(genome_seqs[[chrom]],
                                     start = start_adj, end = end_adj)
    if (strand == "-") {
      seq_slice <- Biostrings::reverseComplement(seq_slice)
    }
    seq_list[[header]] <- seq_slice
  }

  extracted <- Biostrings::DNAStringSet(seq_list)
  Biostrings::writeXStringSet(extracted, out_fasta)

  log_msg(params, sprintf("Step 1 complete: %d sequences → %s",
                          length(extracted), basename(out_fasta)))
  invisible(out_fasta)
}

#' Step 2: CD-HIT clustering for non-redundant LTR library
#'
#' Clusters Complete LTR sequences at the configured identity/covearge
#' thresholds. Produces NR_LTR_library.fasta used for downstream BLAST.
#'
#' @param params LTRtraceConfig object
#' @export
step2_cluster_nr_library <- function(params) {
  step_header(params, "2", 7, "CD-HIT Cluster → NR LTR Library")
  if (!should_run_step(2, params)) {
    log_msg(params, "[SKIP] Step 2 disabled by user.")
    return(invisible(NULL))
  }

  sample <- params$sample_name

  fasta_in  <- file.path(params$dirs$complete_ltr,
                         paste0(sample, "_Complete_LTR.fasta"))
  fasta_out <- file.path(params$dirs$nr_lib,
                         paste0(sample, "_NR_LTR_library.fasta"))

  if (step_already_done(fasta_out)) {
    log_msg(params, sprintf("[RESUME] NR library already exists, skipping."))
    return(invisible(fasta_out))
  }

  if (!file.exists(fasta_in)) {
    stop("[Step 2] Complete LTR FASTA not found. Run Step 1 first.")
  }

  cmd <- sprintf(
    "%s -i %s -o %s -c %.2f -aS %.2f -n 5 -d 0 -M 0 -T %d",
    shQuote(params$cdhit_path),
    shQuote(fasta_in),
    shQuote(fasta_out),
    params$cdhit_identity,
    params$cdhit_coverage,
    params$threads
  )

  log_msg(params, sprintf("Running CD-HIT (identity=%.2f, coverage=%.2f, threads=%d) ...",
                          params$cdhit_identity, params$cdhit_coverage,
                          params$threads))
  log_msg(params, "This may take a while for large LTR sets ...")

  debug_log <- init_debug_log(params$dirs$nr_lib, "phase2_cdhit")
  status <- run_external(cmd, stderr_log = debug_log, echo_label = "cd-hit")

  if (status != 0) {
    warning("[Step 2] CD-HIT exited with non-zero status: ", status,
            ". Check debug log: ", debug_log)
  }

  log_msg(params, sprintf("Step 2 complete: %s", basename(fasta_out)))
  invisible(fasta_out)
}
