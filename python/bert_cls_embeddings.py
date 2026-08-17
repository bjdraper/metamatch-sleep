#!/usr/bin/env python3
"""
Generate BERT [CLS] embeddings for a column of free-text variable descriptions.

PURPOSE
    Step 3 of the METAMATCH pipeline. Turns each metadata variable description
    into a dense vector so that semantically similar descriptions sit close
    together, regardless of how differently they are worded across cohorts.

INPUTS
    A CSV with one column of free text. Three separate runs are needed to
    reproduce the paper (see --help epilog for the exact commands):
      1. the full DPUK metadata corpus      (86,682 rows) -> Figure 3a
      2. the TF-IDF matched sleep variables (   754 rows) -> Figure 3b
      3. the curated full-sentence sleep definitions (374) -> Figure 4

OUTPUT
    A CSV with 768 numeric columns (one per bert-base-uncased hidden dimension)
    plus a trailing `definition` column holding the cleaned input text.

    !! The output has NO KEY COLUMN. Row i of the output corresponds to row i of
    !! the input and to nothing else. Everything downstream joins on that
    !! positional correspondence, so never re-sort or filter the input CSV
    !! between running this script and running the R analysis. See
    !! REPRODUCIBILITY.md ("Positional joins").

RATIONALE
    Why BERT rather than the TF-IDF vectors already computed in step 2?
    TF-IDF matches shared vocabulary; it cannot tell that "trouble getting off
    to sleep" and "difficulty initiating sleep" mean the same thing. BERT
    produces contextualised representations, so paraphrases converge. TF-IDF is
    kept for retrieval (it is fast over 86,682 x 2,032 comparisons and its
    scores are interpretable for the manual QC cut) and BERT is used for the
    semantic analysis that follows.

    Why the [CLS] token? It is the position BERT is pre-trained to use as a
    whole-sequence summary, and taking it is the standard cheap sentence
    representation. It is a known-weak one -- untuned [CLS] vectors are
    anisotropic and often underperform simple mean-pooling. This is the single
    highest-value thing to change in a version 2; see docs/methods_v2_2026.html.

    Why bert-base-uncased? Sleep variable descriptions are participant-facing
    questionnaire wording ("How often have you been bothered by..."), which is
    general English rather than clinical prose, so a general-domain uncased
    model is a reasonable fit. NOTE: the preprint states MiniLM-L6-v2 was used.
    The code that produced the published embeddings uses bert-base-uncased, and
    the shipped embedding files are 768-dimensional, which confirms it (MiniLM
    is 384-dimensional). See REPRODUCIBILITY.md ("Model discrepancy").

REPLACES
    main.py, bigML.py and fulldefinition_embeddings.py from the original
    working directory. Those three files were byte-identical apart from a
    hard-coded Windows input path and the name of the text column, so they are
    collapsed here into one script with those two values as arguments.

USAGE
    python python/bert_cls_embeddings.py \
        --input data/interim/sleep_dic_man.csv \
        --text-col From \
        --output data/interim/cls_embeddings_sleep754.csv
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import pandas as pd
import torch
from transformers import BertModel, BertTokenizer

MODEL_NAME = "bert-base-uncased"
MAX_TOKENS = 512  # bert-base positional-embedding limit


def clean_text(text: object) -> str:
    """Normalise one variable description before embedding.

    The substitutions run in a fixed order and each removes a distinct kind of
    noise observed in DPUK metadata. Order matters: bracket contents are
    stripped before punctuation, otherwise removing the brackets first would
    leave their contents behind as loose words.

    Non-string input (blank cells read by pandas as NaN) returns "" rather than
    raising, so that a sparse column does not abort a long run. Blank rows still
    produce an embedding, which keeps the output row-aligned with the input.
    """
    if not isinstance(text, str):
        return ""

    # Questionnaire item codes embedded in the description, e.g. "q15k".
    text = re.sub(r"q\d+k", "", text)

    # Parenthetical asides: units, coding notes, "(see data dictionary)".
    # These describe the encoding, not the concept being measured.
    text = re.sub(r"\(.*?\)|\[.*?\]|\{.*?\}", "", text)

    # Punctuation. Cohorts punctuate inconsistently ("sleep quality?" vs
    # "sleep quality"), which would otherwise fragment the token stream.
    text = re.sub(r"[^\w\s]", "", text)

    # Orphaned single characters left by the substitutions above, e.g. the "s"
    # in CFAS's "s. has difficulty in sleeping?" (a proxy-respondent prefix).
    text = re.sub(r"\s[\da-zA-Z]?\s", " ", text)

    # Collapse whitespace introduced by the removals.
    return re.sub(r"\s+", " ", text).strip()


def embed_cls(text: str, tokenizer: BertTokenizer, model: BertModel) -> list[float]:
    """Return the [CLS] hidden state for one string as a plain list of floats."""
    inputs = tokenizer(
        text,
        return_tensors="pt",
        truncation=True,
        padding=True,
        max_length=MAX_TOKENS,
    )
    with torch.no_grad():
        outputs = model(**inputs)

    # last_hidden_state is (batch, tokens, hidden). Token 0 is [CLS].
    return outputs.last_hidden_state[:, 0, :].squeeze().tolist()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Commands that reproduce the three embedding files used in the paper:

  # Figure 3a -- full metadata corpus. ~86,682 rows, several hours on CPU,
  # produces a ~1.3 GB CSV that is deliberately not committed to this repo.
  python python/bert_cls_embeddings.py \\
      --input  data/raw/dpuk_metadata_corpus.csv \\
      --text-col fdd_desc \\
      --output data/interim/cls_embeddings_corpus86k.csv

  # Figure 3b -- TF-IDF matched sleep variables (754 rows).
  python python/bert_cls_embeddings.py \\
      --input  data/interim/sleep_dic_man.csv \\
      --text-col From \\
      --output data/interim/cls_embeddings_sleep754.csv

  # Figure 4 -- curated full-sentence sleep definitions (374 rows).
  python python/bert_cls_embeddings.py \\
      --input  data/curated/dpuk_sleep_definitions.csv \\
      --text-col Full_Description \\
      --output data/interim/cls_embeddings_fulldef374.csv
""",
    )
    parser.add_argument("--input", required=True, type=Path, help="input CSV")
    parser.add_argument(
        "--text-col",
        required=True,
        help="column holding the free-text description to embed",
    )
    parser.add_argument("--output", required=True, type=Path, help="output CSV")
    parser.add_argument(
        "--encoding",
        default="cp1252",
        help=(
            "input encoding (default cp1252). The DPUK metadata exports contain "
            "Windows-1252 smart quotes and en-dashes that fail under utf-8."
        ),
    )
    args = parser.parse_args(argv)

    print(f"Loading {MODEL_NAME} ...", file=sys.stderr)
    tokenizer = BertTokenizer.from_pretrained(MODEL_NAME)
    model = BertModel.from_pretrained(MODEL_NAME)
    model.eval()  # disable dropout; embeddings must be deterministic

    df = pd.read_csv(args.input, encoding=args.encoding)
    if args.text_col not in df.columns:
        parser.error(
            f"column {args.text_col!r} not in {args.input} "
            f"(available: {', '.join(df.columns)})"
        )

    cleaned = [clean_text(value) for value in df[args.text_col].tolist()]
    print(f"Embedding {len(cleaned)} descriptions ...", file=sys.stderr)

    vectors = []
    for i, text in enumerate(cleaned, start=1):
        vectors.append(embed_cls(text, tokenizer, model))
        if i % 1000 == 0:
            print(f"  {i}/{len(cleaned)}", file=sys.stderr)

    out = pd.DataFrame(vectors)
    out["definition"] = cleaned  # retained for inspection; dropped by the R side

    args.output.parent.mkdir(parents=True, exist_ok=True)
    out.to_csv(args.output, index=False)

    # Row counts are printed so they can be checked against the input before
    # the positional join on the R side.
    print(
        f"Wrote {len(out)} x {len(out.columns) - 1} embeddings to {args.output}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
