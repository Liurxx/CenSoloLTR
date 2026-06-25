# =========================================================================
# LTRtrace - Fabaceae Pre-built NR LTR Database
# =========================================================================
# Provides 18 pre-built non-redundant LTR libraries from Fabaceae species.
# When --fabaceae-db <ID> is specified, the pipeline uses the pre-built
# library instead of running CD-HIT (Step 2), while Phase 0 and Step 1
# still run normally to detect soloLTRs from the input genome.
# =========================================================================

# Built-in Fabaceae species metadata table
# Sourced from genome_information_with_titles.txt
FABACEAE_SPECIES <- data.frame(
  ID = c(
    "A17", "Cari", "Cchi", "Dreg",
    "Glygla", "Glyinf", "Jack", "ZH13", "WM82",
    "Gsoj", "Lpur", "Lsat", "Msat",
    "Mrub", "Pvul", "R108", "Tind", "Vrad"
  ),
  Species = c(
    "Medicago truncatula", "Cicer arietinum", "Cercis chinensis",
    "Delonix regia", "Glycyrrhiza glabra", "Glycyrrhiza inflata",
    "Glycine max (Jack)", "Glycine max (ZH13)", "Glycine max (WM82)",
    "Glycine soja", "Lablab purpureus", "Lathyrus sativus",
    "Medicago sativa", "Morella rubra", "Phaseolus vulgaris",
    "Medicago truncatula (R108)", "Tamarindus indica", "Vigna radiata"
  ),
  Assembly_Mb = c(
    494.47, 669.92, 352.84, 580.48,
    446.66, 442.53, 1011.76, 1007.24, 1011.79,
    1008.52, 460.76, 5967.28, 3136.11,
    292.60, 560.61, 415.27, 809.51, 500.14
  ),
  Scaffold_number = c(
    8, 69, 67, 232,
    8, 8, 20, 20, 20,
    20, 11, 7646, 32,
    47, 11, 8, 12, 13
  ),
  Longest_scaffold_Mb = c(
    69.98, 124.35, 52.53, 54.07,
    60.60, 63.86, 60.86, 60.63, 60.77,
    63.65, 68.46, 956.68, 110.28,
    44.01, 62.49, 57.81, 96.44, 75.15
  ),
  Scaffold_N50_Mb = c(
    63.90, 80.76, 47.43, 37.31,
    56.95, 58.15, 52.46, 51.88, 51.17,
    51.97, 41.30, 700.45, 98.55,
    36.50, 56.47, 54.39, 64.25, 45.67
  ),
  Contig_N50_Mb = c(
    63.90, 14.63, 29.66, 35.81,
    56.95, 58.15, 52.46, 48.76, 51.17,
    51.97, 41.30, 5.52, 15.12,
    36.50, 56.47, 54.39, 64.25, 45.67
  ),
  Gap_number = c(
    0, 800, 14, 12,
    0, 0, 0, 0, 0,
    0, 0, 5953, 8,
    0, 0, 0, 0, 0
  ),
  GC_content = c(
    34.33, 32.61, 36.95, 34.34,
    37.55, 37.4, 35.04, 35.02, 35.02,
    35.01, 30.06, 38.14, 34.19,
    37.29, 35.93, 32.93, 29.69, 33.3
  ),
  BUSCO = c(
    99.19, 99.6, 98.3, 99.4,
    99.2, 99.3, 99.6, 99.7, 99.8,
    99.7, 99.1, 99.1, 99.5,
    99.01, 99.26, 99.32, 98.8, 98.8
  ),
  Gapped_centromere = c(
    0, 730, 7, 5,
    0, 0, 0, 0, 0,
    0, 0, 1152, 0,
    0, 0, 0, 0, 0
  ),
  Article_Title = c(
    "Two complete telomere-to-telomere genome assemblies of Medicago reveal the landscape and evolution of its centromeres",
    "Pangenome analysis provides insights into legume evolution and breeding",
    "The nearly complete assembly of the Cercis chinensis genome and Fabaceae phylogenomic studies provide insights into new gene evolution",
    "The genomes of seven economic Caesalpinioideae trees provide insights into polyploidization history and secondary metabolite biosynthesis",
    "",  # This study
    "",  # This study
    "A complete reference genome for the soybean cv. Jack",
    "The T2T genome assembly of soybean cultivar ZH13 and its epigenetic landscapes",
    "A telomere-to-telomere gap-free assembly of soybean genome",
    "A telomere-to-telomere genome of wild soybean with resistance to soybean cyst nematode X12",
    "The complete telomere-to-telomere genome assembly of Lablab purpureus (L.) Sweet",
    "A chromosome-scale reference genome of grasspea (Lathyrus sativus)",
    "The haplotype-resolved and near-telomere-to-telomere genome assembly for the autotetraploid alfalfa",
    "T2T reference genome assembly and genome-wide association study reveal the genetic basis of Chinese bayberry fruit quality",
    "Gap-free genome assembly and metabolomics analysis of common bean provide insights into genomic characteristics and metabolic determinants of seed coat pigmentation",
    "Two complete telomere-to-telomere genome assemblies of Medicago reveal the landscape and evolution of its centromeres",
    "Tamarindus indica telomere-to-telomere genome reveals tartaric acid accumulation in fruit",
    "Telomere-to-telomere, gap-free genome of mung bean (Vigna radiata) provides insights into domestication under structural variation"
  ),
  Source = c(
    "https://doi.org/10.1016/j.molp.2025.07.016",
    "https://doi.org/10.1038/s41588-025-02280-5",
    "https://doi.org/10.1016/j.xplc.2022.100422",
    "https://doi.org/10.1016/j.xplc.2024.100944",
    "This study",
    "This study",
    "https://doi.org/10.1016/j.xplc.2023.100765",
    "https://doi.org/10.1016/j.molp.2023.10.003",
    "https://doi.org/10.1016/j.molp.2023.08.012",
    "https://doi.org/10.1038/s41597-025-05741-y",
    "https://doi.org/10.1038/s41597-025-06065-7",
    "https://doi.org/10.1038/s41597-024-03868-y",
    "https://doi.org/10.1016/j.xplc.2025.101691",
    "https://doi.org/10.1093/hr/uhae033",
    "https://doi.org/10.1016/j.jgg.2025.03.002",
    "https://doi.org/10.1016/j.molp.2025.07.016",
    "https://doi.org/10.1016/j.pld.2025.12.011",
    "https://doi.org/10.1093/hr/uhae337"
  ),
  stringsAsFactors = FALSE
)

