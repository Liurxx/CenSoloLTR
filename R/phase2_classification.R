# =========================================================================
# LTRtrace - Phase 2: SoloLTR Classification
# =========================================================================
# Step 3: BLAST classify soloLTRs against NR LTR library
# Step 4: Deep annotation rescue for CEN/Peri-CEN Unclassified
# =========================================================================

#' Step 3: Classify soloLTRs via BLASTn against NR LTR library
#'
#' Extracts soloLTR genomic sequences, runs BLASTn against the
#' non-redundant LTR library, and assigns superfamily based on
#' best bitscore hit.
#'
#' @param params LTRtraceConfig object
#' @export
step3_classify_sololtr <- function(params) {
  step_header(params, "3", 8, "BLAST Classify SoloLTRs")
  if (!should_run_step(3, params)) {
    log_msg(params, "[SKIP] Step 3 disabled by user.")
    return(invisible(NULL))
  }

  sample     <- params$sample_name
  short_name <- gsub("^[A-Z][a-z]+_", "", sample)
  genome_fa  <- params$genome_file

  final_out <- file.path(params$dirs$classify,
                         paste0(sample, "_final_classification.tsv"))

  if (step_already_done(final_out)) {
    log_msg(params, sprintf("[RESUME] Classification already exists, skipping."))
    return(invisible(final_out))
  }

  # Locate input files
  if (!params$skip_phase0) {
    solo_list_path <- file.path(params$dirs$sololtr, paste0(sample, ".solo_list"))
  } else {
    solo_list_path <- find_input(params, "\\.solo_list$", "solo_list")
  }
  nr_lib_path <- get_nr_lib_path(params)

  if (!file.exists(solo_list_path)) {
    stop("[Step 3] solo_list not found. Run Phase 0 or provide path.")
  }
  if (!file.exists(nr_lib_path)) {
    stop("[Step 3] NR LTR library not found. Run Step 2 or provide path.")
  }

  dir.create(params$dirs$classify, showWarnings = FALSE, recursive = TRUE)

  # Paths
  extracted_fa  <- file.path(params$dirs$classify,
                             paste0(sample, "_extracted_soloLTR.fasta"))
  query_short_fa <- file.path(params$dirs$classify,
                              paste0(sample, "_extracted_soloLTR.shortid.fasta"))
  query_map_file <- file.path(params$dirs$classify,
                              paste0(sample, "_query_id_mapping.tsv"))
  db_short_fa    <- file.path(params$dirs$classify,
                              paste0(sample, "_NR_LTR_library.shortid.fasta"))
  db_map_file    <- file.path(params$dirs$classify,
                              paste0(sample, "_db_id_mapping.tsv"))
  db_prefix      <- file.path(params$dirs$classify,
                              paste0(sample, "_NR_LTR_library.shortid"))
  blast_out      <- file.path(params$dirs$classify,
                              paste0(sample, "_blast_results.tsv"))

  # ---- 3a. Extract soloLTR sequences ----
  log_msg(params, "Extracting soloLTR sequences ...")

  solo_df <- utils::read.table(solo_list_path, sep = "\t", header = FALSE,
                                stringsAsFactors = FALSE)
  colnames(solo_df) <- c("chr", "start", "end", "solo_id", "ref_ltr", "te_sorter_score")

  genome_seqs <- Biostrings::readDNAStringSet(genome_fa)
  genome_seqs <- clean_fasta_names(genome_seqs)

  valid_idx <- solo_df$chr %in% names(genome_seqs)
  if (!any(valid_idx)) stop("[Step 3] No valid chromosomes in solo_list.")
  solo_df_valid <- solo_df[valid_idx, , drop = FALSE]

  starts <- pmin(solo_df_valid$start, solo_df_valid$end)
  ends   <- pmax(solo_df_valid$start, solo_df_valid$end)

  chr_lens <- Biostrings::width(genome_seqs[solo_df_valid$chr])
  starts[starts < 1] <- 1
  ends <- pmin(ends, chr_lens)

  solo_seqs <- Biostrings::subseq(genome_seqs[solo_df_valid$chr],
                                   start = starts, end = ends)
  names(solo_seqs) <- solo_df_valid$solo_id
  Biostrings::writeXStringSet(solo_seqs, extracted_fa)
  log_msg(params, sprintf("  Extracted %d soloLTR sequences.", length(solo_seqs)))

  # ---- 3b. Short-ID FASTA files for BLAST ----
  log_msg(params, "Preparing BLAST inputs ...")
  query_map <- write_short_id_fasta(extracted_fa, query_short_fa,
                                     query_map_file, prefix = "QSEQ")
  db_map <- write_short_id_fasta(nr_lib_path, db_short_fa,
                                  db_map_file, prefix = "DBSEQ")

  # ---- 3c. Build BLAST DB and run BLASTn ----
  log_msg(params, "Running BLASTn ...")

  if (!build_blast_db(db_short_fa, db_prefix, params$makeblastdb_path)) {
    stop("[Step 3] BLAST database build failed.")
  }

  blast_status <- run_blastn(query_short_fa, db_prefix, blast_out,
                              params$blastn_path, params$threads,
                              params$blast_evalue)
  if (blast_status != 0) {
    warning("[Step 3] blastn exited with non-zero status.")
  }

  # ---- 3d. Parse results and classify ----
  log_msg(params, "Parsing BLAST results ...")

  if (file.exists(blast_out) && file.info(blast_out)$size > 0) {
    blast_res <- utils::read.table(blast_out, sep = "\t", header = FALSE,
                                   stringsAsFactors = FALSE)
    colnames(blast_res) <- c("qseqid", "sseqid", "pident", "aln_length",
                              "mismatch", "gap", "evalue", "bitscore")

    blast_res <- blast_res %>%
      dplyr::left_join(query_map, by = c("qseqid" = "short_id")) %>%
      dplyr::rename(solo_id = original_id) %>%
      dplyr::left_join(db_map, by = c("sseqid" = "short_id")) %>%
      dplyr::rename(target_ltr_id = original_id)

    best_hits <- blast_res %>%
      dplyr::filter(!is.na(solo_id), !is.na(target_ltr_id)) %>%
      dplyr::group_by(solo_id) %>%
      dplyr::slice_max(order_by = bitscore, n = 1, with_ties = FALSE) %>%
      dplyr::ungroup() %>%
      dplyr::mutate(Superfamily = extract_superfamily(target_ltr_id))

    final_result <- solo_df %>%
      dplyr::left_join(best_hits %>%
                         dplyr::select(solo_id, target_ltr_id, pident,
                                        aln_length, mismatch, gap, evalue,
                                        bitscore, Superfamily),
                       by = "solo_id") %>%
      dplyr::mutate(Superfamily = ifelse(is.na(Superfamily), "Unclassified",
                                          Superfamily))
  } else {
    final_result <- solo_df %>%
      dplyr::mutate(target_ltr_id = NA, pident = NA, aln_length = NA,
                    mismatch = NA, gap = NA, evalue = NA, bitscore = NA,
                    Superfamily = "Unclassified")
  }

  utils::write.table(final_result, final_out, sep = "\t", quote = FALSE,
                      row.names = FALSE)

  n_classified <- sum(final_result$Superfamily != "Unclassified")
  log_msg(params, sprintf("Step 3 complete: %d/%d classified → %s",
                          n_classified, nrow(final_result), basename(final_out)))
  invisible(final_out)
}

