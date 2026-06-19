# =========================================================================
# CenSoloLTR - Phase 0: De Novo LTR Annotation
# =========================================================================
# Steps 0a-0e:
#   0a: LTR_FINDER_parallel  → de novo LTR detection (SCN output)
#   0b: LTR_HARVEST_parallel → genome-tools LTR harvest (SCN output)
#   0c: LTR_retriever        → merge SCN + filter high-confidence LTRs
#   0d: TEsorter             → classify intact LTRs by superfamily
#   0e: SoloLTR detection    → find_LTR.pl + solo_finder.pl
#
# Uses LTR_FINDER_parallel and LTR_HARVEST_parallel (Perl wrappers from
# Shujun Ou) instead of custom R-native genome chunking.
# =========================================================================

# ---- Phase 0 Helpers ----

#' Merge multiple SCN files into one, filtering out comment/header lines
#' @noRd
merge_scn_files <- function(scn_files, out_file) {
  all_lines <- character(0)
  n_filtered <- 0
  for (f in scn_files) {
    if (!file.exists(f) || file.info(f)$size == 0) next
    lines <- readLines(f)
    lines <- lines[nchar(lines) > 0 & !grepl("^#", lines)]
    if (length(lines) > 0) {
      n_filtered <- n_filtered + length(lines)
      all_lines <- c(all_lines, lines)
    }
  }
  writeLines(all_lines, out_file)
  message(sprintf("  Merged %d SCN files -> %d lines -> %s",
                  length(scn_files), n_filtered, basename(out_file)))
  invisible(out_file)
}

# ---- Phase 0 Steps ----

#' Step 0a: Run LTR_FINDER_parallel
#'
#' Uses the LTR_FINDER_parallel Perl wrapper to split the genome, run
#' ltr_finder on each chunk in parallel, and merge results into SCN format.
#'
#' @param params CenSoloLTRConfig object
#' @export
step0a_ltr_finder <- function(params) {
  step_header(params, "0a", 1, "LTR_FINDER (LTR_FINDER_parallel)")
  if (!should_run_step(0, params)) {
    log_msg(params, "[SKIP] Step 0a disabled by user.")
    return(invisible(NULL))
  }

  genome_fa <- params$genome_file
  out_scn   <- file.path(params$dirs$finder,
                         paste0(params$sample_name, ".finder.combine.scn"))

  if (step_already_done(out_scn)) {
    log_msg(params, sprintf("[RESUME] %s already exists, skipping.", basename(out_scn)))
    return(invisible(out_scn))
  }

  if (is.null(params$ltr_finder_pp_path) || !nzchar(params$ltr_finder_pp_path)) {
    stop("[Step 0a] LTR_FINDER_parallel not found. Install: conda install -c bioconda ltr_finder_parallel")
  }

  debug_log <- init_debug_log(params$dirs$finder, "phase0a_ltr_finder")
  dir.create(params$dirs$finder, showWarnings = FALSE, recursive = TRUE)

  log_msg(params, sprintf("Running LTR_FINDER_parallel on %s with %d threads ...",
                          basename(genome_fa), params$ltr_threads))

  # LTR_FINDER_parallel produces:
  #   {genome_prefix}.finder.combine.scn in the working directory
  cmd <- sprintf(
    "%s -seq %s -size 5000000 -overlap 100000 -threads %d -harvest_out -try1 1",
    shQuote(params$ltr_finder_pp_path),
    shQuote(normalizePath(genome_fa)),
    params$ltr_threads
  )

  status <- run_external(cmd, wd = params$dirs$finder,
                         stderr_log = debug_log,
                         echo_label = "LTR_FINDER_parallel")

  if (status != 0) {
    warning("[Step 0a] LTR_FINDER_parallel exited with status ", status,
            ". Check debug log: ", debug_log)
  }

  # Locate the output SCN file (named after the genome file)
  genome_base <- basename(genome_fa)
  expected <- file.path(params$dirs$finder,
                        paste0(genome_base, ".finder.combine.scn"))

  if (file.exists(expected) && file.info(expected)$size > 0) {
    if (expected != out_scn) {
      file.rename(expected, out_scn)
      log_msg(params, sprintf("Renamed: %s -> %s",
                              basename(expected), basename(out_scn)))
    }
  } else if (file.exists(out_scn) && file.info(out_scn)$size > 0) {
    # Already correctly named
  } else {
    stop("[Step 0a] LTR_FINDER_parallel did not produce expected output. ",
         "Expected: ", basename(expected), ". Check debug log: ", debug_log)
  }

  log_msg(params, sprintf("Step 0a complete: %s", basename(out_scn)))
  invisible(out_scn)
}

