# =========================================================================
# LTRtrace - Phase 4: Output Generation
# =========================================================================
# Step 7: Family composition statistics + publication-ready visualization
# =========================================================================

#' Custom color palette for superfamily plotting
#' @noRd
.plot_colors <- c(
  "#3B2368", "#286E74", "#474344", "#1F77B4", "#68A180",
  "#E6D66B", "#D98642", "#B53830", "#E2B9B3", "#782824",
  "#5D4037", "#455A64", "#A56FA6", "#E1F1D5", "#E4E0FF",
  "#808080", "#E0E0E0"
)

#' Standard ggplot2 theme for publication-ready plots
#' @noRd
.cen_theme <- ggplot2::theme_classic(base_size = 14) +
  ggplot2::theme(
    axis.text.y      = ggplot2::element_text(color = "black", face = "italic"),
    axis.text.x      = ggplot2::element_text(color = "black", size = 11),
    axis.line        = ggplot2::element_line(linewidth = 0.5, color = "black"),
    axis.ticks       = ggplot2::element_line(color = "black"),
    strip.background = ggplot2::element_rect(fill = "#cfd8dc", color = "black",
                                              linewidth = 0.8),
    strip.text       = ggplot2::element_text(face = "bold", size = 13,
                                              color = "#263238"),
    legend.position  = "right",
    legend.title     = ggplot2::element_blank(),
    legend.key.size  = ggplot2::unit(0.5, "cm"),
    legend.text      = ggplot2::element_text(size = 11),
    panel.spacing    = ggplot2::unit(1, "lines"),
    plot.title       = ggplot2::element_text(hjust = 0.5, face = "bold", size = 16)
  )

#' Save a plot in three formats: PDF, SVG, PNG
#' @noRd
save_plot_three <- function(p, dir_out, prefix, w = 14, h = 7.5) {
  ggplot2::ggsave(file.path(dir_out, paste0(prefix, ".pdf")),
                  plot = p, width = w, height = h)
  ggplot2::ggsave(file.path(dir_out, paste0(prefix, ".svg")),
                  plot = p, width = w, height = h)
  ggplot2::ggsave(file.path(dir_out, paste0(prefix, ".png")),
                  plot = p, width = w, height = h, dpi = 300)
}

