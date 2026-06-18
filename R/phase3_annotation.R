# =========================================================================
# CenSoloLTR - Phase 3: CEN/Peri-CEN Annotation Extraction
# =========================================================================
# Step 5: Filter Full_Integrated.tsv to CEN/Peri-CEN regions only
# Step 6: Extract FASTA sequences with rich headers
# =========================================================================

#' Step 5: Extract CEN & Peri-CEN SoloLTR Annotations
#'
#' Filters the full annotation table to retain only Centromere and
#' Pericentromere region entries, sorted by chromosome and position.
#'
#' @param params CenSoloLTRConfig object
#' @export
step5_extract_cen_annotations <- function(params) {
  step_header(params, "5", 10, "Extract CEN/Peri-CEN Annotations")
  if (!should_run_step(5, params)) {
    log_msg(params, "[SKIP] Step 5 disabled by user.")
    return(invisible(NULL))
  }

  sample <- params$sample_name

  input_file <- file.path(params$dirs$full_anno,
                          paste0(sample, "_Full_Integrated.tsv"))
  out_file   <- file.path(params$dirs$cen_anno,
                          paste0(sample, "_CEN_PeriCEN_SoloLTR.tsv"))

  if (step_already_done(out_file)) {
    log_msg(params, sprintf("[RESUME] CEN annotation already exists, skipping."))
    return(invisible(out_file))
  }

  if (!file.exists(input_file)) {
    stop("[Step 5] Full_Integrated.tsv not found. Run Step 4 first.")
  }

  df_all <- readr::read_tsv(input_file, show_col_types = FALSE)

  df_target <- df_all %>%
    dplyr::filter(Region %in% c("Centromere", "Pericentromere")) %>%
    dplyr::arrange(chr, start)

  if (nrow(df_target) > 0) {
    readr::write_tsv(df_target, out_file)
    n_cen  <- sum(df_target$Region == "Centromere")
    n_peri <- sum(df_target$Region == "Pericentromere")
    log_msg(params, sprintf("Step 5 complete: CEN=%d, Peri-CEN=%d → %s",
                            n_cen, n_peri, basename(out_file)))
  } else {
    log_msg(params, "Step 5: No CEN/Peri-CEN SoloLTRs found.")
  }

  invisible(out_file)
}

#' Step 6: Extract FASTA sequences for CEN/Peri-CEN SoloLTRs
#'
#' Uses genomic coordinates from the CEN/Peri-CEN annotation table to
#' extract FASTA sequences. Headers follow the format:
#' {Sample}|{Superfamily}|{Region}|{solo_id}
#'
#' @param params CenSoloLTRConfig object
#' @export
step6_extract_cen_fasta <- function(params) {
  step_header(params, "6", 11, "Extract CEN/Peri-CEN FASTA Sequences")
  if (!should_run_step(6, params)) {
    log_msg(params, "[SKIP] Step 6 disabled by user.")
    return(invisible(NULL))
  }

  sample    <- params$sample_name
  genome_fa <- params$genome_file

  tsv_path <- file.path(params$dirs$cen_anno,
                        paste0(sample, "_CEN_PeriCEN_SoloLTR.tsv"))
  out_fa   <- file.path(params$dirs$fasta_out,
                        paste0(sample, "_CEN_PeriCEN_SoloLTR.fa"))

  if (step_already_done(out_fa)) {
    log_msg(params, sprintf("[RESUME] FASTA already exists, skipping."))
    return(invisible(out_fa))
  }

  if (!file.exists(tsv_path)) {
    stop("[Step 6] CEN_PeriCEN annotation not found. Run Step 5 first.")
  }

  df <- readr::read_tsv(tsv_path, col_types = readr::cols(.default = "c"))
  if (nrow(df) == 0) {
    log_msg(params, "Step 6: No records to extract.")
    return(invisible(NULL))
  }

  df$start <- as.numeric(df$start)
  df$end   <- as.numeric(df$end)

  genome_seqs <- Biostrings::readDNAStringSet(genome_fa)
  genome_seqs <- clean_fasta_names(genome_seqs)

  valid_idx <- df$chr %in% names(genome_seqs)
  if (sum(!valid_idx) > 0) {
    warning(sprintf("[Step 6] %d records with missing chromosomes skipped.",
                    sum(!valid_idx)))
    df <- df[valid_idx, ]
  }

  extracted_seqs <- Biostrings::subseq(genome_seqs[df$chr],
                                        start = df$start, end = df$end)

  superfamily_clean <- ifelse(is.na(df$Superfamily), "Unclassified", df$Superfamily)
  new_headers <- sprintf("%s|%s|%s|%s",
                         sample, superfamily_clean, df$Region, df$solo_id)
  names(extracted_seqs) <- new_headers

  Biostrings::writeXStringSet(extracted_seqs, out_fa)
  log_msg(params, sprintf("Step 6 complete: %d sequences → %s",
                          length(extracted_seqs), basename(out_fa)))
  invisible(out_fa)
}
