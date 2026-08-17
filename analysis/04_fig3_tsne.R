# ==============================================================================
# 04_fig3_tsne.R -- Figure 3: where sleep variables sit in semantic space
# ==============================================================================
#
# PURPOSE
#   Two t-SNE projections of BERT [CLS] embeddings.
#     (a) The full DPUK metadata corpus, with retrieved sleep variables
#         highlighted -- does the retrieval step pick out a semantically
#         coherent region, or is it scattered through unrelated metadata?
#     (b) The sleep variables alone, coloured by cohort -- once you look only at
#         sleep, what structures the space?
#
#   The answer to (b) is the paper's main negative result: definitions cluster
#   by cohort and by description length rather than by sleep construct. Cohort
#   house style dominates semantic content.
#
# INPUTS
#   data/interim/cls_embeddings_corpus86k.csv  NOT COMMITTED -- 1.3 GB.
#                                              Regenerate with:
#     python python/bert_cls_embeddings.py \
#         --input data/raw/dpuk_metadata_corpus.csv \
#         --text-col fdd_desc \
#         --output data/interim/cls_embeddings_corpus86k.csv
#   data/interim/cls_embeddings_sleep754.csv   committed (754 x 768)
#   data/raw/dpuk_metadata_corpus.csv          row-aligned with the 86k embeddings
#   data/interim/sleep_dic_man.csv             row-aligned with the 754 embeddings
#
# OUTPUTS
#   figures/fig3.png    both panels stacked
#   If the 86k embedding file is absent, panel (a) is skipped with a warning and
#   only panel (b) is written, so the script never fails on a fresh clone.
#
# RATIONALE
#   Why t-SNE rather than PCA? Two linear components explain very little
#   variance in a 768-dimensional BERT space. t-SNE preserves local neighbourhood
#   structure, which is the question being asked here -- what sits next to what.
#
#   Why perplexity 30? It is the value that balances local against global
#   structure for datasets of this size, and it is Rtsne's default. Lower values
#   fragment the 337-point sleep set into noise; higher values wash the cohort
#   separation out.
#
#   Read t-SNE distances with care: cluster *membership* is informative, but the
#   distance between two clusters and their absolute positions are not. That is
#   why Figure 4 re-does the clustering on UMAP output with an explicit
#   algorithm rather than reading groups off this projection by eye.
#
# ==============================================================================

source(here::here("R", "setup.R"))

message("04: Figure 3 -- t-SNE projections")

path_corpus_emb <- file.path(PATH_INTERIM, "cls_embeddings_corpus86k.csv")

# The reviewed sleep dictionary is needed by both panels: panel (a) uses it only
# to decide which corpus points to highlight, panel (b) projects it directly.
sleep_dic <- read_dpuk_csv(file.path(PATH_INTERIM, "sleep_dic_man.csv"))
sleep_vars <- unique(sleep_dic$fdd_var)


# ==============================================================================
# Panel a: full metadata corpus, sleep variables highlighted
# ==============================================================================

panel_a <- NULL

if (!file.exists(path_corpus_emb)) {

  warning("Panel 3a skipped: ", basename(path_corpus_emb), " not found.\n",
          "  It is 1.3 GB and excluded from version control. Regenerate with the ",
          "command in this script's header, then re-run.", call. = FALSE)

} else {

  corpus_meta <- read_csv(file.path(PATH_RAW, "dpuk_metadata_corpus.csv"),
                          show_col_types = FALSE)
  corpus_emb  <- read_cls_embeddings(path_corpus_emb)

  # Positional join -- see helpers.R::assert_aligned for why this is checked.
  assert_aligned(corpus_emb, corpus_meta, "full metadata corpus")
  corpus_meta$session_id <- as.character(seq_len(nrow(corpus_meta)))

  # Deduplicate before projecting: ~86k descriptions collapse to ~35k distinct
  # embeddings, and plotting the duplicates would only overplot identical points.
  corpus_unique <- distinct_embeddings(corpus_emb)

  set.seed(SEED_TSNE_GLOBAL)
  tsne_corpus <- Rtsne(embedding_matrix(corpus_unique),
                       dims = 2, perplexity = 30, max_iter = 1000, verbose = TRUE)

  # Explicit column names. The original script relied on Rtsne's `X` colliding
  # with the metadata CSV's unnamed index column during the join, then plotted
  # the resulting `X.x`. That worked, but only by accident of the collision.
  corpus_layout <- tibble(
    tsne_1     = tsne_corpus$Y[, 1],
    tsne_2     = tsne_corpus$Y[, 2],
    session_id = corpus_unique$session_id
  ) %>%
    left_join(corpus_meta, by = "session_id") %>%
    mutate(label_sleep = if_else(fdd_var %in% sleep_vars, "sleep", "other"))

  n_projected <- nrow(corpus_layout)
  message("  panel a: ", format(n_projected, big.mark = ","), " unique embeddings, ",
          sum(corpus_layout$label_sleep == "sleep"), " flagged as sleep")

  panel_a <- corpus_layout %>%
    # Sleep points drawn last so they are never hidden under the grey mass.
    arrange(label_sleep) %>%
    ggplot(aes(x = tsne_1, y = tsne_2,
               colour = label_sleep, alpha = label_sleep, shape = label_sleep)) +
    geom_point(size = 3) +
    scale_colour_manual(values = c(other = "#9ADBE8", sleep = ACCENT_PRIMARY)) +
    scale_alpha_manual(values = c(other = 0.1, sleep = 1)) +
    scale_shape_manual(values = c(other = 1, sleep = 19)) +
    guides(shape = "none", alpha = "none") +
    labs(title = "a) Global t-SNE",
         # Computed, not hard-coded, so caption and data cannot drift apart.
         subtitle = paste0("n = ", format(n_projected, big.mark = ",")),
         colour = "Extracted\nSleep Variables",
         x = "Dimension 1", y = "Dimension 2") +
    theme_minimal() +
    theme(plot.title = element_text(size = 14, face = "bold"))
}


