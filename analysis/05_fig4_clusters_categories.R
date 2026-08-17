# ==============================================================================
# 05_fig4_clusters_categories.R -- Figure 4: unsupervised clusters vs expert
#                                  categories
# ==============================================================================
#
# PURPOSE
#   The paper's central comparison. Panel (a) is what an unsupervised pipeline
#   discovers in the sleep definitions with no human input; panels (b) and (c)
#   are what the experts agreed the same definitions are about. Putting them
#   side by side is the argument: the clusters are coarse and partly artefactual
#   (one is defined by description *length*, another by proxy-respondent
#   phrasing), whereas the expert taxonomy separates constructs a sleep
#   researcher would actually want to harmonise on.
#
# INPUTS
#   data/interim/cls_embeddings_fulldef374.csv    374 x 768, committed
#   data/curated/dpuk_sleep_definitions.csv       374 full-sentence definitions
#                                                 ROW-ALIGNED with the above
#   data/curated/consensus_category_count.csv     agreed category counts
#
# OUTPUTS
#   figures/fig4.png                (a) HDBSCAN clusters
#                                   (b) expert category counts
#                                   (c) the same as a word cloud
#   data/interim/hdbscan_clusters.csv   cluster assignment per definition
#
# RATIONALE -- why this particular chain of methods
#
#   Why UMAP *before* HDBSCAN, when t-SNE was already run?
#     t-SNE is for looking at (Figure 3); UMAP is for clustering on. t-SNE
#     deliberately distorts global structure and its output is not a metric
#     space, so density-based clustering on t-SNE coordinates finds artefacts.
#     UMAP preserves more global structure and produces coordinates whose
#     densities are meaningful.
#
#   Why reduce to 5 components rather than clustering the raw 768 dimensions?
#     Density is not well defined in 768 dimensions -- distances concentrate and
#     every point looks equally far from every other. Five components retain
#     enough structure to separate topics while giving HDBSCAN a space where
#     density contrasts still exist.
#
#   Why the cosine metric for UMAP?
#     BERT embedding magnitude tracks token count, not meaning. Cosine distance
#     compares direction only, so a one-line and a three-line question about the
#     same construct are not separated by length alone. (They still partly are
#     -- see cluster 5 -- which is a limitation of untuned [CLS] embeddings, not
#     of the metric.)
#
#   Why n_neighbors = 10 and min_dist = 0.01?
#     With only 374 definitions, a small neighbourhood keeps genuinely local
#     topic structure; a large one would smooth the whole set into one blob. The
#     very small min_dist lets points pack tightly, which is what gives HDBSCAN
#     density contrast to work with.
#
#   Why HDBSCAN rather than k-means?
#     k-means needs k stated in advance, assumes roughly spherical equal-sized
#     clusters, and forces every point into one. None of that holds here: the
#     number of natural topic groups is exactly what is being asked, groups are
#     very unequal in size, and many definitions are genuinely ambiguous.
#     HDBSCAN finds the number of clusters itself and assigns ambiguous points
#     to a noise cluster instead of distorting a real cluster to absorb them.
#
#   Why minPts = 20?
#     The smallest group that should count as a cluster rather than as noise.
#     Below roughly this value the algorithm splits the large "sleep difficulty"
#     region into several near-identical fragments; well above it, distinct
#     topics such as Dreams get absorbed into their neighbours. It yields five
#     clusters plus noise.
#
# MANUAL STEP
#   Cluster labels in CLUSTER_LABELS below were assigned by reading the
#   definitions in each cluster; HDBSCAN returns only integers. The labels are
#   the authors' interpretation and are the weakest link in this panel -- see
#   docs/methods_v2_2026.html for how a version 2 should replace eyeballed
#   labels with measured cluster quality.
#
# ==============================================================================

source(here::here("R", "setup.R"))

message("05: Figure 4 -- clusters and expert categories")


# ---- Load and align ----------------------------------------------------------
#
# IMPORTANT: dpuk_sleep_definitions.csv must be the exact file, in the exact row
# order, that cls_embeddings_fulldef374.csv was generated from. The copy shipped
# here is that file. See REPRODUCIBILITY.md ("Positional joins") -- a second copy
# of this table with 19 rows in a different order existed in the original working
# directory, and joining against the wrong one silently mislabels points.