#' Step 0b: Run LTR_HARVEST_parallel
#'
#' Uses the LTR_HARVEST_parallel wrapper to split the genome, run
#' gt ltrharvest on each chunk in parallel, and merge into SCN format.
#'
#' @param params CenSoloLTRConfig object
#' @export
step0b_ltr_harvest <- function(params) {
  step_header(params, "0b", 2, "LTR_HARVEST (LTR_HARVEST_parallel)")
  if (!should_run_step(0, params)) {
    log_msg(params, "[SKIP] Step 0b disabled by user.")
    return(invisible(NULL))
  }

  genome_fa <- params$genome_file
  out_scn   <- file.path(params$dirs$harvest,
                         paste0(params$sample_name, ".harvest.combine.scn"))

  if (step_already_done(out_scn)) {
    log_msg(params, sprintf("[RESUME] %s already exists, skipping.", basename(out_scn)))
    return(invisible(out_scn))
  }

  if (is.null(params$ltr_harvest_pp_path) || !nzchar(params$ltr_harvest_pp_path)) {
    stop("[Step 0b] LTR_HARVEST_parallel not found. Install: conda install -c bioconda ltr_harvest_parallel")
  }

  debug_log <- init_debug_log(params$dirs$harvest, "phase0b_ltr_harvest")
  dir.create(params$dirs$harvest, showWarnings = FALSE, recursive = TRUE)

  log_msg(params, sprintf("Running LTR_HARVEST_parallel on %s with %d threads ...",
                          basename(genome_fa), params$ltr_threads))

  cmd <- sprintf(
    "%s -seq %s -size 5000000 -overlap 100000 -threads %d -try1 1",
    shQuote(params$ltr_harvest_pp_path),
    shQuote(normalizePath(genome_fa)),
    params$ltr_threads
  )

  status <- run_external(cmd, wd = params$dirs$harvest,
                         stderr_log = debug_log,
                         echo_label = "LTR_HARVEST_parallel")

  if (status != 0) {
    warning("[Step 0b] LTR_HARVEST_parallel exited with status ", status,
            ". Check debug log: ", debug_log)
  }

  # Locate the output SCN file
  genome_base <- basename(genome_fa)
  expected <- file.path(params$dirs$harvest,
                        paste0(genome_base, ".harvest.combine.scn"))

  if (file.exists(expected) && file.info(expected)$size > 0) {
    if (expected != out_scn) {
      file.rename(expected, out_scn)
      log_msg(params, sprintf("Renamed: %s -> %s",
                              basename(expected), basename(out_scn)))
    }
  } else if (file.exists(out_scn) && file.info(out_scn)$size > 0) {
    # Already correctly named
  } else {
    stop("[Step 0b] LTR_HARVEST_parallel did not produce expected output. ",
         "Expected: ", basename(expected), ". Check debug log: ", debug_log)
  }

  log_msg(params, sprintf("Step 0b complete: %s", basename(out_scn)))
  invisible(out_scn)
}