#' List available Fabaceae pre-built NR LTR databases
#'
#' Prints a formatted table of all available Fabaceae species with their
#' genome assembly metadata and article references. Use the ID column values
#' with --fabaceae-db. Use --db-info <ID> to see full details for one species.
#'
#' @export
list_fabaceae_db <- function() {
  cat("\n")
  cat("Available Fabaceae Pre-built NR LTR Databases\n")
  cat("=============================================\n\n")
  cat(sprintf("  %-8s %-28s %8s %10s %6s  %s\n",
              "ID", "Species", "Size(Mb)", "N50(Mb)", "BUSCO", "Article"))
  cat(sprintf("  %-8s %-28s %8s %10s %6s  %s\n",
              "--------", "----------------------------",
              "--------", "----------", "------", "-------"))
  for (i in seq_len(nrow(FABACEAE_SPECIES))) {
    sp <- FABACEAE_SPECIES[i, ]
    title <- if (nchar(sp$Article_Title) > 0) sp$Article_Title else "This study"
    cat(sprintf("  %-8s %-28s %8.1f %10.2f %6.1f  %s\n",
                sp$ID, sp$Species, sp$Assembly_Mb,
                sp$Scaffold_N50_Mb, sp$BUSCO, title))
  }
  cat(sprintf("\n  %d species available.\n", nrow(FABACEAE_SPECIES)))
  cat("  Use --fabaceae-db <ID> to select a pre-built NR LTR library.\n")
  cat("  Use --db-info <ID> to see full details for a single species.\n\n")
  invisible(FABACEAE_SPECIES)
}