definitions <- read_csv(file.path(PATH_CURATED, "dpuk_sleep_definitions.csv"),
                        show_col_types = FALSE)
embeddings  <- read_cls_embeddings(file.path(PATH_INTERIM, "cls_embeddings_fulldef374.csv"))

assert_aligned(embeddings, definitions, "full-sentence sleep definitions")
definitions$session_id <- as.character(seq_len(nrow(definitions)))

unique_emb <- distinct_embeddings(embeddings)
emb_matrix <- embedding_matrix(unique_emb)

# Cohorts shown individually in the exploratory plot below; the rest are pooled.
# Same seven as Figure 3b, so the two figures are read against each other.
PROMINENT_COHORTS <- c("CaPS", "CFAS", "CamCAN", "ELSA", "Whitehall", "AMPLE", "MRC")


# ---- Exploratory t-SNE -------------------------------------------------------
#
# !! DO NOT DELETE THIS BLOCK, even though its output is not a published panel.
#
# Two reasons it is here.
#
# 1. It was the first look at these 316 definitions and it motivated the switch
#    to UMAP + HDBSCAN: the projection shows visible grouping but no boundaries
#    that could be read off reliably by eye, which is the argument for using an
#    explicit clustering algorithm rather than annotating the t-SNE.
#
# 2. Less comfortably, the published Figure 4a depends on it. R's `umap` package
#    (method "naive") draws from the global RNG stream, and this Rtsne call
#    consumes draws from that stream before UMAP runs. Removing it, or running
#    UMAP straight after set.seed(), produces a different UMAP layout and a
#    different number of HDBSCAN clusters. The published clustering therefore
#    depends on an incidental property of execution order, not only on the
#    documented parameters.
#
#    That is a genuine reproducibility weakness and it is recorded rather than
#    papered over -- see REPRODUCIBILITY.md ("RNG stream dependence"). It is kept
#    because reproducing the published figure is this script's job.

set.seed(SEED_CLUSTER)
tsne_explore <- Rtsne(emb_matrix, dims = 2, perplexity = 30,
                      max_iter = 1000, verbose = FALSE)

exploratory_tsne <- tibble(
  tsne_1     = tsne_explore$Y[, 1],
  tsne_2     = tsne_explore$Y[, 2],
  session_id = unique_emb$session_id
) %>%
  left_join(definitions, by = "session_id") %>%
  mutate(Cohort = if_else(Cohort %in% PROMINENT_COHORTS, Cohort, "other"))

exploratory_plot <- ggplot(exploratory_tsne,
                           aes(x = tsne_1, y = tsne_2, colour = Cohort)) +
  geom_point(size = 2) +
  scale_colour_manual(values = COHORT_COLOURS) +
  labs(title = "t-SNE of unique BERT [CLS] embeddings",
       subtitle = "Exploratory; not a published panel",
       x = "Dimension 1", y = "Dimension 2") +
  theme_minimal()

save_figure("fig4_exploratory_tsne.png", exploratory_plot, width = 7, height = 5)


# ---- UMAP --------------------------------------------------------------------
#
# No set.seed() here: UMAP deliberately inherits the RNG state left by the
# Rtsne call above. See the note in that block.

umap_result <- umap(emb_matrix,
                    n_neighbors  = 10,
                    min_dist     = 0.01,
                    n_components = 5,
                    metric       = "cosine")

umap_coords <- as.data.frame(umap_result$layout)
names(umap_coords) <- paste0("umap_", seq_len(ncol(umap_coords)))
umap_coords$session_id <- unique_emb$session_id

message("  UMAP: ", nrow(umap_coords), " definitions -> ",
        ncol(umap_coords) - 1, " components")


# ---- Attach expert categories ------------------------------------------------
#
# The agreed-category column holds a stringified Python list, because the
# consensus exercise was recorded in Python. A definition may legitimately carry
# more than one category, so expanding the list produces more rows than there
# are definitions: 316 unique definitions become 412 rows.

clustered <- umap_coords %>%
  left_join(definitions, by = "session_id") %>%
  unnest_category_list("Consensus Category")

message("  category expansion: ", nrow(umap_coords), " definitions -> ",
        nrow(clustered), " definition-category rows")


