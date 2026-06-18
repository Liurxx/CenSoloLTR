# =========================================================================
# CenSoloLTR - Command-Line Interface (bioinformatics-style)
# =========================================================================

#' Print package banner
#' @export
print_banner <- function() {
  ver <- tryCatch(as.character(utils::packageVersion("CenSoloLTR")),
                   error = function(e) "unknown")
  cat(sprintf('
╔══════════════════════════════════════════════════════════════╗
║  CenSoloLTR v%-47s║
║  Genome-Centered SoloLTR Annotation for Centromere Regions  ║
║                                                             ║
║  Input:  Genome FASTA + Centromere BED                      ║
║  Output: SoloLTR classification, annotation, FASTA, plots   ║
╚══════════════════════════════════════════════════════════════╝
', ver), "\n")
}

#' Build OptionParser with all CLI options
#' @noRd
build_option_parser <- function() {
  optparse::OptionParser(
    usage = "%prog [options] -g <genome.fa> -c <cen.bed> -o <outdir>",
    description = paste0(
      "CenSoloLTR -- An integrated bioinformatics pipeline for de novo LTR\n",
      "annotation, soloLTR detection, and centromere/pericentromere analysis.\n\n",
      "Starting from a genome FASTA and a centromere BED file, the pipeline\n",
      "executes 5 phases (10 steps) to produce:\n",
      "  - SoloLTR classification (BLAST against non-redundant LTR library)\n",
      "  - Deep CEN/Peri-CEN region annotation with rescue of unclassified hits\n",
      "  - Chromosome arm (Arm) region annotation with BLAST rescue\n",
      "  - FASTA sequence extraction (CEN/Peri-CEN + Arm) with rich headers\n",
      "  - Family composition statistics and publication-ready stacked bar plots\n",
      "    (PDF, SVG, PNG)\n"
    ),
    epilogue = paste0(
      "\nExamples:\n",
      "  # Minimal run:\n",
      "  CenSoloLTR -g genome.fa -c cen.bed -o ./output\n\n",
      "  # With custom threads and tool paths:\n",
      "  CenSoloLTR -g genome.fa -c cen.bed -o ./output -t 32 \\\n",
      "    --tesorter /opt/TEsorter/TEsorter --blastn /usr/bin/blastn\n\n",
      "  # Skip de novo LTR detection (use pre-existing results):\n",
      "  CenSoloLTR -g genome.fa -c cen.bed -o ./output --skip-phase0\n\n",
      "  # Run only specific steps:\n",
      "  CenSoloLTR -g genome.fa -c cen.bed -o ./output --only-step 3,4,5\n\n",
      "Note:\n",
      "  Required external tools: ltr_finder, gt (genometools), LTR_retriever,\n",
      "  TEsorter, seqtk, cd-hit, BLAST+ (makeblastdb, blastn).\n",
      "  If tools are in PATH, auto-detection will find them.\n"
    ),
    option_list = list(

      # ---- Required ----
      optparse::make_option(
        c("-g", "--genome"), type = "character", default = NULL,
        metavar = "FILE",
        help = "[Required] Genome FASTA file"
      ),
      optparse::make_option(
        c("-c", "--cen-bed"), type = "character", default = NULL,
        metavar = "FILE",
        help = "[Required] Centromere region BED file (chr\\tstart\\tend)"
      ),
      optparse::make_option(
        c("-o", "--outdir"), type = "character", default = "./CenSoloLTR_output",
        metavar = "DIR",
        help = "Output directory [default: ./CenSoloLTR_output]"
      ),

      # ---- Threads / Performance ----
      optparse::make_option(
        c("-t", "--threads"), type = "integer", default = 8,
        metavar = "INT",
        help = "Number of CPU threads for BLAST and CD-HIT [default: 8]"
      ),
      optparse::make_option(
        c("--ltr-threads"), type = "integer", default = NULL,
        metavar = "INT",
        help = "Threads for LTR_FINDER/HARVEST/retriever/TEsorter [default: same as --threads]"
      ),

      # ---- Tool Paths ----
      optparse::make_option(
        "--conda-env", type = "character", default = NULL,
        metavar = "NAME_OR_PATH",
        help = "Conda environment name or path for tool resolution. If set, tools are resolved from <env>/bin/ first. Use 'censololtr' for the latest toolset (ltr_finder=1.07, LTR_FINDER_parallel=1.4, LTR_HARVEST_parallel=1.3, gt=1.6.6, LTR_retriever=3.0.5, TEsorter=1.5.1)"
      ),
      optparse::make_option(
        "--ltr-finder", type = "character", default = "auto",
        metavar = "PATH",
        help = "Path to ltr_finder binary [default: auto-detect]"
      ),
      optparse::make_option(
        "--gt", type = "character", default = "auto",
        metavar = "PATH",
        help = "Path to gt (genometools) binary for LTR_HARVEST [default: auto-detect]"
      ),
      optparse::make_option(
        "--ltr-retriever-dir", type = "character", default = NULL,
        metavar = "PATH",
        help = "Path to LTR_retriever share/bin/ directory containing helper scripts [auto-detect]"
      ),
      optparse::make_option(
        "--solo-script-dir", type = "character", default = NULL,
        metavar = "PATH",
        help = "Path to directory containing find_LTR.pl and solo_finder.pl for SoloLTR detection"
      ),
      optparse::make_option(
        "--ltr-retriever", type = "character", default = "auto",
        metavar = "PATH",
        help = "Path to LTR_retriever [default: auto-detect]"
      ),
      optparse::make_option(
        "--ltr-retriever-timeout", type = "integer", default = 1800,
        metavar = "SECONDS",
        help = "Max runtime for LTR_retriever in seconds. LTR_retriever's core outputs (pass.list, LTRlib.fa, .out) are produced within ~15 min; the LAI all-vs-all BLAST afterwards can run for hours and is not needed for soloLTR annotation. After timeout, if core outputs exist, the pipeline continues. [default: 1800 (30 min)]"
      ),
      optparse::make_option(
        "--tesorter", type = "character", default = "auto",
        metavar = "PATH",
        help = "Path to TEsorter [default: auto-detect]"
      ),
      optparse::make_option(
        "--seqtk", type = "character", default = "auto",
        metavar = "PATH",
        help = "Path to seqtk [default: auto-detect]"
      ),
      optparse::make_option(
        "--cd-hit", type = "character", default = "auto",
        metavar = "PATH",
        help = "Path to cd-hit [default: auto-detect]"
      ),
      optparse::make_option(
        "--blastn", type = "character", default = "auto",
        metavar = "PATH",
        help = "Path to blastn [default: auto-detect]"
      ),
      optparse::make_option(
        "--makeblastdb", type = "character", default = "auto",
        metavar = "PATH",
        help = "Path to makeblastdb [default: auto-detect]"
      ),

      # ---- Sample Name ----
      optparse::make_option(
        c("-n", "--sample-name"), type = "character", default = NULL,
        metavar = "NAME",
        help = "Sample name prefix (auto-detected from genome filename if not set)"
      ),

      # ---- CD-HIT Parameters ----
      optparse::make_option(
        "--cdhit-identity", type = "double", default = 0.80,
        metavar = "FLOAT",
        help = "CD-HIT sequence identity cutoff [default: 0.80]"
      ),
      optparse::make_option(
        "--cdhit-coverage", type = "double", default = 0.80,
        metavar = "FLOAT",
        help = "CD-HIT alignment coverage cutoff [default: 0.80]"
      ),

      # ---- BLAST Parameters ----
      optparse::make_option(
        "--blast-evalue", type = "double", default = 1e-5,
        metavar = "FLOAT",
        help = "BLAST e-value cutoff for initial classification [default: 1e-5]"
      ),
      optparse::make_option(
        "--blast-evalue-rescue", type = "double", default = 1.0,
        metavar = "FLOAT",
        help = "BLAST e-value cutoff for CEN/Peri-CEN rescue [default: 1.0]"
      ),

      # ---- CEN/Peri-CEN Parameters ----
      optparse::make_option(
        "--peri-extension-bp", type = "integer", default = 500000,
        metavar = "INT",
        help = "Peri-CEN extension length in bp (fixed distance up/downstream of CEN) [default: 500000]"
      ),

      # ---- Plot Parameters ----
      optparse::make_option(
        "--top-families", type = "integer", default = 15,
        metavar = "INT",
        help = "Number of top LTR families to display in plots [default: 15]"
      ),

      # ---- Fabaceae Pre-built Database ----
      optparse::make_option(
        "--fabaceae-db", type = "character", default = NULL,
        metavar = "ID",
        help = "Use pre-built Fabaceae NR LTR library for species ID (skips CD-HIT). Use --list-db to see available IDs."
      ),
      optparse::make_option(
        "--list-db", action = "store_true", default = FALSE,
        help = "List available Fabaceae pre-built NR LTR databases and exit."
      ),
      optparse::make_option(
        "--db-info", type = "character", default = NULL,
        metavar = "ID",
        help = "Show detailed genome information for a Fabaceae species ID and exit."
      ),

      # ---- Pipeline Control ----
      optparse::make_option(
        "--skip-phase0", action = "store_true", default = FALSE,
        help = "Skip Phase 0 (de novo LTR annotation). Use when pre-computed results exist."
      ),
      optparse::make_option(
        "--skip-step", type = "character", default = NULL,
        metavar = "INT[,INT...]",
        help = "Skip specific step(s), e.g. '1,2' to skip step 1 and 2"
      ),
      optparse::make_option(
        "--only-step", type = "character", default = NULL,
        metavar = "INT[,INT...]",
        help = "Run only specific step(s), e.g. '3,4,5'"
      ),

      # ---- Misc ----
      optparse::make_option(
        c("-v", "--version"), action = "store_true", default = FALSE,
        help = "Print version and exit"
      ),
      optparse::make_option(
        "--gen-config", type = "character", default = NULL,
        metavar = "FILE",
        help = "Generate a default YAML config file and exit"
      ),
      optparse::make_option(
        "--config", type = "character", default = NULL,
        metavar = "FILE",
        help = "Load parameters from YAML config file (CLI args override)"
      ),
      optparse::make_option(
        "--quiet", action = "store_true", default = FALSE,
        help = "Suppress progress messages"
      )
    )
  )
}

#' Parse CLI arguments and resolve all parameters
#'
#' Handles: CLI args, YAML config file, environment variables,
#' auto-detection of external tools.
#'
#' @param args Character vector of command-line arguments
#' @return Named list of resolved parameters
#' @export
parse_cli_args <- function(args = commandArgs(trailingOnly = TRUE)) {

  # Strip Rscript -- separator if present (Rscript -e mode passes it through)
  if (length(args) > 0 && args[1] == "--") args <- args[-1]

  parser <- build_option_parser()

  # Handle --help / -h (before optparse, no required args needed)
  if (length(args) == 0 || any(c("--help", "-h") %in% args)) {
    print_banner()
    optparse::print_help(parser)
    quit(status = 0)
  }

  # Handle --version / -v (before optparse, no required args needed)
  if (any(c("--version", "-v") %in% args)) {
    cat("CenSoloLTR version ", as.character(utils::packageVersion("CenSoloLTR")), "\n", sep = "")
    quit(status = 0)
  }

  # Handle --list-db (before optparse, no required args needed)
  if (any("--list-db" %in% args)) {
    print_banner()
    list_fabaceae_db()
    quit(status = 0)
  }

  # Handle --db-info (before optparse, no required args needed)
  db_info_idx <- which(args == "--db-info")
  if (length(db_info_idx) > 0) {
    print_banner()
    if (length(args) > db_info_idx) {
      show_db_info(args[db_info_idx + 1])
    } else {
      stop("--db-info requires an ID argument. Use --list-db to see available IDs.")
    }
    quit(status = 0)
  }

  opt <- tryCatch(
    optparse::parse_args(parser, args = args, positional_arguments = FALSE),
    error = function(e) {
      cat("Error parsing arguments:", conditionMessage(e), "\n\n")
      optparse::print_help(parser)
      quit(status = 1)
    }
  )

  # --version (when passed alongside other args, post-optparse fallback)
  if (isTRUE(opt$version)) {
    cat("CenSoloLTR version ", as.character(utils::packageVersion("CenSoloLTR")), "\n", sep = "")
    quit(status = 0)
  }

  # --gen-config
  if (!is.null(opt[["gen-config"]])) {
    write_default_config(opt[["gen-config"]])
    cat("Default config written to:", opt[["gen-config"]], "\n")
    quit(status = 0)
  }

  # ---- Resolve parameters ----

  # 1. Load YAML config file if provided
  cfg <- list()
  if (!is.null(opt$config) && file.exists(opt$config)) {
    cfg <- yaml::read_yaml(opt$config)
  }

  # 2. Merge: CLI args override YAML config
  params <- list()

  # Helper: get value from CLI or YAML, with fallback
  get_param <- function(name, default) {
    cli_val <- opt[[name]]
    if (!is.null(cli_val) && !identical(cli_val, "auto") &&
        !(is.character(cli_val) && cli_val == "")) {
      return(cli_val)
    }
    yaml_val <- cfg[[name]]
    if (!is.null(yaml_val)) return(yaml_val)
    return(default)
  }

  # ---- Required parameters ----
  params$genome_file <- opt$genome
  params$cen_bed_file <- opt[["cen-bed"]]
  params$outdir      <- opt$outdir

  if (is.null(params$genome_file)) {
    stop("Error: --genome/-g is required. Use --help for usage.")
  }
  if (is.null(params$cen_bed_file)) {
    stop("Error: --cen-bed/-c is required. Use --help for usage.")
  }
  if (!file.exists(params$genome_file)) {
    stop("Error: genome file not found: ", params$genome_file)
  }
  if (!file.exists(params$cen_bed_file)) {
    stop("Error: CEN BED file not found: ", params$cen_bed_file)
  }

  # ---- Sample name ----
  if (!is.null(opt[["sample-name"]]) && opt[["sample-name"]] != "") {
    params$sample_name <- opt[["sample-name"]]
  } else {
    # Auto-detect from genome filename
    genome_basename <- basename(params$genome_file)
    params$sample_name <- sub("\\.(fa|fasta|fna|fas)$", "", genome_basename)
  }

  # ---- Threads ----
  params$threads <- as.integer(opt$threads)
  params$ltr_threads <- if (is.null(opt[["ltr-threads"]])) {
    params$threads
  } else {
    as.integer(opt[["ltr-threads"]])
  }

  # ---- LTR_retriever control ----
  params$ltr_retriever_timeout <- as.integer(
    get_param("ltr-retriever-timeout", 1800))

  # ---- Conda environment resolution ----
  conda_env <- opt[["conda-env"]]
  if (!is.null(conda_env)) {
    # Check if it's a name (e.g. "censololtr_v2") or a path (e.g. "/path/to/env")
    if (dir.exists(conda_env)) {
      conda_bin <- file.path(conda_env, "bin")
    } else {
      conda_bin <- file.path(dirname(dirname(Sys.which("conda"))),
                              "envs", conda_env, "bin")
      if (!dir.exists(conda_bin)) {
        # Try conda info --envs
        conda_info <- suppressWarnings(
          system(paste("conda info --envs 2>/dev/null | grep", shQuote(conda_env)),
                 intern = TRUE))
        if (length(conda_info) > 0) {
          conda_bin <- file.path(trimws(strsplit(conda_info[1], "\\s+")[[1]])[1], "bin")
        }
      }
    }
    if (dir.exists(conda_bin)) {
      params$conda_env <- conda_env
      params$conda_bin <- conda_bin
      options(censololtr_conda_bin = conda_bin)
    } else {
      warning("Conda environment '", conda_env, "' not found. Falling back to PATH.")
    }
  }

  # ---- External tool paths (with auto-detection) ----
  detect_tool <- function(name, candidates) {
    val <- get_param(name, NULL)
    if (!is.null(val) && val != "auto") return(val)
    # Search conda env bin first if configured
    if (!is.null(params$conda_bin) && dir.exists(params$conda_bin)) {
      for (c in candidates) {
        p <- file.path(params$conda_bin, c)
        if (file.exists(p)) return(p)
      }
    }
    for (c in candidates) {
      if (nzchar(Sys.which(c))) return(Sys.which(c))
    }
    return(NULL)
  }

  params$ltr_finder_path    <- detect_tool("ltr-finder",    c("ltr_finder"))
  params$gt_path            <- detect_tool("gt",            c("gt"))
  params$ltr_retriever_path <- detect_tool("ltr-retriever", c("LTR_retriever"))
  params$tesorter_path      <- detect_tool("tesorter",      c("TEsorter"))
  params$seqtk_path         <- detect_tool("seqtk",         c("seqtk"))
  params$cdhit_path         <- detect_tool("cd-hit",        c("cd-hit", "cd-hit-est"))
  params$blastn_path        <- detect_tool("blastn",        c("blastn"))
  params$makeblastdb_path   <- detect_tool("makeblastdb",   c("makeblastdb"))
  # Phase 0 parallel wrappers
  params$ltr_finder_pp_path <- detect_tool("ltr-finder-parallel",
                                            c("LTR_FINDER_parallel"))
  params$ltr_harvest_pp_path <- detect_tool("ltr-harvest-parallel",
                                             c("LTR_HARVEST_parallel"))

  # ---- CD-HIT parameters ----
  params$cdhit_identity <- as.numeric(get_param("cdhit-identity", 0.80))
  params$cdhit_coverage <- as.numeric(get_param("cdhit-coverage", 0.80))

  # ---- BLAST parameters ----
  params$blast_evalue         <- as.numeric(get_param("blast-evalue", 1e-5))
  params$blast_evalue_rescue  <- as.numeric(get_param("blast-evalue-rescue", 1.0))

  # ---- CEN/Peri-CEN ----
  params$peri_extension_bp <- as.integer(get_param("peri-extension-bp", 500000))

  # ---- Plot ----
  params$top_families <- as.integer(get_param("top-families", 15))

  # ---- Fabaceae pre-built database ----
  fabaceae_db_id <- opt[["fabaceae-db"]]
  if (!is.null(fabaceae_db_id) && fabaceae_db_id != "") {
    params$fabaceae_db <- fabaceae_db_id
    params$fabaceae_db_path <- get_fabaceae_db_path(fabaceae_db_id)
    message(sprintf("Using pre-built Fabaceae NR library (ID=%s): %s",
                    fabaceae_db_id, params$fabaceae_db_path))
  } else {
    params$fabaceae_db      <- NULL
    params$fabaceae_db_path <- NULL
  }

  # ---- Pipeline control ----
  params$skip_phase0 <- isTRUE(opt[["skip-phase0"]])
  params$skip_steps  <- parse_step_list(opt[["skip-step"]])
  params$only_steps  <- parse_step_list(opt[["only-step"]])

  # ---- Misc ----
  params$quiet <- isTRUE(opt$quiet)

  # ---- LTR_retriever share directory and helper scripts ----
  ltr_ret_dir <- opt[["ltr-retriever-dir"]]
  if (!is.null(ltr_ret_dir) && dir.exists(ltr_ret_dir)) {
    params$ltr_retriever_dir <- ltr_ret_dir
  } else {
    # Auto-detect from LTR_retriever install location
    ret_bin <- params$ltr_retriever_path
    if (!is.null(ret_bin)) {
      share_bin <- file.path(dirname(ret_bin), "..", "share", "LTR_retriever", "bin")
      if (dir.exists(share_bin)) {
        params$ltr_retriever_dir <- normalizePath(share_bin)
      }
    }
  }
  if (is.null(params$ltr_retriever_dir)) {
    params$ltr_retriever_dir <- NA_character_
  }

  # ---- Resolve SoloLTR script directory ----
  solo_script_dir <- opt[["solo-script-dir"]]
  if (!is.null(solo_script_dir) && dir.exists(solo_script_dir)) {
    params$solo_script_dir <- solo_script_dir
  } else {
    params$solo_script_dir <- NULL
  }

  # Locate find_LTR.pl and solo_finder.pl
  find_candidates <- function(script_name, retriever_dir, tools_dir, solo_dir) {
    paths <- c(
      if (!is.null(solo_dir)) file.path(solo_dir, script_name),
      file.path(retriever_dir, script_name),
      file.path(tools_dir, script_name),
      Sys.which(script_name)
    )
    for (p in paths) {
      if (nzchar(p) && !is.na(p) && file.exists(p)) return(normalizePath(p))
    }
    return(NA_character_)
  }

  # ---- Derived paths ----
  params$pkg_root  <- system.file(package = "CenSoloLTR")
  params$tools_dir <- file.path(params$pkg_root, "scripts")

  params$find_ltr_pl    <- find_candidates("find_LTR.pl",  params$ltr_retriever_dir,
                                            params$tools_dir, params$solo_script_dir)
  params$solo_finder_pl <- find_candidates("solo_finder.pl", params$ltr_retriever_dir,
                                            params$tools_dir, params$solo_script_dir)

  # ---- Validate Phase 0 tools if needed ----
  if (!params$skip_phase0) {
    missing_tools <- character(0)
    if (is.null(params$ltr_finder_pp_path))  missing_tools <- c(missing_tools, "LTR_FINDER_parallel")
    if (is.null(params$ltr_harvest_pp_path)) missing_tools <- c(missing_tools, "LTR_HARVEST_parallel")
    if (is.null(params$ltr_finder_path))      missing_tools <- c(missing_tools, "ltr_finder")
    if (is.null(params$gt_path))              missing_tools <- c(missing_tools, "gt (genometools)")
    if (is.null(params$ltr_retriever_path))   missing_tools <- c(missing_tools, "LTR_retriever")
    if (is.null(params$tesorter_path))        missing_tools <- c(missing_tools, "TEsorter")
    if (is.null(params$seqtk_path))           missing_tools <- c(missing_tools, "seqtk")
    # find_LTR.pl is optional (not present in LTR_retriever v2.9.x)
    if (is.na(params$solo_finder_pl))
      missing_tools <- c(missing_tools, "solo_finder.pl")
    if (length(missing_tools) > 0) {
      stop("Phase 0 tools not found: ", paste(missing_tools, collapse = ", "),
           "\n  Install them or use --skip-phase0 to skip de novo LTR annotation.\n",
           "  Or specify paths: --ltr-finder PATH --gt PATH ...")
    }
  }

  # Validate Phase 1/2 tools
  if (is.null(params$cdhit_path)) stop("cd-hit not found. Specify --cd-hit PATH.")
  if (is.null(params$blastn_path) || is.null(params$makeblastdb_path)) {
    stop("BLAST+ not found. Specify --blastn PATH and --makeblastdb PATH.")
  }

  class(params) <- c("CenSoloLTRConfig", class(params))
  return(params)
}

#' Parse comma-separated step list string to integer vector
#' @noRd
parse_step_list <- function(x) {
  if (is.null(x) || x == "") return(integer(0))
  tryCatch(
    as.integer(strsplit(x, ",")[[1]]),
    error = function(e) stop("Invalid step list: ", x)
  )
}

#' Determine if a step should run
#' @noRd
should_run_step <- function(step_num, params) {
  if (length(params$only_steps) > 0) {
    return(step_num %in% params$only_steps)
  }
  if (length(params$skip_steps) > 0) {
    return(!(step_num %in% params$skip_steps))
  }
  if (params$skip_phase0 && step_num <= 5) {
    return(FALSE)
  }
  return(TRUE)
}

#' Print parameter summary
#' @noRd
print_config_summary <- function(params) {
  if (params$quiet) return()
  fabaceae_info <- if (!is.null(params$fabaceae_db)) {
    sp <- FABACEAE_SPECIES[FABACEAE_SPECIES$ID == params$fabaceae_db, ]
    sprintf("  %s (%s)", params$fabaceae_db, sp$Species[1])
  } else "(none)"
  cat("
Configuration Summary
---------------------
Sample name:       ", params$sample_name, "
Genome file:       ", params$genome_file, "
CEN BED file:      ", params$cen_bed_file, "
Output directory:  ", params$outdir, "
Threads (general): ", params$threads, "
Threads (LTR):     ", params$ltr_threads, "
Conda env:         ", if (!is.null(params$conda_env)) params$conda_env else "(none)", "
Skip Phase 0:      ", params$skip_phase0, "
Fabaceae DB:       ", fabaceae_info, "
CD-HIT identity:   ", params$cdhit_identity, "
BLAST e-value:     ", params$blast_evalue, "
Peri-CEN ext bp:    ", params$peri_extension_bp, "
Top families:      ", params$top_families, "

", sep = "")
}
