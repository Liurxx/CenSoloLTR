# =========================================================================
# CenSoloLTR - Phase 5: Arm Region SoloLTR Annotation
# =========================================================================
# Step 8: Arm SoloLTR deep annotation with BLAST rescue
# Step 9: Extract Arm SoloLTR FASTA sequences
# =========================================================================

#' Step 8: Arm SoloLTR Deep Annotation with BLAST Rescue
#'
#' Filters the full annotation table to retain only Arm region entries.
#' Unclassified Arm soloLTRs are rescued via BLASTn against the NR LTR library,
#' keeping the single best hit per query by bitscore.
#'
#' @param params CenSoloLTRConfig object
#' @export
step8_arm_deep_annotation <- function(params) {
  step_header(params, "5", 8, "Arm SoloLTR Deep Annotation + Rescue")
  if (!should_run_step(8, params)) {
    log_msg(params, "[SKIP] Step 8 disabled by user.")
    return(invisible(NULL))
  }

  sample <- params$sample_name

  input_file <- file.path(params$dirs$full_anno,
                          paste0(sample, "_Full_Integrated.tsv"))
  out_file   <- file.path(params$dirs$arm_anno,
                          paste0(sample, "_Arm_SoloLTR.tsv"))

  if (step_already_done(out_file)) {
    log_msg(params, sprintf("[RESUME] Arm annotation already exists, skipping."))
    return(invisible(out_file))
  }

  if (!file.exists(input_file)) {
    stop("[Step 8] Full_Integrated.tsv not found. Run Step 4 first.")
  }

  df_all <- readr::read_tsv(input_file, show_col_types = FALSE)

  df_arm <- df_all %>% dplyr::filter(Region == "Arm")
  log_msg(params, sprintf("Arm region soloLTRs: %d", nrow(df_arm)))

  if (nrow(df_arm) == 0) {
    log_msg(params, "Step 8: No Arm region soloLTRs found.")
    return(invisible(NULL))
  }

  # ---- Identify unclassified sequences ----
  to_rescue <- df_arm %>% dplyr::filter(Superfamily == "Unclassified")
  n_rescue  <- nrow(to_rescue)
  log_msg(params, sprintf("  Unclassified in Arm: %d (%.1f%%)",
                          n_rescue, n_rescue / nrow(df_arm) * 100))

  nr_lib_fa <- get_nr_lib_path(params)

  if (n_rescue > 0 && file.exists(nr_lib_fa)) {
    log_msg(params, sprintf("  Rescuing %d unclassified Arm sequences via BLAST ...",
                            n_rescue))

    # ---- Extract query sequences from genome ----
    genome_seqs <- Biostrings::readDNAStringSet(params$genome_file)
    genome_seqs <- clean_fasta_names(genome_seqs)

    valid_chr <- to_rescue$chr %in% names(genome_seqs)
    if (sum(!valid_chr) > 0) {
      warning(sprintf("[Step 8] %d records with missing chromosomes skipped.",
                      sum(!valid_chr)))
      to_rescue <- to_rescue[valid_chr, ]
    }

    if (nrow(to_rescue) == 0) {
      df_arm_final <- df_arm %>%
        dplyr::mutate(Confidence = ifelse(Superfamily == "Unclassified",
                                          "Still_Unclassified", "High_Confidence"))
    } else {
      rescue_dna <- Biostrings::subseq(
        genome_seqs[to_rescue$chr],
        start = to_rescue$start, end = to_rescue$end
      )
      names(rescue_dna) <- to_rescue$solo_id

      tmp_q_fa <- file.path(params$dirs$arm_anno,
                            paste0(sample, "_arm_tmp_query.fa"))
      Biostrings::writeXStringSet(rescue_dna, tmp_q_fa)

      # ---- Build BLAST DB from NR library ----
      tmp_db_dir <- file.path(params$dirs$arm_anno, "arm_tmp_blast_db")
      dir.create(tmp_db_dir, showWarnings = FALSE, recursive = TRUE)
      db_prefix <- file.path(tmp_db_dir, "arm_lib")

      debug_log <- init_debug_log(params$dirs$arm_anno, "step8_blast")

      # Build BLAST DB without -parse_seqids (NR library IDs can exceed 50-char limit)
      db_cmd <- paste(
        shQuote(params$makeblastdb_path),
        "-in", shQuote(nr_lib_fa),
        "-dbtype nucl",
        "-out", shQuote(db_prefix)
      )
      run_external(db_cmd, stderr_log = debug_log, echo_label = "makeblastdb_arm")

      # ---- Run BLAST rescue ----
      blast_out <- file.path(params$dirs$arm_anno,
                             paste0(sample, "_arm_tmp_blast.tsv"))
      cmd <- paste(
        shQuote(params$blastn_path),
        "-query", shQuote(tmp_q_fa),
        "-db", shQuote(db_prefix),
        "-out", shQuote(blast_out),
        "-outfmt", shQuote("6 qseqid sseqid pident bitscore"),
        "-evalue", params$blast_evalue_rescue,
        "-word_size 7",
        "-dust no",
        "-max_target_seqs 5",
        "-num_threads", params$threads
      )
      run_external(cmd, stderr_log = debug_log, echo_label = "blastn_arm_rescue")

      # ---- Integrate BLAST results ----
      if (file.exists(blast_out) && file.info(blast_out)$size > 0) {
        res <- readr::read_tsv(blast_out,
                               col_names = c("solo_id", "t_id_new", "pi_new", "bs_new"),
                               show_col_types = FALSE) %>%
          dplyr::group_by(solo_id) %>%
          dplyr::slice_max(bs_new, n = 1, with_ties = FALSE) %>%
          dplyr::ungroup() %>%
          dplyr::mutate(sf_new = extract_superfamily(t_id_new))

        df_arm_final <- df_arm %>%
          dplyr::left_join(res, by = "solo_id") %>%
          dplyr::mutate(
            Confidence = dplyr::case_when(
              Superfamily != "Unclassified" ~ "High_Confidence",
              !is.na(sf_new) ~ "Low_Confidence_Rescued",
              TRUE ~ "Still_Unclassified"
            ),
            target_ltr_id = dplyr::coalesce(target_ltr_id, t_id_new),
            pident        = dplyr::coalesce(pident, pi_new),
            bitscore      = dplyr::coalesce(bitscore, bs_new),
            Superfamily   = ifelse(Superfamily == "Unclassified" & !is.na(sf_new),
                                   sf_new, Superfamily)
          )
      } else {
        df_arm_final <- df_arm %>%
          dplyr::mutate(Confidence = ifelse(Superfamily == "Unclassified",
                                            "Still_Unclassified", "High_Confidence"))
      }

      # Cleanup temp files
      unlink(c(tmp_q_fa, blast_out))
      unlink(tmp_db_dir, recursive = TRUE)
    }
  } else {
    df_arm_final <- df_arm %>%
      dplyr::mutate(Confidence = ifelse(Superfamily == "Unclassified",
                                        "Still_Unclassified", "High_Confidence"))
  }

  # ---- Save Arm annotation ----
  all_cols <- colnames(df_all)
  keep_cols <- intersect(all_cols, colnames(df_arm_final))
  extra_cols <- c("Region", "Confidence")
  for (ec in extra_cols) {
    if (ec %in% colnames(df_arm_final) && !(ec %in% keep_cols)) {
      keep_cols <- c(keep_cols, ec)
    }
  }

  df_arm_final %>%
    dplyr::select(dplyr::any_of(keep_cols)) %>%
    readr::write_tsv(out_file)

  conf_summary <- df_arm_final %>% dplyr::count(Confidence)
  log_msg(params, sprintf("Step 8 complete: %d rows -> %s",
                          nrow(df_arm_final), basename(out_file)))
  log_msg(params, "  Confidence summary:")
  for (i in seq_len(nrow(conf_summary))) {
    log_msg(params, sprintf("    %s: %d",
                            conf_summary$Confidence[i], conf_summary$n[i]))
  }

  invisible(out_file)
}

