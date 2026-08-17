# ==============================================================================
# 02_fig1_cohort_landscape.R -- Figure 1: the DPUK metadata landscape
# ==============================================================================
#
# PURPOSE
#   Establishes the scale and the imbalance of the problem before any sleep
#   variable is retrieved: how many variables each cohort contributes, and how
#   weakly that relates to how many people each cohort recruited.
#
# INPUTS
#   data/raw/cohort_summary.csv   one row per cohort: n_vars, Initial_N, Estimated_N
#
# OUTPUTS
#   figures/fig1.png              (a) treemap of variable counts
#                                 (b) variables vs population size
#
# RATIONALE
#   Why a treemap for panel (a)? Variable counts span three orders of magnitude
#   (CaPS 7,670 and CFAS 25,779 against CamPaIGN's 32). On a bar chart the small
#   cohorts vanish. A treemap encodes count as area, which keeps every cohort
#   visible while making the dominance of the largest four immediately legible
#   -- those four are labelled with their share of the total.
#
#   Why log(n_vars) in panel (b)? Same range problem. The log axis is what makes
#   the panel's actual point readable: the number of variables a cohort
#   documents is close to independent of how many participants it recruited.
#   Metadata volume reflects study design and documentation practice, not study
#   size, which is why a sleep variable cannot be found by looking at the big
#   cohorts alone.
#
#   Why Estimated_N rather than Initial_N for point size? Initial_N is the
#   recruitment target reported by each study; Estimated_N is the count actually
#   present in the DPUK-held data. They differ substantially for cohorts that
#   deposited a subset (CFASII: 21,887 recruited, 7,524 deposited). Estimated_N
#   is the population a researcher could really analyse.
#
# ==============================================================================

source(here::here("R", "setup.R"))

message("02: Figure 1 -- cohort landscape")


# ---- Load and order ----------------------------------------------------------

cohorts <- read_csv(file.path(PATH_RAW, "cohort_summary.csv"), show_col_types = FALSE) %>%
  mutate(
    cohort      = recode_cohorts(cohort),   # trims the "CFAS " trailing space
    Estimated_N = as.numeric(Estimated_N)
  ) %>%
  arrange(desc(n_vars)) %>%
  # Fix factor order once, here, so both panels order cohorts identically.
  mutate(cohort = factor(cohort, levels = cohort))

total_vars <- sum(cohorts$n_vars)
total_pop  <- sum(cohorts$Estimated_N)

message("  ", nrow(cohorts), " cohorts, ",
        format(total_vars, big.mark = ","), " variables, ",
        format(total_pop, big.mark = ","), " participants")
message("  variables per cohort: median ", median(cohorts$n_vars),
        ", mean ", round(mean(cohorts$n_vars)),
        ", range ", min(cohorts$n_vars), "-", max(cohorts$n_vars))

# Label only the four largest cohorts with their percentage share; labelling all
# 20 makes the smallest tiles unreadable.
cohorts <- cohorts %>%
  mutate(label = if_else(
    row_number() <= 4,
    paste(cohort, paste0(round(n_vars / total_vars * 100), "%"), sep = "\n"),
    as.character(cohort)
  ))


# ---- Panel a: treemap of variable counts -------------------------------------

panel_a <- ggplot(cohorts, aes(area = n_vars, fill = cohort, label = label)) +
  geom_treemap() +
  geom_treemap_text(place = "centre", colour = "white", size = 30) +
  scale_fill_manual(values = COHORT_COLOURS) +
  guides(fill = "none") +
  labs(title = "a) ") +
  theme(plot.title = element_text(size = 14, face = "bold"))


# ---- Panel b: variables against population size ------------------------------

panel_b <- ggplot(cohorts,
                  aes(x = log(n_vars), y = reorder(cohort, n_vars),
                      size = Estimated_N, colour = cohort)) +
  geom_point() +
  scale_size_continuous(range = c(5, 15), name = "Population size") +
  scale_colour_manual(values = COHORT_COLOURS) +
  guides(colour = "none") +
  labs(title = "b) ", x = "log(N of Variables)", y = NULL) +
  theme_minimal() +
  theme(plot.title = element_text(size = 14, face = "bold"))


# ---- Assemble ----------------------------------------------------------------

fig1 <- panel_a + panel_b
save_figure("fig1.png", fig1, width = 12, height = 7)