#' Step 7: Family composition statistics and visualization
#'
#' Reads CEN/Peri-CEN annotation data, computes per-family statistics,
#' and generates 4 types of stacked bar plots:
#'   1. Count absolute (sqrt scale)
#'   2. Count percentage (100% stacked)
#'   3. Length absolute (sqrt scale)
#'   4. Length percentage (100% stacked)
#'
#' Each plot is saved in PDF, SVG, and PNG formats.
#' Two statistical summary tables are also generated.
#'
#' @param params LTRtraceConfig object
#' @export
step7_family_stats_plot <- function(params) {
  step_header(params, "7", 12, "Family Statistics + Publication Plots")
  if (!should_run_step(7, params)) {
    log_msg(params, "[SKIP] Step 7 disabled by user.")
    return(invisible(NULL))
  }

  sample <- params$sample_name

  # Check for pre-existing output
  out_png <- file.path(params$dirs$stats_out, "Plot_Count_Absolute_Sqrt.png")
  if (step_already_done(out_png)) {
    log_msg(params, "[RESUME] Plots already exist, skipping.")
    return(invisible(params$dirs$stats_out))
  }

  # ---- 7a. Read data ----
  tsv_path <- file.path(params$dirs$cen_anno,
                        paste0(sample, "_CEN_PeriCEN_SoloLTR.tsv"))

  if (!file.exists(tsv_path)) {
    warning("[Step 7] CEN/Peri-CEN annotation not found. Run Step 5 first.")
    return(invisible(NULL))
  }

  df <- readr::read_tsv(tsv_path, col_types = readr::cols(.default = "c")) %>%
    dplyr::mutate(
      Sample    = sample,
      start     = as.numeric(start),
      end       = as.numeric(end),
      Length_bp = end - start + 1
    ) %>%
    dplyr::mutate(Superfamily = ifelse(is.na(Superfamily), "Unclassified",
                                        Superfamily))

  if (nrow(df) == 0) {
    log_msg(params, "Step 7: No data to plot.")
    return(invisible(NULL))
  }

  # ---- 7b. Statistical tables ----
  log_msg(params, "Generating statistical summary tables ...")

  stats_summary <- df %>%
    dplyr::group_by(Sample, Region, Superfamily) %>%
    dplyr::summarise(
      Count           = dplyr::n(),
      Total_Length_bp = sum(Length_bp),
      Total_Length_Mb = Total_Length_bp / 1e6,
      .groups = "drop"
    ) %>%
    dplyr::arrange(Sample, Region, desc(Count))

  readr::write_tsv(stats_summary,
                   file.path(params$dirs$stats_out, "Detailed_Family_Stats.tsv"))

  total_stats_wide <- df %>%
    dplyr::group_by(Sample, Region) %>%
    dplyr::summarise(
      Total_Count     = dplyr::n(),
      Total_Length_Mb = round(sum(Length_bp) / 1e6, 3),
      .groups = "drop"
    ) %>%
    tidyr::pivot_wider(
      names_from  = Region,
      values_from = c(Total_Count, Total_Length_Mb),
      values_fill = 0
    )

  readr::write_tsv(total_stats_wide,
                   file.path(params$dirs$stats_out, "Species_Total_Summary_Wide.tsv"))

  # ---- 7c. Prepare plot data ----
  log_msg(params, "Preparing plot data ...")

  family_counts <- df %>%
    dplyr::filter(Superfamily != "Unclassified") %>%
    dplyr::count(Superfamily, sort = TRUE)

  top_families <- head(family_counts$Superfamily, params$top_families)

  df_plot <- df %>%
    dplyr::mutate(
      Superfamily = dplyr::case_when(
        Superfamily == "Unclassified" ~ "Unclassified",
        Superfamily %in% top_families ~ Superfamily,
        TRUE ~ "Others"
      )
    ) %>%
    dplyr::mutate(
      Superfamily = factor(Superfamily,
                            levels = c(top_families, "Others", "Unclassified"))
    )

  plot_summary <- df_plot %>%
    dplyr::group_by(Sample, Region, Superfamily, .drop = FALSE) %>%
    dplyr::summarise(
      Count           = dplyr::n(),
      Total_Length_Mb = sum(Length_bp) / 1e6,
      .groups = "drop"
    )

  # ---- 7d. Generate plots ----

  # Plot A: Count absolute (sqrt scale)
  log_msg(params, "  Plot A: Count (sqrt scale) ...")
  p_count_abs <- ggplot2::ggplot(plot_summary,
                                  ggplot2::aes(x = Count, y = Sample, fill = Superfamily)) +
    ggplot2::geom_bar(stat = "identity", color = "#212121",
                      linewidth = 0.2, width = 0.8) +
    ggplot2::facet_grid(~ Region, scales = "free_x") +
    ggplot2::scale_fill_manual(values = .plot_colors) +
    ggplot2::scale_x_continuous(
      trans  = "sqrt",
      breaks = scales::breaks_extended(n = 6),
      labels = scales::label_number(accuracy = 0.1)
    ) +
    .cen_theme +
    ggplot2::labs(x = "Number of Solo LTRs (Square Root Scale)", y = "",
                  title = "Solo LTR Accumulation (Count)")
  save_plot_three(p_count_abs, params$dirs$stats_out, "Plot_Count_Absolute_Sqrt")

  # Plot B: Count percentage
  log_msg(params, "  Plot B: Count (percentage) ...")
  p_count_pct <- ggplot2::ggplot(plot_summary,
                                  ggplot2::aes(x = Count, y = Sample, fill = Superfamily)) +
    ggplot2::geom_bar(stat = "identity", position = "fill",
                      color = "#212121", linewidth = 0.2, width = 0.8) +
    ggplot2::facet_grid(~ Region) +
    ggplot2::scale_fill_manual(values = .plot_colors) +
    ggplot2::scale_x_continuous(labels = scales::label_percent()) +
    .cen_theme +
    ggplot2::labs(x = "Percentage (%)", y = "",
                  title = "Solo LTR Composition by Count (%)")
  save_plot_three(p_count_pct, params$dirs$stats_out, "Plot_Count_Percentage")

  # Plot C: Length absolute (sqrt scale)
  log_msg(params, "  Plot C: Length (sqrt scale) ...")
  p_length_abs <- ggplot2::ggplot(plot_summary,
                                   ggplot2::aes(x = Total_Length_Mb, y = Sample,
                                                fill = Superfamily)) +
    ggplot2::geom_bar(stat = "identity", color = "#212121",
                      linewidth = 0.2, width = 0.8) +
    ggplot2::facet_grid(~ Region, scales = "free_x") +
    ggplot2::scale_fill_manual(values = .plot_colors) +
    ggplot2::scale_x_continuous(
      trans  = "sqrt",
      breaks = scales::breaks_extended(n = 6),
      labels = scales::label_number(accuracy = 0.1)
    ) +
    .cen_theme +
    ggplot2::labs(x = "Total Length (Mb, Square Root Scale)", y = "",
                  title = "Solo LTR Accumulation (Total Length in Mb)")
  save_plot_three(p_length_abs, params$dirs$stats_out, "Plot_Length_Absolute_Sqrt")

  # Plot D: Length percentage
  log_msg(params, "  Plot D: Length (percentage) ...")
  p_length_pct <- ggplot2::ggplot(plot_summary,
                                   ggplot2::aes(x = Total_Length_Mb, y = Sample,
                                                fill = Superfamily)) +
    ggplot2::geom_bar(stat = "identity", position = "fill",
                      color = "#212121", linewidth = 0.2, width = 0.8) +
    ggplot2::facet_grid(~ Region) +
    ggplot2::scale_fill_manual(values = .plot_colors) +
    ggplot2::scale_x_continuous(labels = scales::label_percent()) +
    .cen_theme +
    ggplot2::labs(x = "Percentage (%)", y = "",
                  title = "Solo LTR Composition by Total Length (%)")
  save_plot_three(p_length_pct, params$dirs$stats_out, "Plot_Length_Percentage")

  log_msg(params, sprintf("Step 7 complete: %d plot files + 2 tables → %s",
                          12, params$dirs$stats_out))
  invisible(params$dirs$stats_out)
}