#' Step 9: Extract FASTA sequences for Arm SoloLTRs
#'
#' Extracts genomic sequences for Arm-region soloLTRs using coordinates
#' from the Arm annotation table. FASTA headers follow the format:
#' {Sample}|{Superfamily}|{Region}|{solo_id}
#'
#' @param params CenSoloLTRConfig object
#' @export
step9_extract_arm_fasta <- function(params) {
  step_header(params, "5", 9, "Extract Arm FASTA Sequences")
  if (!should_run_step(9, params)) {
    log_msg(params, "[SKIP] Step 9 disabled by user.")
    return(invisible(NULL))
  }

  sample    <- params$sample_name
  genome_fa <- params$genome_file

  tsv_path <- file.path(params$dirs$arm_anno,
                        paste0(sample, "_Arm_SoloLTR.tsv"))
  out_fa   <- file.path(params$dirs$arm_fasta,
                        paste0(sample, "_Arm_SoloLTR.fa"))

  if (step_already_done(out_fa)) {
    log_msg(params, sprintf("[RESUME] Arm FASTA already exists, skipping."))
    return(invisible(out_fa))
  }

  if (!file.exists(tsv_path)) {
    stop("[Step 9] Arm annotation not found. Run Step 8 first.")
  }

  df <- readr::read_tsv(tsv_path, col_types = readr::cols(.default = "c"))
  if (nrow(df) == 0) {
    log_msg(params, "Step 9: No records to extract.")
    return(invisible(NULL))
  }

  df$start <- as.numeric(df$start)
  df$end   <- as.numeric(df$end)

  genome_seqs <- Biostrings::readDNAStringSet(genome_fa)
  genome_seqs <- clean_fasta_names(genome_seqs)

  valid_idx <- df$chr %in% names(genome_seqs)
  if (sum(!valid_idx) > 0) {
    warning(sprintf("[Step 9] %d records with missing chromosomes skipped.",
                    sum(!valid_idx)))
    df <- df[valid_idx, ]
  }

  if (nrow(df) == 0) {
    log_msg(params, "Step 9: No valid records to extract.")
    return(invisible(NULL))
  }

  extracted_seqs <- Biostrings::subseq(genome_seqs[df$chr],
                                        start = df$start, end = df$end)

  superfamily_clean <- ifelse(is.na(df$Superfamily), "Unclassified", df$Superfamily)
  new_headers <- sprintf("%s|%s|%s|%s",
                         sample, superfamily_clean, df$Region, df$solo_id)
  names(extracted_seqs) <- new_headers

  Biostrings::writeXStringSet(extracted_seqs, out_fa)
  log_msg(params, sprintf("Step 9 complete: %d sequences -> %s",
                          length(extracted_seqs), basename(out_fa)))
  invisible(out_fa)
}
