# ==============================================================================
# 03_fig2_similarity_duplication.R -- Figure 2: retrieval yield and quality
# ==============================================================================
#
# PURPOSE
#   Characterises what the TF-IDF retrieval step actually returned: how many
#   sleep variables per cohort, how much of that is the same question repeated,
#   and how confidently each cohort's wording matched UMLS.
#
#   Panel (c) is the paper's honesty check. It shows that a high cosine score is
#   not the same as a correct match, which is the evidence for the conclusion
#   that expert review cannot be removed from this pipeline.
#
# INPUTS
#   data/interim/sleep_dic_man.csv             754 reviewed TF-IDF matches
#   data/curated/sleep_vars_umls_qc_manual.xlsx  376 unique variables with the
#                                              expert YES/NO verdict on whether
#                                              the assigned UMLS term is right
#
# OUTPUTS
#   figures/fig2.png    (a) unique sleep variables per cohort
#                       (b) duplicated variables per cohort
#                       (c) distribution of cosine similarity per cohort
#   figures/fig2_umls_qc.png  supporting: expert verdict per cohort + overall
#
# RATIONALE
#   What counts as a duplicate? Two rows sharing a description string (`From`)
#   are the same question asked twice -- typically the same item repeated across
#   longitudinal waves under different variable IDs (CFAS's v64_h0..v64_h3), or
#   a questionnaire reused between sub-studies. They are counted separately from
#   unique variables because a researcher harmonising sleep data needs to know
#   the distinct constructs available, not the row count.
#
#   Why max(Similarity) when collapsing? A description can match several UMLS
#   terms. The best-scoring match is the one that was carried forward, so the
#   collapsed score has to be the maximum to describe what was actually used.
#
#   Why order cohorts by mean similarity in panel (c)? It makes visible that
#   cohorts differ systematically in how closely their wording tracks
#   standardised terminology -- cohorts using validated instrument wording score
#   high and tightly, cohorts with bespoke phrasing score low and spread out.
#   That variation is the metadata heterogeneity the paper is about.
#
# REFACTOR NOTE
#   In the original working directory this analysis existed twice, in
#   a1_population_analysis/metadata_analysis_i.Rmd and in
#   a2_cosine_score_analysis/cosine_sim_score_visualisations.Rmd, with ~230
#   duplicated lines. The a1 version produced the published Figure 2 and is the
#   one reproduced here; the a2 version's standalone panels and its scale break
#   (scale_x_break) were exploratory and are not reproduced.
#
# ==============================================================================

source(here::here("R", "setup.R"))

message("03: Figure 2 -- retrieval yield and quality")


# ---- Load --------------------------------------------------------------------

sleep_dic <- read_dpuk_csv(file.path(PATH_INTERIM, "sleep_dic_man.csv")) %>%
  mutate(cohort = recode_cohorts(cohort)) %>%
  select(fdd_var, From, To, cohort, Similarity)

message("  ", nrow(sleep_dic), " matched rows across ",
        n_distinct(sleep_dic$cohort), " cohorts")


# ---- Collapse to one row per distinct description per cohort -----------------

by_description <- sleep_dic %>%
  group_by(From, cohort) %>%
  summarise(Similarity = max(Similarity), .groups = "drop") %>%
  # Cohort ordering for panel (c): highest mean similarity first.
  group_by(cohort) %>%
  mutate(mean_similarity = mean(Similarity)) %>%
  ungroup() %>%
  arrange(desc(mean_similarity)) %>%
  mutate(cohort = factor(cohort, levels = unique(cohort)))

message("  ", nrow(by_description), " distinct sleep descriptions")


# ---- Unique and duplicated counts per cohort ---------------------------------

unique_counts <- by_description %>%
  count(cohort, name = "n_vars") %>%
  mutate(type_col = "Unique")

# A description appearing k times contributes k - 1 duplicates.
duplicate_counts <- sleep_dic %>%
  group_by(From, cohort) %>%
  summarise(n_repeats = n() - 1, .groups = "drop") %>%
  group_by(cohort) %>%
  summarise(n_vars = sum(n_repeats), .groups = "drop") %>%
  mutate(type_col = "Duplicated")

counts <- bind_rows(unique_counts, duplicate_counts)

# Panel (a)/(b) order cohorts by unique count, ascending, so the bars read as a
# ranking. Panel (c) keeps its own similarity ordering.
count_order <- unique_counts %>% arrange(n_vars) %>% pull(cohort) %>% as.character()
counts <- counts %>% mutate(cohort = factor(as.character(cohort), levels = count_order))

message("  unique: ", sum(unique_counts$n_vars),
        " | duplicated: ", sum(duplicate_counts$n_vars))


# ---- Panel a: unique variables per cohort ------------------------------------

