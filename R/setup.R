# ==============================================================================
# setup.R -- shared configuration for all METAMATCH-Sleep analysis scripts
# ==============================================================================
#
# PURPOSE
#   Single source of truth for packages, the cohort colour palette, the cohort
#   name lookup, and random seeds. In the original working scripts each of these
#   was pasted into every .Rmd, which let them drift apart (see NOTE on the
#   palette below). Every script in analysis/ starts by sourcing this file.
#
# USAGE
#   source(here::here("R", "setup.R"))
#
# ==============================================================================


# ---- Packages ----------------------------------------------------------------
#
# Only packages actually used downstream are loaded. The original scripts also
# loaded text, quanteda, udpipe, textrank, igraph, ggraph, proxy, mclust,
# kernlab and dendextend; none of them are called anywhere in the analysis, so
# they are dropped. They were left over from exploratory work that did not make
# it into the paper.
#
# plyr is deliberately NOT loaded. The original scripts loaded it *after* dplyr,
# which masks dplyr::summarise and dplyr::mutate -- that masking is the only
# reason the originals had to write dplyr:: in front of every verb. The one plyr
# function that was used (mapvalues) is replaced by a named-vector lookup in
# recode_cohorts() below.

suppressPackageStartupMessages({
  # Data wrangling
  library(dplyr)
  library(tidyr)
  library(readr)
  library(stringr)
  library(readxl)
  library(here)

  # Dimensionality reduction and clustering
  library(Rtsne)      # t-SNE (Figures 3 and 4)
  library(umap)       # UMAP  (Figure 4, feeds HDBSCAN)
  library(dbscan)     # HDBSCAN (Figure 4)

  # Visualisation
  library(ggplot2)
  library(scales)
  library(patchwork)    # multi-panel figure assembly
  library(treemapify)   # Figure 1a treemap
  library(ggrepel)      # Figure 3b point labels
  library(ggwordcloud)  # Figure 4c word cloud
  library(factoextra)   # Figure 4a cluster ellipses (fviz_cluster)
})


# ---- Reproducibility ---------------------------------------------------------
#
# t-SNE and UMAP are stochastic; the layout (though not the cluster structure)
# changes with the seed. These are the seeds that produced the published
# figures. SEED_TSNE_LOCAL differs from the others only because it was the value
# in use when the Figure 3b layout was finalised -- it carries no other meaning,
# but changing it would move the manually positioned point labels in that panel.

SEED_TSNE_GLOBAL <- 42   # Figure 3a, t-SNE over the full metadata corpus
SEED_TSNE_LOCAL  <- 40   # Figure 3b, t-SNE over sleep variables only
SEED_CLUSTER     <- 42   # Figure 4a, t-SNE / UMAP / HDBSCAN
SEED_WORDCLOUD   <- 42   # Figure 4c, word cloud text placement


# ---- Cohort colour palette ---------------------------------------------------
#
# University of Sheffield brand colours assigned one per cohort, so that a
# cohort keeps the same colour across every figure in the paper.
#
# NOTE ON A DISCREPANCY IN THE ORIGINAL SCRIPTS
#   This palette was pasted into five separate chunks and the copies had drifted:
#     - a1_population_analysis used the key "CFAS " (with a trailing space),
#       while a2 and a4 used "CFAS". The trailing-space version matched the raw
#       cohort_summary.csv value; the trimmed version matched everything else.
#     - a4_ML_analysis assigned AMPLE #3BD4AE and MRC #E7004C, whereas a1/a2
#       assigned #981F92 and #8B008B. AMPLE therefore shared a colour with
#       GS:SFHS in Figure 3, and MRC shared one with Airwave.
#   The a1/a2 values are used here as canonical because they give all 20 cohorts
#   distinct colours. Figures 3 and 4 collapse all but seven cohorts into
#   "other" anyway, so this only changes which two hues those panels use.

