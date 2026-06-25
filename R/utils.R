# =========================================================================
# LTRtrace - Utility Functions
# =========================================================================

#' Safe wrapper for system() calls to external tools
#'
#' IMPORTANT: R's system(ignore.stdout=TRUE) appends ">/dev/null" to the
#' shell command, which OVERRIDES any existing "> file" redirect in the
#' command string. This function detects that conflict and forces
#' ignore.stdout=FALSE when the command already has its own redirect.
#'
#' It also captures stderr to a debug log for diagnostics.
#'
#' @param cmd Shell command to execute
#' @param wd Working directory (optional, restored on exit)
#' @param stderr_log Path to stderr log file (optional, appended per call)
#' @param echo_cmd Whether to write the command to a command log (default TRUE)
#' @param echo_label Short label for the command log entry
#' @return Exit status of the command (invisible integer)
#' @noRd
run_external <- function(cmd, wd = NULL, stderr_log = NULL,
                         echo_cmd = TRUE, echo_label = NULL) {
  # Detect if cmd already contains shell-level stdout redirect
  has_stdout_redirect <- grepl("\\s+(>|>>)\\s*\\S", cmd)

  # When cmd has its own redirect, ignore.stdout MUST be FALSE
  # because R's ignore.stdout=TRUE appends '>/dev/null' to the shell
  # command, which overrides the cmd-level redirect
  use_ignore_stdout <- !has_stdout_redirect

  # Resolve stderr_log to absolute path BEFORE changing working directory
  if (!is.null(stderr_log) && nzchar(stderr_log)) {
    stderr_log <- normalizePath(stderr_log, mustWork = FALSE)
  }

  # Prepend conda env bin to PATH so LTR_retriever and other tools
  # can find their dependencies (RepeatMasker, etc.) in the env
  cmd_final <- cmd
  conda_bin <- getOption("ltrtrace_conda_bin", NULL)
  if (!is.null(conda_bin) && nzchar(conda_bin) && dir.exists(conda_bin)) {
    cmd_final <- sprintf("export PATH=%s:$PATH; %s", shQuote(conda_bin), cmd_final)
  }

  # Append stderr capture if requested
  if (!is.null(stderr_log) && nzchar(stderr_log)) {
    cmd_final <- sprintf("(%s) 2>>%s", cmd_final, shQuote(stderr_log))
  }

  # Log the command
  if (echo_cmd) {
    label <- if (!is.null(echo_label)) echo_label else "run_external"
    msg <- sprintf("[%s] %s", label, cmd)
    message(msg)
  }

  # Change working directory if requested
  wd_orig <- getwd()
  if (!is.null(wd) && dir.exists(wd)) setwd(wd)
  on.exit(setwd(wd_orig), add = TRUE)

  ret <- system(cmd_final, ignore.stdout = use_ignore_stdout,
                ignore.stderr = is.null(stderr_log))

  invisible(ret)
}

#' Initialize a per-phase command/debug log file
#'
#' @param dir_path Directory for the log file
#' @param phase_name Phase name for the log filename
#' @return Path to the log file
#' @noRd
init_debug_log <- function(dir_path, phase_name) {
  dir.create(dir_path, showWarnings = FALSE, recursive = TRUE)
  log_file <- file.path(dir_path, sprintf(".debug_%s.log", phase_name))
  cat(sprintf("# LTRtrace Debug Log — %s\n", phase_name),
      sprintf("# Started: %s\n", Sys.time()),
      file = log_file, sep = "", append = FALSE)
  return(log_file)
}

#' Clean FASTA names: keep only the first whitespace-delimited token
#' @param x DNAStringSet object
#' @return DNAStringSet with cleaned names
#' @export
clean_fasta_names <- function(x) {
  names(x) <- stringr::str_extract(names(x), "^[^\\s]+")
  x
}

#' Generate short IDs for BLAST compatibility
#'
#' BLAST has issues with long sequence IDs. This function creates short
#' identifiers and a mapping table for downstream ID recovery.
#'
#' @param input_fasta Path to input FASTA file
#' @param output_fasta Path to output short-ID FASTA file
#' @param mapping_tsv Path to write ID mapping table
#' @param prefix Prefix for short IDs (e.g. "QSEQ", "DBSEQ")
#' @return data.frame with short_id and original_id columns
#' @export
write_short_id_fasta <- function(input_fasta, output_fasta, mapping_tsv,
                                  prefix = "SEQ") {
  seqs <- Biostrings::readDNAStringSet(input_fasta)
  seqs <- clean_fasta_names(seqs)

  original_ids <- names(seqs)
  short_ids    <- sprintf("%s%06d", prefix, seq_along(seqs))

  mapping_df <- data.frame(
    short_id    = short_ids,
    original_id = original_ids,
    stringsAsFactors = FALSE
  )

  names(seqs) <- short_ids
  Biostrings::writeXStringSet(seqs, output_fasta)
  utils::write.table(mapping_df, mapping_tsv, sep = "\t",
                      quote = FALSE, row.names = FALSE)

  return(mapping_df)
}

