#!/usr/bin/env python3
"""
Assign seed categories to sleep variable descriptions by keyword matching.

PURPOSE
    Step 4 of the METAMATCH pipeline, and the input to the expert consensus
    exercise. Produces a *first draft* categorisation of each sleep variable so
    that the reviewing researchers start from a proposal rather than a blank
    sheet.

    This script does NOT produce the categories reported in the paper. Its
    output was reviewed, corrected and agreed by the authors; that agreed
    version is data/curated/consensus_category_assignment.csv. The gap between
    the two is itself a finding -- see "What this step is for" below.

INPUTS
    --input     CSV of sleep variables (default: the curated definitions)
    --keywords  data/reference/initial_category_keywords.csv, the seed taxonomy

OUTPUT
    The input CSV with two added columns:
      Categories       -- topic categories matched (may be several, or
                          "Uncategorized" if none)
      Test Categories  -- validated instruments detected (PSQI, CESD, GHQ, ESS)

WHAT THIS STEP IS FOR
    Keyword matching is deliberately crude, and the paper's central claim rests
    on how crude it is. Substring matching over short questionnaire wording has
    three failure modes that are visible in the output:

      1. Over-matching. "time" is a keyword for Sleep Duration, so "How many
         times did you wake?" is labelled a duration question when it measures
         fragmentation.
      2. Under-matching. Nothing catches "How long does it take you to drop
         off?" as sleep latency, because the seed list has no entry for
         "drop off".
      3. Vocabulary collision across categories. "satisfied" appears under both
         Sleep Quality and Sleep Satisfaction, so those two are systematically
         conflated.

    A variable may legitimately hold more than one category (a PSQI item can be
    about both quality and duration), so matches are kept as a list rather than
    forced to one label. "Uncategorized" is dropped whenever any real category
    matched, so it means "nothing matched" rather than "matched nothing useful".

REFACTOR NOTE
    The original Classifier_2.py inlined the keyword dictionary as a Python
    literal, duplicating initial_category_keywords.csv. The two could drift
    apart independently. The dictionary is now read from that CSV, which is the
    single source of truth for the seed taxonomy. A `Set` column was added to
    the CSV to distinguish topic categories from validated-instrument
    categories; the original encoded that distinction only by which of the two
    inlined dictionaries a row sat in. Keywords themselves are unchanged.

USAGE
    python python/keyword_categoriser.py \
        --input  data/curated/dpuk_sleep_definitions.csv \
        --text-col Cohort_Var_Description \
        --output data/interim/seed_categories.csv
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import pandas as pd

UNCATEGORISED = "Uncategorized"  # US spelling retained: it is a data value


def load_keyword_sets(path: Path) -> tuple[dict[str, list[str]], dict[str, list[str]]]:
    """Read the seed taxonomy, split into topic and instrument dictionaries.

    Returns (topics, instruments), each mapping category name -> keyword list.
    """
    table = pd.read_csv(path)

    required = {"Category Type", "Set", "Keywords"}
    missing = required - set(table.columns)
    if missing:
        raise ValueError(f"{path} is missing column(s): {', '.join(sorted(missing))}")

    def to_dict(subset: pd.DataFrame) -> dict[str, list[str]]:
        return {
            row["Category Type"]: [k.strip() for k in str(row["Keywords"]).split(",")]
            for _, row in subset.iterrows()
        }

    topics = to_dict(table[table["Set"] == "topic"])
    instruments = to_dict(table[table["Set"] == "instrument"])
    return topics, instruments


def categorise(description: object, keyword_sets: dict[str, list[str]]) -> list[str]:
    """Return every category whose keywords appear in the description.

    Matching is case-insensitive substring matching, which is what makes it
    over-match on short words -- see the module docstring. It is kept as-is
    because this is the procedure the published consensus exercise reacted to.
    """
    if not isinstance(description, str):
        return [UNCATEGORISED]

    lowered = description.lower()
    matched = [
        category
        for category, keywords in keyword_sets.items()
        if any(keyword.lower() in lowered for keyword in keywords)
    ]
    return matched or [UNCATEGORISED]


def drop_redundant_uncategorised(categories: list[str]) -> list[str]:
    """Remove the Uncategorized placeholder when a real category also matched."""
    if UNCATEGORISED in categories and len(categories) > 1:
        return [c for c in categories if c != UNCATEGORISED]
    return categories


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--input",
        type=Path,
        default=Path("data/curated/dpuk_sleep_definitions.csv"),
        help="CSV of sleep variables to categorise",
    )
    parser.add_argument(
        "--keywords",
        type=Path,
        default=Path("data/reference/initial_category_keywords.csv"),
        help="seed taxonomy CSV",
    )
    parser.add_argument(
        "--text-col",
        default="Cohort_Var_Description",
        help="column holding the description to match against",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("data/interim/seed_categories.csv"),
        help="output CSV",
    )
    args = parser.parse_args(argv)

    topics, instruments = load_keyword_sets(args.keywords)
    print(
        f"Loaded {len(topics)} topic categories and "
        f"{len(instruments)} instrument categories",
        file=sys.stderr,
    )

    df = pd.read_csv(args.input)
    if args.text_col not in df.columns:
        parser.error(
            f"column {args.text_col!r} not in {args.input} "
            f"(available: {', '.join(df.columns)})"
        )

    descriptions = df[args.text_col]
    df["Categories"] = [
        drop_redundant_uncategorised(categorise(d, topics)) for d in descriptions
    ]
    df["Test Categories"] = [categorise(d, instruments) for d in descriptions]

    args.output.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(args.output, index=False)

    n_uncat = sum(c == [UNCATEGORISED] for c in df["Categories"])
    print(
        f"Wrote {len(df)} rows to {args.output} "
        f"({n_uncat} matched no topic category and need manual assignment)",
        file=sys.stderr,
    )
    print(
        "MANUAL STEP: this output is a draft. Review and agree categories by "
        "consensus, then save as data/curated/consensus_category_assignment.csv",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
