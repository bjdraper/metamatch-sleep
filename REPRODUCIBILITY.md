# Reproducibility notes

Everything in this file was found while refactoring the original working
directory for release. It is written for colleagues who need to trust, extend or
re-run the analysis, and it errs towards saying too much rather than too little.

Nothing here changes a published result unless it says so explicitly. Where a
published number is affected, that is stated plainly.

---

## Summary

| # | Issue | Affects a published result? |
|---|---|---|
| 1 | Preprint names MiniLM-L6-v2; the code uses `bert-base-uncased` | No result — but the Methods text needs correcting |
| 2 | Embeddings are joined to metadata by row position, with no key | No — verified below |
| 3 | Figure 4 clustering runs on the category-expanded frame | Yes — this is what produces the five clusters |
| 4 | Figure 4's UMAP inherits RNG state from a preceding t-SNE call | Yes — exact cluster sizes are not reproducible across package versions |
| 5 | Cohort palette had drifted between scripts | Cosmetic only |
| 6 | Variable count is 86,681 here and 86,682 in the paper | Off-by-one in a quoted total |
| 7 | ELSA duplicate count is 4 here and 2 in published Figure 2b | One bar label in Figure 2b |

---

## 1. Model discrepancy: MiniLM-L6-v2 vs bert-base-uncased

**The preprint (line 169) states that embeddings were generated with
MiniLM-L6-v2 from HuggingFace. They were not. They were generated with
`bert-base-uncased`.**

Evidence:

- All three original embedding scripts (`main.py`, `bigML.py`,
  `fulldefinition_embeddings.py`) set `model_name = 'bert-base-uncased'` and load
  it with `BertTokenizer` / `BertModel`.
- Every shipped embedding file has **768** numeric columns. `bert-base-uncased`
  has a hidden size of 768; MiniLM-L6-v2 has 384. Check it yourself:

  ```bash
  head -1 data/interim/cls_embeddings_sleep754.csv | tr ',' '\n' | wc -l
  # 769  == 768 dimensions + the trailing `definition` column
  ```

The code in this repository keeps `bert-base-uncased`, because that is what
produced the published figures. **The manuscript's Methods section should be
corrected**, and the two models are not interchangeable: MiniLM is trained with
a sentence-similarity objective and is a genuinely better sentence encoder,
whereas an untuned BERT `[CLS]` vector is a known-weak sentence representation.
Switching to MiniLM would change the figures.

There is also a smaller version mismatch: the preprint reports `dbscan` 1.2.0,
which is worth pinning (see issue 4).

---

## 2. Positional joins

Embeddings carry **no key column**. Row *i* of an embedding CSV corresponds to
row *i* of the CSV it was generated from, and nothing anywhere records that fact.
The original scripts reconstructed the link with:

```r
data$session_id <- rownames(data)
```

Any re-sort, filter or regeneration between the embedding step and the plotting
step silently attaches the wrong metadata to every point — no error, no warning,
and nothing visibly wrong in the output.

**This did happen.** Two copies of the 374-row sleep definition table existed in
the original working directory:

- `python backup/FullDefinitions.csv` — the file the embeddings were generated from
- `a4_ML_analysis/dpuk_sleep_definitions.csv` — the file `HDBSCAN_analysis.Rmd` joined against

They contain the same 374 rows, but **19 of them are in a different order** (all
MRC variables, at positions 259–277). The published Figure 4 therefore joined 19
embeddings to the wrong rows.

**The published figure is nonetheless unaffected**, verified as follows: at all
19 mismatched positions, both the `Cohort` value and the `Consensus Category`
value are identical between the two files. Only the description text differs, and
description text is not used to colour, group or count anything in Figure 4.

```python
import pandas as pd
a = pd.read_csv("FullDefinitions.csv"); b = pd.read_csv("dpuk_sleep_definitions.csv")
m = a["Full_Description"].fillna("") != b["Full_Description"].fillna("")
m.sum()                                                    # 19
a.loc[m, "Cohort"].unique()                                # ['MRC']
(a.loc[m, "Consensus Category"].values
 == b.loc[m, "Consensus Category"].values).all()           # True
```

**What this repository does about it:**

