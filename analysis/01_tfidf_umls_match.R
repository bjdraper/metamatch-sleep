# ==============================================================================
# 01_tfidf_umls_match.R -- retrieve sleep variables from the DPUK metadata corpus
# ==============================================================================
#
# PURPOSE
#   Steps 1-2 of the METAMATCH pipeline. Scores every DPUK variable description
#   against every term in the SLEEPTALKING reference corpus, and keeps the
#   best-matching UMLS term for each. This is the retrieval step: it reduces
#   86,682 variable descriptions to a candidate set small enough to review by
#   hand.
#
# INPUTS
#   data/reference/sleeptalking_corpus.csv  2,032 UMLS sleep terms (CUI C0037313
#                                           and descendants, retrieved June 2022)
#   data/raw/dpuk_metadata_corpus.csv       86,682 variable descriptions, 20 cohorts
#
# OUTPUTS
#   data/interim/tfidf_matches_all.csv      every description with its best match
#   data/interim/sleep_dic_man.csv          the reviewed subset (754 rows)
#                                           -- committed; regenerating it
#                                           requires the manual step below
#
# RATIONALE
#   Why TF-IDF over n-grams rather than exact string matching? Cohorts describe
#   the same construct with different vocabulary and different levels of
#   abbreviation ("s. has difficulty in sleeping?" vs "Difficulty sleeping").
#   Exact matching finds almost nothing. Character n-gram TF-IDF tolerates
#   abbreviation, pluralisation and typos while staying cheap enough to run
#   86,682 x 2,032 comparisons.
#
#   Why cosine similarity? It compares the direction of two term-weight vectors
#   and ignores their magnitude, so a one-word description and a long
#   questionnaire item are scored on the vocabulary they share rather than on
#   length.
#
#   Why PolyFuzz via reticulate rather than a native R implementation? PolyFuzz
#   wraps scikit-learn's TF-IDF vectoriser with sparse k-nearest-neighbour
#   search, which returns only the top match per description instead of
#   materialising a 176-million-cell dense similarity matrix.
#
# MANUAL STEP
#   Scores ranged 1.000 to 0.164 (mean 0.522). A threshold of >= 0.5 was applied
#   and the surviving matches were read individually to confirm each really
#   described sleep. That review is what turns tfidf_matches_all.csv into
#   sleep_dic_man.csv, and it cannot be reproduced by running this script. The
#   reviewed file is committed so the rest of the pipeline runs without it.
#
#   The cut is intentionally permissive: subsequent manual UMLS quality control
#   (Figure 2c) found only 173/376 matches to be correct, i.e. the threshold was
#   set to favour recall and let the expert reject false positives. Raising it
#   would have discarded true sleep variables whose wording happened to share
#   little vocabulary with UMLS.
#
# ENVIRONMENT
#   Needs a Python environment with polyfuzz installed:
#       pip install "polyfuzz>=0.4.2"
#   Set RETICULATE_PYTHON to that interpreter, or edit the use_python() call.
#
# ==============================================================================

source(here::here("R", "setup.R"))
library(reticulate)

RUN_MATCHING <- FALSE  # set TRUE to re-run retrieval; see MANUAL STEP above

message("01: TF-IDF retrieval of sleep variables")


# ---- Load inputs -------------------------------------------------------------

umls_sleep <- read_csv(file.path(PATH_REFERENCE, "sleeptalking_corpus.csv"),
                       show_col_types = FALSE)
metadata   <- read_csv(file.path(PATH_RAW, "dpuk_metadata_corpus.csv"),
                       show_col_types = FALSE)

message("  SLEEPTALKING corpus: ", nrow(umls_sleep), " UMLS terms")
message("  DPUK metadata:       ", nrow(metadata), " variable descriptions across ",
        n_distinct(metadata$cohort), " cohorts")


# ---- TF-IDF matching ---------------------------------------------------------
#
# Matching is guarded because it takes ~20 minutes and its output is superseded
# by the manually reviewed file. Everything downstream reads sleep_dic_man.csv.

if (RUN_MATCHING) {

  polyfuzz <- reticulate::import("polyfuzz")

  # unique() both sides: identical descriptions recur across cohort waves and
  # scoring them repeatedly changes nothing.
  from_vec <- unique(metadata$fdd_desc)
  to_vec   <- unique(umls_sleep$name)

  message("  matching ", length(from_vec), " unique descriptions against ",
          length(to_vec), " unique UMLS terms ...")

  matches <- polyfuzz$PolyFuzz("TF-IDF")$match(from_vec, to_vec)$get_matches()

  matches <- matches %>%
    mutate(Similarity = as.numeric(Similarity)) %>%
    arrange(desc(Similarity))

  write_csv(matches, file.path(PATH_INTERIM, "tfidf_matches_all.csv"))

  # Attach cohort and variable name back onto each match. Joining on the
  # description text (not on position) is what makes this step safe to re-run.
  sleep_dic <- matches %>%
    left_join(metadata, by = c("From" = "fdd_desc")) %>%
    filter(Similarity >= 0.5)

  message("  ", nrow(sleep_dic), " matches at similarity >= 0.5, ",
          "covering ", n_distinct(sleep_dic$cohort), " cohorts")

  # MANUAL STEP: sleep_dic is the *candidate* set. Review it by hand and save
  # the confirmed rows to data/interim/sleep_dic_man.csv before continuing.
  write_csv(sleep_dic, file.path(PATH_INTERIM, "tfidf_candidates_for_review.csv"))

} else {
  message("  RUN_MATCHING is FALSE -- using the committed reviewed matches")
}


# ---- Reviewed output ---------------------------------------------------------

sleep_dic_man <- read_dpuk_csv(file.path(PATH_INTERIM, "sleep_dic_man.csv"))

message("  reviewed sleep dictionary: ", nrow(sleep_dic_man), " variables, ",
        n_distinct(sleep_dic_man$From), " distinct descriptions, ",
        n_distinct(sleep_dic_man$cohort), " cohorts")
message("  similarity range: ",
        sprintf("%.3f", min(sleep_dic_man$Similarity)), " to ",
        sprintf("%.3f", max(sleep_dic_man$Similarity)),
        " (mean ", sprintf("%.3f", mean(sleep_dic_man$Similarity)), ")")