# ---- HDBSCAN -----------------------------------------------------------------
#
# !! IMPORTANT -- READ BEFORE CHANGING THE ORDER OF THESE STEPS.
#
# Clustering runs on the category-EXPANDED frame (412 rows), not on the 316
# unique definitions. This is what the published analysis did and it is
# reproduced faithfully here, because it is what Figure 4a shows.
#
# It has a consequence worth being explicit about. A definition carrying three
# agreed categories appears as three rows at *identical* UMAP coordinates, so it
# contributes three times to the local density that HDBSCAN measures. Multi-label
# definitions are therefore weighted more heavily than single-label ones, and the
# weighting comes from the expert annotation rather than from the embeddings --
# which means panel (a) is not purely unsupervised.
#
# The effect is not cosmetic. Clustering the 316 unique definitions instead, with
# everything else held constant, yields 2 clusters and no noise points rather
# than the 5 clusters plus noise reported in the paper. The published structure
# depends on the duplication.
#
# This is documented rather than silently corrected: the figure in the paper is
# the one this script must reproduce. See REPRODUCIBILITY.md ("Clustering on the
# expanded frame") and docs/methods_v2_2026.html for how a version 2 should
# handle multi-label data at this step.

umap_only <- clustered %>% select(starts_with("umap_"))

set.seed(SEED_CLUSTER)
hdb <- hdbscan(umap_only, minPts = 20)

clustered$cluster <- factor(hdb$cluster)

cluster_sizes <- table(hdb$cluster)
message("  HDBSCAN: ", sum(hdb$cluster > 0), " clustered, ",
        sum(hdb$cluster == 0), " assigned to noise")
message("  cluster sizes: ",
        paste(names(cluster_sizes), cluster_sizes, sep = "=", collapse = ", "))

# MANUAL STEP: labels assigned by reading each cluster's member definitions.
# Cluster 0 is HDBSCAN's noise/outlier group, not a topic -- it collects
# definitions too sparse or too ambiguous to place, which here turned out to be
# mostly proxy-respondent ("s. has difficulty...") and undefined items.
#
# These labels belong to the PUBLISHED clustering, whose cluster sizes are
# recorded in PUBLISHED_CLUSTER_SIZES below. They are only meaningful if this run
# reproduced that clustering, so they are applied conditionally -- see the guard.
CLUSTER_LABELS <- c(
  "0" = "Undefined and Proxy Reports",
  "1" = "Sleep Disorders and Sleep Difficulty",
  "2" = "Dreams",
  "3" = "Psychological Assessments",
  "4" = "Sleep Latency & Waking",
  "5" = "General Long-format Sleep assessment"
)

# Cluster sizes in data/curated/hdbscan_clusters.csv, the assignment used for the
# published Figure 4a.
PUBLISHED_CLUSTER_SIZES <- c("0" = 16, "1" = 98, "2" = 20,
                             "3" = 59, "4" = 54, "5" = 165)

observed_sizes <- table(as.character(hdb$cluster))
reproduced_published <- identical(
  as.integer(observed_sizes[names(PUBLISHED_CLUSTER_SIZES)]),
  as.integer(PUBLISHED_CLUSTER_SIZES)
)

if (reproduced_published) {
  clustered$cluster_label <- CLUSTER_LABELS[as.character(hdb$cluster)]
  message("  cluster sizes match the published assignment; expert labels applied")
} else {
  # Applying the published names to a differently-shaped clustering would put
  # confident, wrong words on the figure. Fall back to neutral labels and say so.
  clustered$cluster_label <- paste("Cluster", as.character(hdb$cluster))
  warning(
    "HDBSCAN did not reproduce the published cluster sizes.\n",
    "  published: ", paste(names(PUBLISHED_CLUSTER_SIZES),
                           PUBLISHED_CLUSTER_SIZES, sep = "=", collapse = ", "), "\n",
    "  this run:  ", paste(names(observed_sizes),
                           as.integer(observed_sizes), sep = "=", collapse = ", "), "\n",
    "  The expert cluster names are NOT applied, and panel (a) is drawn without\n",
    "  the in-place annotations, because both are tied to the published layout.\n",
    "  This is expected on package versions other than umap 0.2.10.0 / Rtsne 0.17 /\n",
    "  dbscan 1.2.0 -- see REPRODUCIBILITY.md ('RNG stream dependence'). The\n",
    "  published assignment is committed at data/curated/hdbscan_clusters.csv.",
    call. = FALSE
  )
}


