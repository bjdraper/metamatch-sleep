# ==============================================================================
# run_all.R -- regenerate every figure in the paper
# ==============================================================================
#
# USAGE
#   Rscript analysis/run_all.R
#
# Runs the figure-producing scripts in order. Script 01 (TF-IDF retrieval) is
# NOT run: it needs a Python environment with polyfuzz, takes ~20 minutes, and
# its output is superseded by a manually reviewed file that is committed to the
# repository. Run it directly if you want to reproduce the retrieval step.
#
# Figure 3 panel (a) needs a 1.3 GB embedding file that is excluded from version
# control; script 04 detects its absence, warns, and writes panel (b) alone. See
# that script's header for the command that regenerates it.
#
# ==============================================================================

t_start <- Sys.time()

scripts <- c(
  "02_fig1_cohort_landscape.R",
  "03_fig2_similarity_duplication.R",
  "04_fig3_tsne.R",
  "05_fig4_clusters_categories.R"
)

for (script in scripts) {
  message("\n", strrep("=", 78))
  message("RUNNING ", script)
  message(strrep("=", 78))
  source(here::here("analysis", script), echo = FALSE)
}

message("\n", strrep("=", 78))
message("Done in ", round(difftime(Sys.time(), t_start, units = "mins"), 1), " minutes.")
message("Figures written to ", here::here("figures"))
message(strrep("=", 78))