- Only one copy of the table is shipped, at
  `data/curated/dpuk_sleep_definitions.csv`, and it is the copy the embeddings
  were generated from. The join is now correct by construction.
- Every positional join is preceded by `assert_aligned()` (`R/helpers.R`), which
  stops with an explanatory error if row counts disagree.

A row-count assertion catches a *changed* table but not a *reordered* one of the
same length. Writing a stable key (`master_id`) into the embedding files is the
proper fix and is the first recommendation in `docs/methods_v2_2026.html`.

---

## 3. Figure 4 clusters the category-expanded frame

`HDBSCAN_analysis.Rmd` joined the expert categories onto the UMAP coordinates and
expanded the multi-label category column **before** clustering. Because a
definition can hold several agreed categories, this turns 316 unique definitions
into 412 rows, with multi-label definitions appearing two or three times at
*identical* UMAP coordinates.

HDBSCAN measures local density, so a definition duplicated three times
contributes three times as much density as one appearing once. Panel 4a is
therefore **not purely unsupervised**: its cluster structure is partly driven by
how many categories the experts assigned.

This is not a rounding-error effect. Clustering the 316 unique definitions
instead, with every parameter unchanged, gives **2 clusters and no noise points**
rather than the five clusters plus noise in the paper.

`analysis/05_fig4_clusters_categories.R` reproduces the original order, with a
long comment at the clustering step explaining why. Reproducing the published
figure is that script's job. Whether the paper should be amended is a judgement
for the authors; the effect on the paper's *argument* is limited, because Figure
4a is used to show that unsupervised clusters are coarse and partly artefactual
— which remains true, and is arguably more true given this.

---

## 4. RNG stream dependence

R's `umap` package (method `"naive"`) draws from the global RNG stream. In
`HDBSCAN_analysis.Rmd` a `Rtsne()` call sits between `set.seed(42)` and the
`umap()` call, consuming draws from that stream. The published UMAP layout —
and hence the HDBSCAN clustering computed from it — depends on that call having
run first. Running `umap()` directly after `set.seed(42)` gives a different
layout and a different number of clusters.

`analysis/05_fig4_clusters_categories.R` keeps the `Rtsne()` call for this
reason, flagged with a `DO NOT DELETE` comment.

**Even so, the published cluster sizes are not exactly reproducible here.**

| | 0 (noise) | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|---|
| Published (`data/curated/hdbscan_clusters.csv`) | 16 | 98 | 20 | 59 | 54 | 165 |
| This repo, `dbscan` 1.2.0 | 20 | 98 | 51 | 78 | 165 | — |
| This repo, `dbscan` 1.2.5 | 19 | 99 | 51 | 78 | 165 | — |

The largest cluster (165) and the second (98) reproduce exactly; the remaining
133 points split into two groups here rather than three. Package version
accounts for part of the gap — `dbscan` 1.2.0 gets closer than 1.2.5 — and the
rest is attributable to RNG state that cannot be recovered from an `.Rmd` that
was executed interactively, chunk by chunk, over several sessions.

**How the code handles this.** `05_fig4_clusters_categories.R` compares its
cluster sizes against the published ones. If they match, the expert cluster
names and the in-place panel annotations are applied. If they do not, it raises a
warning, falls back to neutral `Cluster N` labels, and omits the annotations,
rather than printing confident and wrong topic names on the figure. The published
assignment stays available at `data/curated/hdbscan_clusters.csv`.

To reproduce as closely as possible, pin:

```
R 4.4.1   Rtsne 0.17   umap 0.2.10.0   dbscan 1.2.0
```

---

## 5. Cohort palette drift

The cohort colour vector was pasted into five separate chunks, and the copies
had diverged:

- `a1_population_analysis` keyed the palette on `"CFAS "` with a trailing space
  (matching the raw cohort summary CSV); `a2` and `a4` used `"CFAS"`.
- `a4_ML_analysis` assigned AMPLE `#3BD4AE` and MRC `#E7004C`, whereas `a1`/`a2`
  assigned `#981F92` and `#8B008B`. In Figures 3 and 4, AMPLE therefore shared a
  colour with GS:SFHS and MRC shared one with Airwave.

