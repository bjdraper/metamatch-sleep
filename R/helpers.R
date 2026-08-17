# ==============================================================================
# helpers.R -- small utilities shared across the analysis scripts
# ==============================================================================
#
# Sourced by R/setup.R. Nothing here changes the methodology; these are the
# functions that were previously defined inline (and in two cases defined twice,
# in different files) in the original .Rmd notebooks.
#
# ==============================================================================


#' Save a figure with a white background
#'
#' ggplot2's default device background is transparent, which renders as black in
#' some PDF viewers and in dark-mode image previews. The original scripts solved
#' this by shadowing ggplot2::ggsave with a wrapper in one notebook and passing
#' bg = "white" by hand in another. Shadowing a package function is easy to miss
#' when reading the code, so this is a plainly named function instead.
#'
#' @param filename file name, resolved relative to figures/ unless absolute
#' @param plot ggplot or patchwork object
#' @param width,height dimensions in inches
#' @param dpi resolution; 300 for publication rasters
save_figure <- function(filename, plot, width = 7, height = 5, dpi = 300) {
  path <- if (grepl("^(/|[A-Za-z]:)", filename)) filename else file.path(PATH_FIGURES, filename)
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  ggplot2::ggsave(path, plot, width = width, height = height, dpi = dpi, bg = "white")
  message("  wrote ", path)
  invisible(path)
}


#' Darken a hex colour by scaling its RGB channels
#'
#' Used to keep axis-label text legible when it is coloured to match the bars it
#' labels: several brand colours (notably ICICLE's #FFFF00) are too light to
#' read as text on white.
#'
#' @param colour hex colour string
#' @param factor multiplier in [0, 1]; lower is darker
darken_colour <- function(colour, factor = 0.8) {
  rgb_col  <- grDevices::col2rgb(colour)
  darkened <- pmax(pmin(rgb_col * factor, 255), 0)
  grDevices::rgb(darkened[1], darkened[2], darkened[3], maxColorValue = 255)
}


#' Assert that an embedding matrix is row-aligned with its source table
#'
#' THIS IS THE MOST IMPORTANT CHECK IN THE REPOSITORY.
#'
#' The embedding CSVs produced by python/bert_cls_embeddings.py carry no key
#' column -- row i of the embedding file corresponds to row i of the input CSV
#' and nothing else records that fact. The original scripts reconstructed the
#' link with `session_id <- rownames(df)`, i.e. a positional join. If the source
#' table is ever re-sorted, filtered, or regenerated between the embedding step
#' and the plotting step, every downstream figure silently attaches the wrong
#' metadata to each point, with no error and no visual sign that anything broke.
#'
#' That is not hypothetical: two copies of the sleep definition table did drift
#' apart in exactly this way during the original analysis. See REPRODUCIBILITY.md
#' ("Positional joins") for what happened and why the published Figure 4 is
#' nonetheless unaffected.
#'
#' Call this immediately before any positional join.
#'
#' @param embeddings data frame of embeddings
#' @param source_table data frame the embeddings were computed from
#' @param label description used in the error message
assert_aligned <- function(embeddings, source_table, label = "embeddings") {
  if (nrow(embeddings) != nrow(source_table)) {
    stop(
      "Row-alignment check failed for ", label, ".\n",
      "  embeddings:   ", nrow(embeddings), " rows\n",
      "  source table: ", nrow(source_table), " rows\n",
      "These are joined by position, so they must match exactly. ",
      "Regenerate the embeddings from the current source table before continuing.",
      call. = FALSE
    )
  }
  message("  alignment OK: ", label, " (", nrow(embeddings), " rows)")
  invisible(TRUE)
}


#' Read a DPUK metadata CSV with the correct source encoding
#'
#' The metadata exports came out of Windows tooling and are Windows-1252, not
#' UTF-8: they contain smart quotes (0x93/0x94) and apostrophes (0x92) in items
#' such as 'medicine (prescribed or "over the counter")'. readr assumes UTF-8 and
#' errors on those bytes.
#'
#' The files are deliberately left in their original encoding rather than being
#' re-saved as UTF-8, so that what is committed here is byte-for-byte what the
#' published analysis ran on. python/bert_cls_embeddings.py defaults to the same
#' encoding for the same reason.
#'
#' @param path path to the CSV
#' @param ... passed to readr::read_csv
read_dpuk_csv <- function(path, ...) {
  readr::read_csv(
    path,
    locale = readr::locale(encoding = "windows-1252"),
    show_col_types = FALSE,
    progress = FALSE,
    ...
  )
}


#' Load a CLS embedding CSV and attach positional row identifiers
#'
#' The embedding files written by python/bert_cls_embeddings.py have one column
#' per BERT dimension (768 for bert-base-uncased) plus a trailing `definition`
#' column holding the cleaned input text. That trailing column is dropped here:
#' it is useful for eyeballing the file but must not enter the distance
#' calculation.
#'
#' @param path path to the embedding CSV
#' @return data frame with a leading `session_id` column and 768 numeric columns
read_cls_embeddings <- function(path) {
  emb <- readr::read_csv(path, show_col_types = FALSE, progress = FALSE)

  # Drop the trailing text column written for human inspection.
  if ("definition" %in% names(emb)) emb <- dplyr::select(emb, -"definition")

  # Positional identifier. Character, not integer, so that it joins cleanly
  # against the rownames-derived ids used on the metadata side.
  emb$session_id <- as.character(seq_len(nrow(emb)))
  dplyr::select(emb, "session_id", dplyr::everything())
}


#' Reduce embeddings to semantically unique rows
#'
#' Cleaning (lower-casing, punctuation and bracket removal) collapses many
#' variable descriptions onto identical strings, which produce bit-identical
#' embeddings. Two variables with the same cleaned text carry no additional
#' semantic information, and leaving both in would let a repeated phrase
#' dominate a cluster purely by how often a cohort asked it.
#'
#' Deduplicating on the embedding vector rather than the raw string is
#' deliberate: it is the representation the clustering actually sees. For the
#' sleep dictionary this reduces 754 matched variables to 337 unique definitions
#' -- the figure quoted throughout the paper.
#'
#' @param embeddings data frame from read_cls_embeddings()
#' @return the same data frame with duplicate embedding vectors removed
distinct_embeddings <- function(embeddings) {
  vectors <- as.matrix(embeddings[, setdiff(names(embeddings), "session_id")])
  kept    <- embeddings[!duplicated(vectors), ]
  message("  ", nrow(embeddings), " embeddings -> ", nrow(kept), " semantically unique")
  kept
}


#' Extract the numeric matrix from an embedding data frame
#'
#' @param embeddings data frame from read_cls_embeddings()
embedding_matrix <- function(embeddings) {
  as.matrix(embeddings[, setdiff(names(embeddings), "session_id")])
}


#' Expand a bracketed Python-style list column into one row per category
#'
#' The consensus categories were assigned in Python and written to CSV as the
#' repr() of a list, e.g. "['Sleep Difficulty', 'Sleep Latency and Waking']".
#' A variable can legitimately belong to more than one category, so counts in
#' Figure 4b sum to more than the 374 definitions.
#'
#' @param df data frame
#' @param column name of the column holding the stringified list
unnest_category_list <- function(df, column) {
  df %>%
    dplyr::mutate(
      !!column := stringr::str_remove_all(.data[[column]], "[\\[\\]']"),
      !!column := strsplit(.data[[column]], ",\\s*")
    ) %>%
    tidyr::unnest(dplyr::all_of(column)) %>%
    dplyr::mutate(!!column := trimws(.data[[column]]))
}