panel_a <- ggplot(filter(counts, type_col == "Unique"),
                  aes(y = cohort, x = n_vars, fill = cohort)) +
  geom_col() +
  scale_fill_manual(values = COHORT_COLOURS) +
  labs(title = "a) ", x = "Number of Unique Sleep Variables", y = NULL) +
  theme_minimal() +
  theme(legend.position = "none",
        plot.title = element_text(size = 14, face = "bold"))


# ---- Panel b: duplicated variables per cohort --------------------------------
#
# Counts are printed beside each bar because several cohorts have none, and a
# zero-length bar is otherwise indistinguishable from a missing cohort.

panel_b <- ggplot(filter(counts, type_col == "Duplicated"),
                  aes(y = cohort, x = n_vars, fill = cohort)) +
  geom_col() +
  geom_text(aes(label = n_vars), hjust = -0.5, size = 4, colour = "black") +
  xlim(0, 300) +  # headroom so the largest bar's label is not clipped
  scale_fill_manual(values = COHORT_COLOURS) +
  labs(title = "b) ", x = "Number of Duplicate Variables", y = NULL) +
  theme_minimal() +
  theme(legend.position = "none",
        axis.text.y = element_text(size = 10),
        axis.text.x.bottom = element_text(size = 10),
        plot.title = element_text(size = 14, face = "bold"))


# ---- Panel c: similarity distribution per cohort -----------------------------
#
# Boxplot plus every underlying point: several cohorts contribute few enough
# variables that a boxplot alone would imply more data than exists.

panel_c <- ggplot(by_description, aes(x = cohort, y = Similarity, fill = cohort)) +
  geom_boxplot() +
  geom_point(shape = 1) +
  scale_fill_manual(values = COHORT_COLOURS) +
  guides(fill = "none") +
  labs(title = "c) ", y = "Cosine Similarity") +
  theme_minimal() +
  theme(axis.title.x = element_blank(),
        axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 1),
        plot.title = element_text(size = 14, face = "bold"))


# ---- Assemble ----------------------------------------------------------------

fig2 <- (panel_a + panel_b) / panel_c
save_figure("fig2.png", fig2, width = 10, height = 8)


# ==============================================================================
# Supporting figure: was the assigned UMLS term actually correct?
# ==============================================================================
#
# The expert reviewed each of the 376 unique variables and recorded whether the
# UMLS term TF-IDF assigned to it genuinely described the same concept. This is
# the number that justifies keeping a human in the pipeline, so it is computed
# here rather than quoted from the manuscript.

qc <- read_excel(file.path(PATH_CURATED, "sleep_vars_umls_qc_manual.xlsx")) %>%
  mutate(cohort = recode_cohorts(cohort)) %>%
  filter(bjd_UMLS_QC %in% c("YES", "NO")) %>%
  mutate(verdict = if_else(bjd_UMLS_QC == "YES", "UMLS match", "UMLS mis-match"))

qc_counts <- qc %>%
  count(cohort, verdict, name = "n_vars") %>%
  mutate(cohort = factor(cohort, levels = count_order))

qc_overall <- qc %>%
  count(verdict, name = "n_vars") %>%
  mutate(percentage = n_vars / sum(n_vars))

message("  UMLS QC: ",
        paste(sprintf("%s %d (%.0f%%)", qc_overall$verdict, qc_overall$n_vars,
                      qc_overall$percentage * 100), collapse = ", "))

qc_bars <- ggplot(qc_counts, aes(y = cohort, x = n_vars, fill = verdict)) +
  geom_col(position = "dodge") +
  scale_fill_manual(values = c("UMLS match" = ACCENT_PRIMARY,
                               "UMLS mis-match" = ACCENT_MUTED)) +
  labs(x = "Number of Sleep Variables", y = NULL, fill = "Manual Tag",
       title = "Unique sleep variables with a correct UMLS match") +
  theme_minimal()

qc_pie <- ggplot(qc_overall, aes(x = "", y = n_vars, fill = verdict)) +
  geom_col(width = 1) +
  geom_text(aes(label = percent(percentage, accuracy = 1)),
            position = position_stack(vjust = 0.5), size = 6) +
  coord_polar("y") +
  scale_fill_manual(values = c("UMLS match" = ACCENT_PRIMARY,
                               "UMLS mis-match" = ACCENT_MUTED)) +
  labs(x = NULL, y = NULL) +
  theme_minimal() +
  theme(axis.text.x = element_blank(), axis.ticks = element_blank(),
        panel.grid = element_blank(), panel.border = element_blank(),
        legend.position = "none")

# Inset the overall split into the empty upper-right of the bar chart.
fig2_qc <- qc_bars +
  annotation_custom(ggplotGrob(qc_pie), xmin = 25, xmax = 55, ymin = 1, ymax = 12)

save_figure("fig2_umls_qc.png", fig2_qc, width = 7, height = 5)