# ==============================================================================
# Panel b: sleep variables only, coloured by cohort
# ==============================================================================

sleep_emb <- read_cls_embeddings(file.path(PATH_INTERIM, "cls_embeddings_sleep754.csv"))

assert_aligned(sleep_emb, sleep_dic, "sleep dictionary")
sleep_dic$session_id <- as.character(seq_len(nrow(sleep_dic)))

# 754 matched variables -> 337 semantically unique definitions.
sleep_unique <- distinct_embeddings(sleep_emb)

set.seed(SEED_TSNE_LOCAL)
tsne_sleep <- Rtsne(embedding_matrix(sleep_unique),
                    dims = 2, perplexity = 30, max_iter = 1000, verbose = TRUE)

# Only cohorts contributing enough sleep variables to form a visible group are
# coloured individually; the remaining 13 are pooled into "other" so the legend
# stays readable and the dominant cohorts stand out.
PROMINENT_COHORTS <- c("CaPS", "CFAS", "CamCAN", "ELSA", "Whitehall", "AMPLE", "MRC")

sleep_layout <- tibble(
  tsne_1     = tsne_sleep$Y[, 1],
  tsne_2     = tsne_sleep$Y[, 2],
  session_id = sleep_unique$session_id
) %>%
  left_join(sleep_dic, by = "session_id") %>%
  mutate(
    cohort = recode_cohorts(cohort),
    cohort = if_else(cohort %in% PROMINENT_COHORTS, cohort, "other"),
    # Wrap long questionnaire items so callout labels stay inside the panel.
    From   = str_wrap(From, width = 30)
  )

message("  panel b: ", nrow(sleep_layout), " unique sleep definitions")

# ---- Manual annotation -------------------------------------------------------
#
# Six variables are labelled to give the reader concrete examples of what the
# regions of the plot contain -- one from each prominent cohort plus a second
# ELSA item from the dense central cluster. These are chosen by hand, and the
# nudge offsets below are tuned to the layout produced by SEED_TSNE_LOCAL.
# Changing that seed will move the points and the labels will need repositioning.

LABELLED_VARS <- c(
  "SP6",                          # CamCAN, right-most point
  "c3restlessdisturbednights",    # CaPS
  "r4sleepr",                     # ELSA, central cluster
  "SD_Insomnia",                  # AMPLE
  "XWKSLEEP",                     # Whitehall
  "heslpe"                        # ELSA, second example
)

sleep_layout <- sleep_layout %>% mutate(to_label = fdd_var %in% LABELLED_VARS)

panel_b <- ggplot(sleep_layout, aes(x = tsne_1, y = tsne_2, colour = cohort)) +
  geom_point(size = 2) +
  scale_colour_manual(values = COHORT_COLOURS) +
  ylim(-20, 25) + xlim(-30, 30) +
  geom_text_repel(
    data = filter(sleep_layout, to_label),
    aes(label = From), size = 3, colour = "black",
    box.padding        = unit(0.5, "lines"),
    point.padding      = unit(0.25, "lines"),
    min.segment.length = 0,
    segment.curvature  = 0,
    segment.ncp        = 1,
    force              = 3,
    max.overlaps       = Inf,
    arrow              = arrow(length = unit(0.01, "npc")),
    # Hand-tuned offsets, in the order of LABELLED_VARS as they appear in the data.
    position = position_nudge_repel(x = c(0, 0, -15, 3, 0, 0),
                                    y = c(-5, -5, -5, 10, 7, -10))
  ) +
  labs(title = "b) Sleep t-SNE",
       subtitle = paste0("n = ", nrow(sleep_layout)),
       colour = "Prevalent Cohorts",
       x = "Dimension 1", y = "Dimension 2") +
  theme_minimal() +
  theme(plot.title = element_text(size = 14, face = "bold"))


# ---- Assemble ----------------------------------------------------------------

if (is.null(panel_a)) {
  save_figure("fig3_panel_b_only.png", panel_b, width = 9, height = 5)
  message("  wrote panel b only (see warning above)")
} else {
  save_figure("fig3.png", panel_a / panel_b, width = 9, height = 9)
}