#' Resolve tool path: use explicit path or search PATH
#' @param explicit_path User-provided path or NULL
#' @param tool_name Name of the tool for which() lookup
#' @return Resolved path or NULL
#' @noRd
resolve_tool <- function(explicit_path, tool_name) {
  if (!is.null(explicit_path) && explicit_path != "auto") {
    if (file.exists(explicit_path)) return(explicit_path)
    warning("Tool path not found: ", explicit_path)
    return(NULL)
  }
  resolved <- Sys.which(tool_name)
  if (nzchar(resolved)) return(resolved)
  return(NULL)
}

#' BLAST database rebuild helper
#' Cleans old index files and builds fresh BLAST database
#' @param fasta_file Path to FASTA for database
#' @param db_prefix Output prefix for BLAST database
#' @param makeblastdb_path Path to makeblastdb
#' @param debug_log Optional stderr debug log path
#' @noRd
build_blast_db <- function(fasta_file, db_prefix, makeblastdb_path,
                           debug_log = NULL) {
  old_ext <- c(".nhr", ".nin", ".nsq", ".ndb", ".not", ".ntf", ".nto")
  for (ext in old_ext) {
    f <- paste0(db_prefix, ext)
    if (file.exists(f)) file.remove(f)
  }
  cmd <- paste(
    shQuote(makeblastdb_path),
    "-in", shQuote(fasta_file),
    "-dbtype nucl",
    "-parse_seqids",
    "-out", shQuote(db_prefix)
  )
  status <- run_external(cmd, stderr_log = debug_log, echo_label = "makeblastdb")
  if (status != 0) return(FALSE)
  return(file.exists(paste0(db_prefix, ".nhr")))
}

#' Run BLASTn with standard parameters
#' @param query_fa Query FASTA path
#' @param db_prefix BLAST database prefix
#' @param out_file Output TSV path
#' @param blastn_path Path to blastn
#' @param threads Number of threads
#' @param evalue E-value cutoff
#' @param extra_args Additional blastn arguments
#' @param debug_log Optional stderr debug log path
#' @noRd
run_blastn <- function(query_fa, db_prefix, out_file, blastn_path,
                        threads, evalue, extra_args = "", debug_log = NULL) {
  cmd <- paste(
    shQuote(blastn_path),
    "-query", shQuote(query_fa),
    "-db", shQuote(db_prefix),
    "-out", shQuote(out_file),
    "-outfmt", shQuote("6 qseqid sseqid pident length mismatch gapopen evalue bitscore"),
    "-num_threads", threads,
    "-evalue", evalue,
    extra_args
  )
  return(run_external(cmd, stderr_log = debug_log, echo_label = "blastn"))
}

#' Check if a step's output already exists (for resume support)
#' @param outfile Expected output file path
#' @return TRUE if output already exists
#' @noRd
step_already_done <- function(outfile) {
  file.exists(outfile) && file.info(outfile)$size > 0
}

#' Print a step header
#' @noRd
step_header <- function(params, phase, step, description) {
  if (params$quiet) return()
  message("\n")
  message(rep("=", 62))
  message(sprintf("  Phase %s | Step %s | %s", phase, step, description))
  message(rep("=", 62))
}

#' Print step completion
#' @noRd
step_done <- function(params, msg = "Done.") {
  if (params$quiet) return()
  message(msg)
}

#' Scan genome for BLAST hits to detect soloLTRs
#'
#' Uses blastn -task blastn-short for short fragment detection.
#' Returns BED-style coordinates of candidate regions.
#'
#' @param query_fa Query FASTA (NR LTR library)
#' @param genome_fa Subject FASTA (genome)
#' @param out_file Output file path
#' @param blastn_path Path to blastn
#' @param threads Threads
#' @noRd
genome_blast_scan <- function(query_fa, genome_fa, out_file,
                               blastn_path, threads, evalue = 1e-5,
                               debug_log = NULL) {
  cmd <- paste(
    shQuote(blastn_path),
    "-query", shQuote(query_fa),
    "-subject", shQuote(genome_fa),
    "-out", shQuote(out_file),
    "-outfmt '6 qseqid sseqid pident length qstart qend sstart send evalue bitscore'",
    "-num_threads", threads,
    "-evalue", evalue,
    "-max_target_seqs 10000"
  )
  return(run_external(cmd, stderr_log = debug_log, echo_label = "genome_blast_scan"))
}

#' Extract superfamily from LTR library sequence ID
#'
#' NR library IDs have format: Superfamily_Clade_Domain1_Domain2_..._N
#' This function extracts the second field (Clade) as the superfamily identifier.
#'
#' @param id Character vector of sequence IDs
#' @return Character vector of superfamily names
#' @export
extract_superfamily <- function(id) {
  sapply(stringr::str_split(id, "_"), function(x) {
    if (length(x) >= 2) x[2] else "Unclassified"
  }, USE.NAMES = FALSE)
}