#' Step 0c: Merge SCN files and run LTR_retriever
#'
#' Combines LTR_FINDER and LTR_HARVEST SCN outputs, then runs LTR_retriever
#' to filter high-confidence intact LTR elements.
#'
#' Outputs: .pass.list, .pass.list.gff3, .out, .LTRlib.fa
#'
#' @param params CenSoloLTRConfig object
#' @export
step0c_ltr_retriever <- function(params) {
  step_header(params, "0c", 3, "Merge SCN + LTR_retriever")
  if (!should_run_step(0, params)) {
    log_msg(params, "[SKIP] Step 0c disabled by user.")
    return(invisible(NULL))
  }

  genome_fa <- params$genome_file
  sample    <- params$sample_name

  finder_scn  <- file.path(params$dirs$finder,
                           paste0(sample, ".finder.combine.scn"))
  harvest_scn <- file.path(params$dirs$harvest,
                           paste0(sample, ".harvest.combine.scn"))
  raw_scn     <- file.path(params$dirs$retriever,
                           paste0(sample, ".rawLTR.scn"))

  pass_list   <- file.path(params$dirs$retriever,
                           paste0(sample, ".genome.fasta.pass.list"))

  if (step_already_done(pass_list)) {
    log_msg(params, sprintf("[RESUME] pass.list already exists, skipping."))
    return(invisible(pass_list))
  }

  debug_log <- init_debug_log(params$dirs$retriever, "phase0c_ltr_retriever")

  # Merge SCN files
  if (file.exists(finder_scn) && file.exists(harvest_scn)) {
    log_msg(params, "Merging LTR_FINDER and LTR_HARVEST SCN outputs ...")
    dir.create(params$dirs$retriever, showWarnings = FALSE, recursive = TRUE)
    finder_lines  <- readLines(finder_scn)
    harvest_lines <- readLines(harvest_scn)
    writeLines(c(finder_lines, harvest_lines), raw_scn)
  } else if (file.exists(finder_scn)) {
    file.copy(finder_scn, raw_scn, overwrite = TRUE)
    log_msg(params, "Only LTR_FINDER output available (LTR_HARVEST not found).")
  } else if (file.exists(harvest_scn)) {
    file.copy(harvest_scn, raw_scn, overwrite = TRUE)
    log_msg(params, "Only LTR_HARVEST output available (LTR_FINDER not found).")
  } else {
    stop("Neither LTR_FINDER nor LTR_HARVEST SCN output found. Cannot proceed.")
  }

  # Symlink genome to retriever dir (LTR_retriever expects it in working dir)
  genome_link <- file.path(params$dirs$retriever,
                           paste0(sample, ".genome.fasta"))
  if (!file.exists(genome_link)) {
    file.symlink(normalizePath(genome_fa), genome_link)
  }

  log_msg(params, "Running LTR_retriever ...")

  cmd <- sprintf(
    "%s -threads %d -genome %s.genome.fasta -inharvest %s.rawLTR.scn",
    shQuote(params$ltr_retriever_path),
    params$ltr_threads,
    sample,
    sample
  )

  # Wrap with timeout if configured (prevents LAI all-vs-all BLAST from
  # running indefinitely; core outputs are produced before LAI starts)
  if (is.finite(params$ltr_retriever_timeout) &&
      params$ltr_retriever_timeout > 0) {
    cmd <- sprintf("timeout --signal=TERM --kill-after=30 %d %s",
                   as.integer(params$ltr_retriever_timeout), cmd)
    log_msg(params, sprintf("  (timeout: %d s)", params$ltr_retriever_timeout))
  }

  status <- run_external(cmd, wd = params$dirs$retriever,
                         stderr_log = debug_log,
                         echo_label = "LTR_retriever")

  # Core outputs needed for downstream steps (0d, 0e, Phase 1)
  # LTR_retriever v3.x inserts ".mod" into output filenames (e.g.
  # .genome.fasta.mod.pass.list), while v2.9.x does not. Handle both.
  mod_pass_list <- file.path(params$dirs$retriever,
                             paste0(sample, ".genome.fasta.mod.pass.list"))
  if (file.exists(mod_pass_list) && file.info(mod_pass_list)$size > 0) {
    # v3.x naming detected — create symlinks to match expected v2.9.x names
    mod_prefix  <- paste0(sample, ".genome.fasta.mod")
    norm_prefix <- paste0(sample, ".genome.fasta")
    mod_files <- list.files(params$dirs$retriever,
                            pattern = paste0("^", sample, "\\.genome\\.fasta\\.mod\\."),
                            full.names = TRUE)
    for (mf in mod_files) {
      norm_name <- file.path(params$dirs$retriever,
                             sub(paste0("\\.genome\\.fasta\\.mod\\."), ".genome.fasta.", basename(mf)))
      if (!file.exists(norm_name)) file.symlink(basename(mf), norm_name)
    }
    log_msg(params, "LTR_retriever v3.x (.mod) naming detected — symlinks created.")
  }

  essential <- c(
    pass_list,
    file.path(params$dirs$retriever, paste0(sample, ".genome.fasta.pass.list.gff3")),
    file.path(params$dirs$retriever, paste0(sample, ".genome.fasta.nmtf.pass.list")),
    file.path(params$dirs$retriever, paste0(sample, ".genome.fasta.LTRlib.fa"))
  )
  essential_exist <- file.exists(essential) & file.info(essential)$size > 0

  # timeout exit codes: 124 (timeout), 137 (SIGKILL from --kill-after)
  if (status %in% c(124, 137)) {
    if (all(essential_exist)) {
      log_msg(params, "LTR_retriever timed out at LAI step, but all core outputs exist — continuing.")
    } else {
      warning("[Step 0c] LTR_retriever timed out and core outputs are missing. ",
              "Consider increasing --ltr-retriever-timeout. ",
              "Check debug log: ", debug_log)
      return(invisible(NULL))
    }
  } else if (status != 0) {
    if (all(essential_exist)) {
      log_msg(params, "LTR_retriever exited non-zero but core outputs exist — continuing.")
    } else {
      warning("[Step 0c] LTR_retriever exited with non-zero status: ", status,
              ". Check debug log: ", debug_log)
    }
  }

  # Report any missing files
  for (f in essential) {
    if (!file.exists(f) || file.info(f)$size == 0) {
      warning("[Step 0c] Expected output not found: ", f)
    }
  }

  log_msg(params, sprintf("Step 0c complete: %s", pass_list))
  invisible(pass_list)
}