#' Step 4: Deep annotation rescue for CEN/Peri-CEN Unclassified
#'
#' For soloLTRs in centromere/pericentromere regions that were classified
#' as Unclassified in Step 3, this step performs a relaxed BLAST search
#' to attempt rescue classification.
#'
#' @param params LTRtraceConfig object
#' @export
step4_deep_annotation <- function(params) {
  step_header(params, "4", 9, "Deep Annotation: CEN/Peri-CEN Rescue")
  if (!should_run_step(4, params)) {
    log_msg(params, "[SKIP] Step 4 disabled by user.")
    return(invisible(NULL))
  }

  sample    <- params$sample_name
  genome_fa <- params$genome_file
  cen_bed   <- params$cen_bed_file

  full_out <- file.path(params$dirs$full_anno,
                        paste0(sample, "_Full_Integrated.tsv"))

  if (step_already_done(full_out)) {
    log_msg(params, sprintf("[RESUME] Full annotation already exists, skipping."))
    return(invisible(full_out))
  }

  # Locate inputs
  v1_anno <- file.path(params$dirs$classify,
                       paste0(sample, "_final_classification.tsv"))
  nr_lib  <- get_nr_lib_path(params)
  fai_file <- file.path(dirname(genome_fa),
                        paste0(basename(genome_fa), ".fai"))

  if (!file.exists(v1_anno)) stop("[Step 4] classification file not found.")
  if (!file.exists(nr_lib))  stop("[Step 4] NR library not found.")
  # Init debug log for Step 4
  debug_log <- init_debug_log(params$dirs$full_anno, "phase4_deep_annotation")

  if (!file.exists(fai_file)) {
    # Try to generate .fai if missing
    log_msg(params, "Generating genome index (.fai) ...")
    run_external(paste("samtools faidx", shQuote(genome_fa)),
                 stderr_log = debug_log, echo_label = "samtools faidx")
    fai_file <- paste0(genome_fa, ".fai")
  }

  # Read data
  df_fai  <- readr::read_tsv(fai_file, col_names = c("chr", "chr_len", "off", "b1", "b2"),
                              show_col_types = FALSE)
  df_cen  <- readr::read_tsv(cen_bed, col_names = c("chr", "cen_start", "cen_end"),
                              show_col_types = FALSE)
  df_solo <- readr::read_tsv(v1_anno, show_col_types = FALSE)

  # Compute CEN/Peri-CEN regions
  df_regions <- df_cen %>%
    dplyr::left_join(df_fai %>% dplyr::select(chr, chr_len), by = "chr") %>%
    dplyr::mutate(
      ext = as.numeric(params$peri_extension_bp),
      peri_up_s = pmax(1, cen_start - ext),
      peri_dn_e = pmin(chr_len, cen_end + ext)
    )

  df_merge <- df_solo %>%
    dplyr::left_join(df_regions, by = "chr") %>%
    dplyr::mutate(
      Region = dplyr::case_when(
        (start >= cen_start & end <= cen_end) ~ "Centromere",
        (start >= peri_up_s & end <= cen_start) |
          (start >= cen_end & end <= peri_dn_e) ~ "Pericentromere",
        TRUE ~ "Arm"
      )
    )

  to_rescue <- df_merge %>%
    dplyr::filter(Region %in% c("Centromere", "Pericentromere"),
                  Superfamily == "Unclassified")

  if (nrow(to_rescue) == 0) {
    log_msg(params, "  No unclassified CEN/Peri-CEN sequences to rescue.")
    final_out <- df_merge %>%
      dplyr::mutate(Confidence = ifelse(Superfamily == "Unclassified",
                                         "None", "High_Confidence"))
    cols_keep <- setdiff(colnames(df_solo), c("Region", "Confidence"))
    readr::write_tsv(final_out %>% dplyr::select(dplyr::any_of(c(cols_keep, "Region", "Confidence"))),
                     full_out)
    return(invisible(full_out))
  }

  log_msg(params, sprintf("  Rescuing %d unclassified CEN/Peri-CEN sequences ...",
                          nrow(to_rescue)))

  # Rescue BLAST
  genome_seqs <- Biostrings::readDNAStringSet(genome_fa)
  genome_seqs <- clean_fasta_names(genome_seqs)
  rescue_dna <- Biostrings::subseq(genome_seqs[to_rescue$chr],
                                    start = to_rescue$start, end = to_rescue$end)
  names(rescue_dna) <- to_rescue$solo_id

  tmp_q_fa <- file.path(params$dirs$full_anno, paste0(sample, "_tmp_q.fa"))
  Biostrings::writeXStringSet(rescue_dna, tmp_q_fa)

  tmp_db_dir <- file.path(params$dirs$full_anno, paste0(sample, "_tmp_db"))
  dir.create(tmp_db_dir, showWarnings = FALSE, recursive = TRUE)
  db_prefix <- file.path(tmp_db_dir, "lib")

  run_external(paste(shQuote(params$makeblastdb_path), "-in", shQuote(nr_lib),
               "-dbtype nucl -out", shQuote(db_prefix)),
               stderr_log = debug_log, echo_label = "makeblastdb (rescue)")

  rescue_out <- file.path(params$dirs$full_anno, paste0(sample, "_tmp_res.tsv"))
  run_external(paste(shQuote(params$blastn_path),
               "-query", shQuote(tmp_q_fa),
               "-db", shQuote(db_prefix),
               "-out", shQuote(rescue_out),
               "-outfmt '6 qseqid sseqid pident bitscore'",
               "-evalue", params$blast_evalue_rescue,
               "-word_size 7 -dust no -max_target_seqs 1",
               "-num_threads", params$threads),
               stderr_log = debug_log, echo_label = "blastn (rescue)")

  if (file.exists(rescue_out) && file.info(rescue_out)$size > 0) {
    res <- readr::read_tsv(rescue_out,
                           col_names = c("solo_id", "t_id_new", "pi_new", "bs_new"),
                           show_col_types = FALSE) %>%
      dplyr::group_by(solo_id) %>%
      dplyr::slice_max(bs_new, n = 1, with_ties = FALSE) %>%
      dplyr::ungroup() %>%
      dplyr::mutate(sf_new = extract_superfamily(t_id_new))

    df_final <- df_merge %>%
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
    df_final <- df_merge %>%
      dplyr::mutate(Confidence = ifelse(Superfamily == "Unclassified",
                                         "Still_Unclassified", "High_Confidence"))
  }

  cols_keep <- setdiff(colnames(df_solo), c("Region", "Confidence"))
  readr::write_tsv(df_final %>% dplyr::select(dplyr::any_of(c(cols_keep, "Region", "Confidence"))),
                   full_out)

  # Preserve rescue intermediate files for debugging
  unlink(tmp_db_dir, recursive = TRUE)

  rescued_n <- sum(df_final$Confidence == "Low_Confidence_Rescued", na.rm = TRUE)
  log_msg(params, sprintf("Step 4 complete: %d rescued → %s", rescued_n,
                          basename(full_out)))
  invisible(full_out)
}

#' Find input file by pattern (for --skip-phase0 mode)
#' @noRd
find_input <- function(params, pattern, description) {
  candidates <- list.files(params$outdir, pattern = pattern,
                           recursive = TRUE, full.names = TRUE)
  if (length(candidates) > 0) return(candidates[1])
  stop(sprintf("[find_input] %s not found. Run Phase 0 or provide path.", description))
}