COHORT_COLOURS <- c(
  "Airwave"   = "#E7004C",  "AMPLE"    = "#981F92",  "BDR"      = "#4B0082",
  "BRACE"     = "#00BBCC",  "CamCAN"   = "#005A8F",  "CamPaIGN" = "#FFA07A",
  "CaPS"      = "#64CBE8",  "CFAS"     = "#981F92",  "CFASII"   = "#00CE7C",
  "ELSA"      = "#FF6371",  "EPIC"     = "#9400D3",  "EPINEF"   = "#8A2BE2",
  "GS:SFHS"   = "#3BD4AE",  "ICICLE"   = "#FFFF00",  "MRC"      = "#8B008B",
  "NICOLA"    = "#FF9664",  "NIMROD"   = "#800080",  "SMC"      = "#DAA8E2",
  "TRACK"     = "#0000FF",  "Whitehall" = "#A1DED2",
  "other"     = "#CFD5DA"   # grey, for cohorts collapsed together in Figs 3-4
)

# Two-colour accents used for binary contrasts (unique vs duplicated variables,
# UMLS match vs mis-match).
ACCENT_PRIMARY   <- "#E7004C"  # coral   -- the highlighted category
ACCENT_SECONDARY <- "#005A8F"  # teal    -- the contrast category
ACCENT_MUTED     <- "grey70"   # neutral -- "not matched" / background

# Full University of Sheffield sequence, used where a figure needs many
# unordered categories (Figure 4b/4c, 16 sleep categories).
UOS_SEQUENCE <- c(
  "#440099", "#9ADBE8", "#131E29", "#005A8F", "#00BBCC", "#64CBE8",
  "#00CE7C", "#3BD4AE", "#A1DED2", "#663DB3", "#981F92", "#DAA8E2",
  "#E7004C", "#FF6371", "#FF9664"
)


# ---- Cohort naming -----------------------------------------------------------
#
# DPUK stores cohort identifiers in lower case ("genscot", "cfasii"); the paper
# uses display names ("GS:SFHS", "CFASII"). The original scripts did this two
# different ways: plyr::mapvalues with two parallel 20-element vectors that had
# to stay index-aligned by hand, and (in tSNE_global.Rmd) a chain of gsub()
# calls whose result depended on execution order -- gsub("cfas", "CFAS") applied
# before the CFASII substitution would have produced "CFASii".
#
# One named lookup replaces both. Names are the stored identifiers, values are
# the display names.

COHORT_DISPLAY_NAMES <- c(
  airwave = "Airwave",   ample   = "AMPLE",    bdr      = "BDR",
  brace   = "BRACE",     camcan  = "CamCAN",   campaign = "CamPaIGN",
  caps    = "CaPS",      cfas    = "CFAS",     cfasii   = "CFASII",
  elsa    = "ELSA",      epic    = "EPIC",     epinef   = "EPINEF",
  genscot = "GS:SFHS",   icicle  = "ICICLE",   mrc      = "MRC",
  nicola  = "NICOLA",    nimrod  = "NIMROD",   smc      = "SMC",
  track   = "TRACK",     whitehall = "Whitehall"
)

#' Map stored cohort identifiers to paper display names
#'
#' Case-insensitive and whitespace-tolerant, so it copes with the "CFAS "
#' trailing space present in cohort_summary.csv. Values with no entry in the
#' lookup are returned unchanged rather than silently becoming NA, which is what
#' makes an unrecognised cohort visible instead of invisible.
#'
#' @param x character vector of cohort identifiers
#' @return character vector of display names
recode_cohorts <- function(x) {
  key     <- tolower(trimws(as.character(x)))
  mapped  <- unname(COHORT_DISPLAY_NAMES[key])
  ifelse(is.na(mapped), trimws(as.character(x)), mapped)
}


# ---- Project paths -----------------------------------------------------------
#
# here::here() resolves paths from the repo root regardless of the working
# directory, so scripts run identically from RStudio, Rscript, or knitr. The
# original scripts used absolute Windows paths (C:/Users/Lonza Project/... and
# S:/0373_Sleep_Dementia/...) which ran on exactly one machine.

PATH_REFERENCE <- here::here("data", "reference")
PATH_RAW       <- here::here("data", "raw")
PATH_INTERIM   <- here::here("data", "interim")
PATH_CURATED   <- here::here("data", "curated")
PATH_FIGURES   <- here::here("figures")

source(here::here("R", "helpers.R"))