#' Step 0d: Extract LTR sequences and run TEsorter
#'
#' Uses seqtk to extract intact LTR sequences from the genome based on
#' pass.list coordinates, then classifies them with TEsorter.
#'
#' @param params CenSoloLTRConfig object
#' @export
step0d_tesorter <- function(params) {
  step_header(params, "0d", 4, "seqtk extract + TEsorter classification")
  if (!should_run_step(0, params)) {
    log_msg(params, "[SKIP] Step 0d disabled by user.")
    return(invisible(NULL))
  }

  genome_fa <- params$genome_file
  sample    <- params$sample_name

  pass_list <- file.path(params$dirs$retriever,
                          paste0(sample, ".genome.fasta.pass.list"))
  cls_tsv   <- file.path(params$dirs$tesorter,
                          paste0(sample, ".rawLTR.fa.rexdb-plant.cls.tsv"))

  if (step_already_done(cls_tsv)) {
    log_msg(params, sprintf("[RESUME] TEsorter result already exists, skipping."))
    return(invisible(cls_tsv))
  }

  if (!file.exists(pass_list)) {
    warning("[Step 0d] pass.list not found. Run Step 0c first.")
    return(invisible(NULL))
  }

  debug_log <- init_debug_log(params$dirs$tesorter, "phase0d_tesorter")

  # Prepare BED file from pass.list
  rawltr_bed <- file.path(params$dirs$tesorter, "rawLTR.bed")
  rawltr_fa  <- file.path(params$dirs$tesorter, paste0(sample, ".rawLTR.fa"))

  lines <- readLines(pass_list)
  bed_lines <- c()
  for (line in lines) {
    if (grepl("^#", line) || line == "") next
    parts <- strsplit(line, "[:.]+")[[1]]
    if (length(parts) >= 3) {
      bed_lines <- c(bed_lines, paste(parts[1], parts[2], parts[3], sep = "\t"))
    }
  }
  writeLines(bed_lines, rawltr_bed)

  log_msg(params, sprintf("Extracting %d LTR sequences with seqtk ...", length(bed_lines)))

  cmd_seqtk <- sprintf(
    "%s subseq %s %s > %s",
    shQuote(params$seqtk_path),
    shQuote(genome_fa),
    shQuote(rawltr_bed),
    shQuote(rawltr_fa)
  )
  run_external(cmd_seqtk, stderr_log = debug_log, echo_label = "seqtk")

  if (!file.exists(rawltr_fa) || file.info(rawltr_fa)$size == 0) {
    stop("[Step 0d] seqtk failed: rawLTR FASTA is missing or empty: ", rawltr_fa)
  }

  log_msg(params, "Running TEsorter (rexdb-plant) ...")
  cmd_tesorter <- sprintf(
    "%s -db rexdb-plant -st nucl -p %d %s",
    shQuote(params$tesorter_path),
    params$ltr_threads,
    shQuote(normalizePath(rawltr_fa, mustWork = FALSE))
  )

  status <- run_external(cmd_tesorter, wd = params$dirs$tesorter,
                         stderr_log = debug_log,
                         echo_label = "TEsorter")

  if (status != 0 || !file.exists(cls_tsv)) {
    stop("[Step 0d] TEsorter failed (exit=", status,
         "). Output not found: ", cls_tsv,
         ". Check debug log: ", debug_log)
  }

  log_msg(params, sprintf("Step 0d complete: %s", cls_tsv))
  invisible(cls_tsv)
}