`R/setup.R` now holds one canonical palette, using the `a1`/`a2` values because
they give all 20 cohorts distinct colours. `recode_cohorts()` trims and
case-folds, so the trailing-space problem cannot recur. Figures 3 and 4 pool all
but seven cohorts into "other", so this changes only which two hues those panels
use — no data, counts or groupings are affected.

---

## 6. Variable count: 86,681 vs 86,682

The preprint quotes **86,682** variable descriptions throughout. Both routes
through the data give **86,681**:

```r
sum(readr::read_csv("data/raw/cohort_summary.csv")$n_vars)        # 86681
nrow(readr::read_csv("data/raw/dpuk_metadata_corpus.csv"))        # 86681
```

(`wc -l` reports 86,687 lines, but five records contain embedded newlines inside
quoted fields, so the parsed row count is the correct one.)

The two internal routes agree with each other, so the corpus is self-consistent
and the paper's figure is off by one. It affects no figure and no conclusion, but
the quoted total should be corrected to 86,681 in the next version. Scripts here
compute counts from the data rather than hard-coding them, so figure captions
cannot drift from the underlying files.

---

## 7. ELSA duplicate count in Figure 2b

Published Figure 2b labels ELSA with **2** duplicated variables. Re-running gives
**4**. Panels 2a and 2c reproduce exactly, as do the other five duplicate counts
(CaPS 60, CFAS 267, CFASII 40, ICICLE 6, MRC 3).

This is not a difference in the refactored code. Both the original counting logic
and the version in `03_fig2_similarity_duplication.R` give 4 when run on the
committed `sleep_dic_man.csv`, and the four repeated ELSA descriptions are
identifiable:

```
difficulty in sleeping in last 30 days                    x2
sleep: frequency wake up feeling tired & worn out         x2
sleep: rating sleep quality overall                       x2
whether felt their sleep was restless during past week    x2
```

The most likely explanation is that the published figure was produced from an
earlier vintage of the sleep dictionary — the two source notebooks are dated six
months apart (July 2024 and January 2025) — and that two of these ELSA pairs
entered the file in between. The committed file is the later one. **Worth
confirming before the next version**, since it changes a number in a published
figure, though not the ranking, the totals used elsewhere, or any conclusion.

### A deliberate deviation in the same panel

Published Figure 2b shows only the six cohorts that have duplicates. This version
shows all 17 with a `0` label, so that panels (a) and (b) share a y-axis and can
be read across. This was a judgement call made during the refactor, not an
attempt to reproduce the original; revert the `filter` in
`03_fig2_similarity_duplication.R` if the published form is wanted.

---

## Manual steps that cannot be re-run

Three points in the pipeline are human judgement and are not reproducible by
executing code. The outputs of all three are committed so that everything
downstream runs.

1. **UMLS candidate review** (`01_tfidf_umls_match.R`). Matches at cosine ≥ 0.5
   were read individually to confirm each described sleep. Produces
   `data/interim/sleep_dic_man.csv` (754 rows).
2. **UMLS match quality control**. Each of the 376 unique variables was marked
   YES/NO for whether its assigned UMLS term was correct. 173 YES, 203 NO.
   Produces `data/curated/sleep_vars_umls_qc_manual.xlsx`.
3. **Consensus categorisation**. The keyword categoriser's draft output was
   reviewed and agreed by the authors. Produces
   `data/curated/consensus_category_assignment.csv`.

Every such point is marked `MANUAL STEP` in the scripts.

---

## Environment

R 4.5.2 was used for the refactor; the paper reports R 4.4.1. Python 3.14 is
reported in the paper; `transformers` 4.44.0 is pinned in `requirements.txt`.

```r
# R packages
dplyr tidyr readr stringr readxl here
Rtsne umap dbscan
ggplot2 scales patchwork treemapify ggrepel ggwordcloud factoextra
reticulate   # only for analysis/01, which needs Python polyfuzz
```

The DPUK metadata CSVs are **Windows-1252**, not UTF-8 — they contain smart
quotes in items such as `medicine (prescribed or "over the counter")`. They are
committed in their original encoding so that what is here is byte-for-byte what
the published analysis ran on. `read_dpuk_csv()` and the `--encoding` default in
`bert_cls_embeddings.py` handle this.