#' Show detailed information for a single Fabaceae species
#'
#' Prints a formatted detail page for the specified species, including
#' all genome assembly metrics, article title, and DOI/source.
#'
#' @param id Species ID (e.g. "A17", "Glyinf")
#' @export
show_db_info <- function(id) {
  if (!id %in% FABACEAE_SPECIES$ID) {
    stop(sprintf(
      "Unknown Fabaceae database ID: '%s'.\nUse --list-db to see available IDs.",
      id
    ), call. = FALSE)
  }
  sp <- FABACEAE_SPECIES[FABACEAE_SPECIES$ID == id, ]

  cat(sprintf("\n"))
  cat(sprintf("  Fabaceae Database Detail: %s (%s)\n", id, sp$Species))
  cat(sprintf("  ===============================================\n\n"))

  cat(sprintf("  %-28s %s\n", "Species:", sp$Species))
  cat(sprintf("  %-28s %s\n\n", "Database ID:", id))

  cat(sprintf("  %-28s %.2f Mb\n", "Assembly size:", sp$Assembly_Mb))
  cat(sprintf("  %-28s %d\n", "Scaffold number:", sp$Scaffold_number))
  cat(sprintf("  %-28s %.2f Mb\n", "Longest scaffold:", sp$Longest_scaffold_Mb))
  cat(sprintf("  %-28s %.2f Mb\n", "Scaffold N50:", sp$Scaffold_N50_Mb))
  cat(sprintf("  %-28s %.2f Mb\n", "Contig N50:", sp$Contig_N50_Mb))
  cat(sprintf("  %-28s %d\n", "Gap number:", sp$Gap_number))
  cat(sprintf("  %-28s %.1f%%\n", "GC content:", sp$GC_content))
  cat(sprintf("  %-28s %.1f%%\n", "BUSCO:", sp$BUSCO))
  cat(sprintf("  %-28s %d\n\n", "Gapped centromere:", sp$Gapped_centromere))

  cat(sprintf("  Article:\n"))
  title <- if (nchar(sp$Article_Title) > 0) sp$Article_Title else "(This study / unpublished)"
  source_str <- sp$Source
  cat(sprintf("    %s\n", title))
  if (grepl("^https?://", source_str)) {
    cat(sprintf("    DOI: %s\n", source_str))
  } else {
    cat(sprintf("    Source: %s\n", source_str))
  }
  cat("\n")
  invisible(sp)
}

#' Get path to a Fabaceae pre-built NR LTR library
#' @param id Species ID (e.g. "A17", "Glyinf")
#' @return Absolute path to the NR_LTR_library.fasta file
#' @noRd
get_fabaceae_db_path <- function(id) {
  if (!id %in% FABACEAE_SPECIES$ID) {
    stop(sprintf(
      "Unknown Fabaceae database ID: '%s'.\nUse --list-db to see available IDs.",
      id
    ), call. = FALSE)
  }
  fasta_path <- system.file("extdata", "fabaceae_db", id,
                            paste0(id, "_NR_LTR_library.fasta"),
                            package = "LTRtrace")
  if (!file.exists(fasta_path) || file.info(fasta_path)$size == 0) {
    stop(sprintf(
      "Fabaceae database file not found or empty: %s\nPackage may need reinstallation.",
      fasta_path
    ), call. = FALSE)
  }
  return(fasta_path)
}

#' Centralized NR LTR library path resolver
#'
#' When --fabaceae-db is specified, returns the pre-built library path.
#' Otherwise returns the standard pipeline output path (Step 2 CD-HIT result).
#'
#' @param params LTRtraceConfig object
#' @return Absolute path to the NR LTR library FASTA file
#' @noRd
get_nr_lib_path <- function(params) {
  if (!is.null(params$fabaceae_db) && params$fabaceae_db != "") {
    return(get_fabaceae_db_path(params$fabaceae_db))
  }
  file.path(params$dirs$nr_lib,
            paste0(params$sample_name, "_NR_LTR_library.fasta"))
}
