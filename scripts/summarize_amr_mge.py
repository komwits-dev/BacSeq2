#!/usr/bin/env python3
"""Create a compact AMR/VFDB/plasmid/MGE/prophage JSON summary for BacSeq2 report."""
from __future__ import annotations
import argparse, csv, json
from pathlib import Path


def count_lines(path: Path, header: bool=True) -> int:
    if not path.exists() or path.stat().st_size == 0:
        return 0
    n = sum(1 for _ in path.open(errors="ignore"))
    return max(0, n - 1) if header else n


def read_tsv_head(path: Path, max_rows: int=50):
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open(errors="ignore") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        return [row for _, row in zip(range(max_rows), reader)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sample", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--amrfinder", default="")
    ap.add_argument("--card", default="")
    ap.add_argument("--vfdb", default="")
    ap.add_argument("--mob", default="")
    ap.add_argument("--phigaro", default="")
    ap.add_argument("--mefinder", default="")
    args = ap.parse_args()

    paths = {k: Path(v) for k, v in vars(args).items() if k not in {"sample", "out"} and v}

    summary = {
        "sample": args.sample,
        "amr": {
            "amrfinderplus_hits": count_lines(paths.get("amrfinder", Path(""))),
            "card_rgi_hits": count_lines(paths.get("card", Path(""))),
            "amrfinderplus_preview": read_tsv_head(paths.get("amrfinder", Path("")), 30),
        },
        "virulence": {
            "vfdb_hits": count_lines(paths.get("vfdb", Path(""))),
            "vfdb_preview": read_tsv_head(paths.get("vfdb", Path("")), 30),
        },
        "plasmid_mge_phage": {
            "mob_suite_report_exists": paths.get("mob", Path("")).exists(),
            "mobileelementfinder_exists": paths.get("mefinder", Path("")).exists(),
            "phigaro_exists": paths.get("phigaro", Path("")).exists(),
        },
        "interpretation_note": (
            "Genomic AMR findings are resistance determinants, not a clinical antibiogram. "
            "Compare with AST phenotypes when available."
        ),
    }
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