#' Step 0e: SoloLTR Detection
#'
#' Runs solo_finder.pl to detect soloLTRs from RepeatMasker output.
#' For LTR_retriever v2.9.x, the RM .out file is generated first if missing.
#' For v3.x with find_LTR.pl available, that pre-processing step is included.
#'
#' @param params CenSoloLTRConfig object
#' @export
step0e_sololtr_detect <- function(params) {
  step_header(params, "0e", 5, "SoloLTR Detection (solo_finder.pl)")
  if (!should_run_step(0, params)) {
    log_msg(params, "[SKIP] Step 0e disabled by user.")
    return(invisible(NULL))
  }

  sample <- params$sample_name

  ltrlib_fa <- file.path(params$dirs$retriever,
                          paste0(sample, ".genome.fasta.LTRlib.fa"))
  out_file  <- file.path(params$dirs$retriever,
                          paste0(sample, ".genome.fasta.nmtf.pass.list"))
  genome_fa <- file.path(params$dirs$retriever,
                          paste0(sample, ".genome.fasta"))
  rm_out    <- file.path(params$dirs$retriever,
                          paste0(sample, ".genome.fasta.out"))
  solo_list <- file.path(params$dirs$sololtr,
                          paste0(sample, ".solo_list"))

  if (step_already_done(solo_list)) {
    log_msg(params, sprintf("[RESUME] solo_list already exists, skipping."))
    return(invisible(solo_list))
  }

  if (!file.exists(ltrlib_fa)) {
    warning("[Step 0e] LTRlib.fa not found: ", ltrlib_fa)
    return(invisible(NULL))
  }
  if (!file.exists(out_file)) {
    warning("[Step 0e] .out file not found: ", out_file)
    return(invisible(NULL))
  }

  solo_finder_pl <- params$solo_finder_pl
  if (is.na(solo_finder_pl) || !file.exists(solo_finder_pl)) {
    warning("[Step 0e] solo_finder.pl not found. Check --ltr-retriever-dir or ensure LTR_retriever is installed.")
    return(invisible(NULL))
  }

  debug_log <- init_debug_log(params$dirs$sololtr, "phase0e_sololtr")

  # ---- Generate RepeatMasker .out file if missing (LTR_retriever v2.9.x) ----
  # LTR_retriever v2.9.0 may timeout before the annotation step that creates
  # the .out file. v2.9.x solo_finder.pl reads RM .out format (positional arg),
  # so we need to generate it ourselves if it doesn't exist.
  if (!file.exists(rm_out) || file.info(rm_out)$size == 0) {
    log_msg(params, "RepeatMasker .out file not found, running RepeatMasker ...")
    if (!file.exists(genome_fa)) {
      warning("[Step 0e] Genome symlink not found: ", genome_fa)
      return(invisible(NULL))
    }
    cmd_rm <- sprintf(
      "RepeatMasker -e ncbi -pa %d -q -no_is -norna -nolow -div 40 -lib %s -cutoff 225 %s > /dev/null 2>&1",
      params$ltr_threads, shQuote(basename(ltrlib_fa)), shQuote(basename(genome_fa))
    )
    run_external(cmd_rm, wd = params$dirs$retriever,
                 stderr_log = debug_log, echo_label = "RepeatMasker")
    if (!file.exists(rm_out) || file.info(rm_out)$size == 0) {
      warning("[Step 0e] RepeatMasker failed to produce .out file.")
      return(invisible(NULL))
    }
  } else {
    log_msg(params, sprintf("Using existing RM .out file: %s", rm_out))
  }

  # ---- Detect solo_finder.pl interface (v2.9.x vs v3.x) ----
  # v2.9.x: perl solo_finder.pl RepeatMasker.out > solo_list  (positional arg)
  # v3.x:   perl solo_finder.pl -i out_file -info lib_info > solo_list
  # Detect by scanning the script content: v2.9.x has a usage message
  # "perl this_script.pl RepeatMasker.out > solo_list"
  sf_content <- readLines(solo_finder_pl, warn = FALSE)
  is_v2_solo <- any(grepl("RepeatMasker[.]out\\s*>\\s*solo_list", sf_content,
                           perl = TRUE))

  if (!is_v2_solo) {
    # v3.x path: run find_LTR.pl first, then solo_finder.pl with -i/-info flags
    find_ltr_pl <- params$find_ltr_pl
    if (is.na(find_ltr_pl) || !file.exists(find_ltr_pl)) {
      warning("[Step 0e] find_LTR.pl not found (required for v3.x solo_finder.pl).")
      return(invisible(NULL))
    }
    lib_info <- file.path(params$dirs$sololtr, paste0(sample, ".lib.LTR.info"))
    log_msg(params, "Running find_LTR.pl ...")
    cmd_find <- sprintf(
      "perl %s -lib %s > %s",
      shQuote(find_ltr_pl), shQuote(ltrlib_fa), shQuote(lib_info)
    )
    run_external(cmd_find, stderr_log = debug_log, echo_label = "find_LTR.pl")

    if (!file.exists(lib_info) || file.info(lib_info)$size == 0) {
      warning("[Step 0e] find_LTR.pl produced no output. Skipping solo_finder.pl.")
      return(invisible(NULL))
    }

    log_msg(params, "Running solo_finder.pl (v3.x interface) ...")
    cmd_solo <- sprintf(
      "perl %s -i %s -info %s > %s",
      shQuote(solo_finder_pl), shQuote(rm_out), shQuote(lib_info),
      shQuote(solo_list)
    )
  } else {
    # v2.9.x path: solo_finder.pl reads RM .out format from positional argument
    log_msg(params, "Running solo_finder.pl (v2.9.x interface) ...")
    cmd_solo <- sprintf(
      "perl %s %s > %s",
      shQuote(solo_finder_pl), shQuote(rm_out), shQuote(solo_list)
    )
  }

  run_external(cmd_solo, stderr_log = debug_log, echo_label = "solo_finder.pl")

  # ---- Post-process v2.9.x output to standard 6-column format ----
  # v2.9.x output (2 cols): ref_ltr\tsolo_chr:start..end
  # Standard format (6 cols): chr, start, end, solo_id, ref_ltr, te_sorter_score
  if (is_v2_solo) {
    log_msg(params, "Converting v2.9.x solo_list to standard format ...")
    raw <- utils::read.table(solo_list, sep = "\t", header = FALSE,
                              stringsAsFactors = FALSE, comment.char = "")
    # Parse "chr:start..end" from column 2
    loc_parts <- stringr::str_match(raw[[2]], "^(.+?):(\\d+)\\.\\.(\\d+)$")
    solo_df <- data.frame(
      chr            = loc_parts[, 2],
      start          = as.integer(loc_parts[, 3]),
      end            = as.integer(loc_parts[, 4]),
      solo_id        = sprintf("solo_%05d", seq_len(nrow(raw))),
      ref_ltr        = raw[[1]],
      te_sorter_score = NA_real_,
      stringsAsFactors = FALSE
    )
    utils::write.table(solo_df, solo_list, sep = "\t",
                        row.names = FALSE, col.names = FALSE, quote = FALSE)
    log_msg(params, sprintf("  Converted %d soloLTR entries.", nrow(solo_df)))
  }

  log_msg(params, sprintf("Step 0e complete: %s", solo_list))
  invisible(solo_list)
}