# ---- Export cluster assignments ----------------------------------------------

clustered %>%
  select(Cohort, Full_Description, `Consensus Category`, `Test Categories`,
         cluster, cluster_label) %>%
  write_csv(file.path(PATH_INTERIM, "hdbscan_clusters.csv"))


# ---- Panel a: clusters -------------------------------------------------------
#
# fviz_cluster projects the 5 UMAP components onto their first two principal
# components for display and draws a concentration ellipse per cluster. Point
# labels are suppressed: 374 overlapping definition strings are unreadable.

panel_a <- fviz_cluster(
  list(data = umap_only, cluster = hdb$cluster),
  geom             = "point",
  ellipse          = TRUE,
  palette          = "jco",
  show.clust.cent  = FALSE,
  labelsize        = 0
) +
  labs(title = "a) ", subtitle = "Unsupervised Clustering of Sleep Variables") +
  theme_minimal() +
  theme(legend.position = "right",
        plot.title = element_text(size = 14, face = "bold"))

# Cluster names are placed as annotations at hand-chosen coordinates rather than
# via a legend, so each ellipse is named in place. These positions are tuned to
# the layout produced by SEED_CLUSTER and will need adjusting if it changes.
CLUSTER_LABEL_POSITIONS <- tribble(
  ~x,    ~y,    ~label,                                                    ~size,
  -0.5,  -1.0,  "Undefined and Proxy Reports",                              2.7,
   1.0,   1.5,  "Sleep Disorders and Sleep Difficulty",                     2.7,
   2.5,   1.0,  "Dreams",                                                   2.7,
   2.0,  -1.0,  "Psychological Assessments",                                2.7,
   0.5,  -2.0,  "Sleep Latency & Waking",                                   2.7,
  -2.0,  -0.5,  "General Long-format Sleep Questions\nrelating to Mental Health", 2.5
)

if (reproduced_published) {
  panel_a <- panel_a +
    geom_text(data = CLUSTER_LABEL_POSITIONS,
              aes(x = x, y = y, label = label, size = size),
              inherit.aes = FALSE, colour = "black", fontface = "bold",
              show.legend = FALSE) +
    scale_size_identity()
}


# ---- Panels b and c: expert consensus categories -----------------------------

category_counts <- read_csv(file.path(PATH_CURATED, "consensus_category_count.csv"),
                            show_col_types = FALSE)

message("  expert categories: ", nrow(category_counts),
        ", total assignments ", sum(category_counts$Count))

# One colour per category, ordered by count. The four largest categories share
# the deep-violet brand colour so they read as a block; the rest cycle through
# the University of Sheffield sequence.
category_colours <- c(rep("#440099", 4), UOS_SEQUENCE)
names(category_colours) <- category_counts %>% arrange(Count) %>% pull(Category)

panel_b <- ggplot(category_counts,
                  aes(x = Count, y = reorder(Category, Count), fill = Category)) +
  geom_col() +
  scale_fill_manual(values = category_colours) +
  labs(title = "b) ",
       subtitle = paste0("Guided Manual Categorisation, n = ", nrow(definitions)),
       x = "Number of Sleep Variables", y = "Category") +
  theme_minimal() +
  theme(legend.position = "none",
        plot.title = element_text(size = 14, face = "bold"))

# The word cloud restates panel (b) in a form that makes the relative dominance
# of the top categories immediate; area, not font height, encodes count.
set.seed(SEED_WORDCLOUD)
panel_c <- ggplot(category_counts,
                  aes(label = Category, size = Count, colour = Category)) +
  geom_text_wordcloud_area(rm_outside = TRUE, eccentricity = 1) +
  scale_size_area(max_size = 40) +
  scale_colour_manual(values = category_colours) +
  theme_minimal()


# ---- Assemble ----------------------------------------------------------------

fig4 <- panel_a / (panel_b + panel_c)
save_figure("fig4.png", fig4, width = 10, height = 10)
