# METAMATCH-Sleep

Code and data for **"Leveraging NLP to Identify Domain-Specific Variables in
Large-Scale Cohort Metadata: A Sleep Use Case"**
([medRxiv 2026.01.18.26344317](https://doi.org/10.64898/2026.01.18.26344317)).

METAMATCH is a semi-automatic method for finding all variables about a given
health topic inside the metadata of many cohort studies at once. Sleep is the
worked example here, but nothing in the method is sleep-specific — swap the
reference dictionary and it applies to any domain.

**The result in one line:** 86,681 variable descriptions across 20 DPUK cohorts
were reduced to 337 semantically unique sleep variables, of which expert review
confirmed 173/376 UMLS assignments as correct — which is why the paper concludes
that NLP narrows the search enormously but does not remove the expert.

---

## The pipeline

```
  SLEEPTALKING corpus                    DPUK metadata corpus
  2,032 UMLS sleep terms                 86,681 variable descriptions
  (CUI C0037313, June 2022)              20 cohorts
           │                                      │
           └──────────────┬───────────────────────┘
                          ▼
              1. TF-IDF + cosine similarity              analysis/01
                 best UMLS match per description
                          │
                          ▼
              ┌─ MANUAL: review matches at >= 0.5 ─┐
                          │
                          ▼
                 754 matched sleep variables
                          │
                          ▼
              2. BERT [CLS] embeddings                   python/
                 bert-base-uncased, 768-d
                          │
                          ▼
                 337 semantically unique definitions
                          │
              ┌───────────┴───────────┐
              ▼                       ▼
   3. t-SNE projection      4. UMAP -> HDBSCAN clustering
      Figure 3                  Figure 4a
                                      │
                                      ▼
                        ┌─ MANUAL: consensus categorisation ─┐
                                      │
                                      ▼
                             16 agreed categories
                                  Figure 4b/c
```

Steps marked MANUAL are human judgement and cannot be re-run by executing code.
Their outputs are committed so everything downstream works. They are also the
point of the paper: see [REPRODUCIBILITY.md](REPRODUCIBILITY.md).

---

## Which script makes which figure

| Figure | Script | What it shows |
|---|---|---|
| 1 | `analysis/02_fig1_cohort_landscape.R` | Variable counts per cohort (treemap) and their weak relationship to population size |
| 2 | `analysis/03_fig2_similarity_duplication.R` | Unique vs duplicated sleep variables per cohort; cosine similarity distributions |
| 3 | `analysis/04_fig3_tsne.R` | t-SNE of the whole corpus with sleep highlighted; t-SNE of sleep variables by cohort |
| 4 | `analysis/05_fig4_clusters_categories.R` | HDBSCAN clusters vs the expert consensus categories |
| — | `analysis/01_tfidf_umls_match.R` | The retrieval step. Produces no figure; needs Python `polyfuzz` |

---

## Running it

```bash
git clone git@github.com:draperb7/metamatch-sleep.git
cd metamatch-sleep

# R dependencies
Rscript -e 'install.packages(c(
  "dplyr","tidyr","readr","stringr","readxl","here",
  "Rtsne","umap","dbscan",
  "ggplot2","scales","patchwork","treemapify","ggrepel","ggwordcloud","factoextra"
))'

# Regenerate every figure
Rscript analysis/run_all.R
```

Takes about a minute. Figures land in `figures/`; the versions published in the
paper are kept alongside in `figures/published/` for comparison.

Two things will not run out of the box, both by design:

- **Figure 3 panel (a)** needs a 1.3 GB embedding file that is too large for
  GitHub. Script 04 detects its absence, warns, and writes panel (b) alone.
  Regenerate it with the command in that script's header (a few hours on CPU).
- **`analysis/01`** needs a Python environment with `polyfuzz`, and its output is
  superseded by a manually reviewed file that is committed. It is guarded behind
  `RUN_MATCHING <- FALSE`.

### Python steps

```bash
pip install -r requirements.txt

# Embeddings (see the script's --help for all three variants)
python python/bert_cls_embeddings.py \
    --input data/interim/sleep_dic_man.csv \
    --text-col From \
    --output data/interim/cls_embeddings_sleep754.csv

# Draft categories, the input to the expert consensus exercise
python python/keyword_categoriser.py
```

### Methods walkthrough

`methods_walkthrough.Rmd` knits the whole analysis into a single annotated HTML
page:

```bash
Rscript -e 'rmarkdown::render("methods_walkthrough.Rmd")'
```

Needs [pandoc](https://pandoc.org/installing.html) (bundled with RStudio;
`brew install pandoc` otherwise).

---

## How this release was verified

| Check | Result |
|---|---|
| `Rscript analysis/run_all.R` from clean state | Runs to completion, ~6 seconds |
| Figure 1 panels vs published | Match |
| Figure 2 panels (a) and (c) vs published | Match |
| Figure 2 panel (b) | One difference — ELSA 4 vs published 2, explained in REPRODUCIBILITY.md |
| Figure 3, unique embeddings after dedup | **35,529** — matches the published caption exactly |
| Figure 3b, unique sleep definitions | **337** — matches the paper |
| Figure 4, cluster row count after expansion | **412** — matches the published assignment |
| Figure 4, cluster sizes | Largest two match (165, 98); remainder splits differently — see REPRODUCIBILITY.md |
| Consolidated `clean_text()` vs original cleaned text | **0 differences across all 1,128 rows** |
| Every positional join | Guarded by `assert_aligned()`, all pass |
| `methods_walkthrough.Rmd` | All chunks execute |

The embedding step itself was not re-executed (it needs `torch`, and several
hours of CPU). Its text-cleaning stage — the only part that changed in the
refactor — was verified exactly against the cleaned text stored in the shipped
embedding files; the model forward pass after it is deterministic.

---

## Repository layout

```
R/
  setup.R          packages, cohort palette, name lookup, RNG seeds
  helpers.R        figure saving, embedding IO, alignment assertions
analysis/
  01..05_*.R       the pipeline, in order
  run_all.R        regenerates figures 1-4
python/
  bert_cls_embeddings.py   BERT [CLS] embeddings for any text column
  keyword_categoriser.py   seed categories from the keyword taxonomy
data/
  reference/       SLEEPTALKING UMLS corpus; seed category keywords
  raw/             DPUK metadata corpus; per-cohort summary counts
  interim/         TF-IDF matches; BERT embeddings
  curated/         expert-reviewed outputs (the manual steps)
figures/
  published/       the figures exactly as they appear in the preprint
docs/
  methods_v2_2026.html     recommended upgrades for a version 2
```

### Data files worth knowing about

| File | Rows | What it is |
|---|---|---|
| `reference/sleeptalking_corpus.csv` | 2,032 | UMLS sleep terms, the reference dictionary |
| `raw/dpuk_metadata_corpus.csv` | 86,681 | Every variable description, 20 cohorts |
| `raw/cohort_summary.csv` | 20 | Variable counts and population size per cohort |
| `interim/sleep_dic_man.csv` | 754 | TF-IDF matches after manual review |
| `interim/cls_embeddings_*.csv` | 754 / 374 | BERT [CLS] vectors, 768-d |
| `curated/sleep_vars_umls_qc_manual.xlsx` | 376 | Expert YES/NO on each UMLS assignment |
| `curated/dpuk_sleep_definitions.csv` | 374 | Full-sentence definitions with agreed categories |
| `curated/consensus_category_count.csv` | 16 | The agreed category taxonomy and counts |
| `curated/hdbscan_clusters.csv` | 412 | Published cluster assignment |

---

## Before you build on this

Three things are important enough to state on the front page. All are covered in
full in [REPRODUCIBILITY.md](REPRODUCIBILITY.md).

1. **The preprint names MiniLM-L6-v2; the code uses `bert-base-uncased`.** The
   768-dimensional embedding files confirm the code. The manuscript needs
   correcting; the code here is left as it ran.

2. **Embeddings are joined to metadata by row position, with no key column.**
   Re-sorting a source table between the embedding step and the plotting step
   corrupts every figure silently. `assert_aligned()` guards each join. This
   already happened once during the original analysis — harmlessly, as verified
   in REPRODUCIBILITY.md — and fixing it properly is the first recommendation for
   a version 2.

3. **Figure 4's clustering is not exactly reproducible** across package versions,
   because its UMAP layout depends on RNG state left by a preceding t-SNE call.
   Script 05 detects when it has not reproduced the published cluster sizes and
   withholds the expert cluster labels rather than applying them to a different
   clustering.

---

## What changed in this release

The analysis is unchanged; the packaging is not. For anyone comparing against the
original `DPUK_NLP_share/` working directory:

- Four byte-identical copies of `sleep_dic_man.csv`, three of the UMLS QC table
  and two of the 5.5 MB metadata corpus reduced to one each. Two *different*
  files both named `metadata.csv` renamed to `cohort_summary.csv` and
  `dpuk_metadata_corpus.csv`.
- Three near-identical Python embedding scripts collapsed into one with
  arguments. ~230 duplicated lines between the `a1` and `a2` notebooks removed.
- The cohort palette, name lookup and helper functions — previously pasted into
  five places and drifting apart — centralised in `R/setup.R`.
- Hard-coded Windows paths (`C:/Users/Lonza Project/…`, `S:/0373_Sleep_Dementia/…`)
  replaced with `here::here()`.
- A broken `source("lonza_colorscheme.R")`, an order-dependent chain of `gsub()`
  cohort renames, an accidental `X.x` column reference, and unused loads of ~12
  packages fixed or removed.
- Hard-coded figure captions (`"n = 35,529"`) computed from the data instead.
- Every script given a header stating purpose, inputs, outputs and the rationale
  for its parameter choices; every human-judgement step marked `MANUAL STEP`.

---

## Citation

See [CITATION.cff](CITATION.cff).

Draper B, Briggs P, Purcell S, Dijk D-J, Bauermeister S, Bartsch U. *Leveraging
NLP to Identify Domain-Specific Variables in Large-Scale Cohort Metadata: A Sleep
Use Case.* medRxiv 2026.01.18.26344317.

## Licence

Code is MIT ([LICENSE](LICENSE)). The DPUK metadata is provided under the terms
agreed with Dementias Platform UK; contact the authors before redistributing it.
