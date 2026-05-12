#!/usr/bin/env python3
"""
Check BacSeq2 database availability and common misconfiguration problems.

This checker is stricter for GTDB-Tk: gtdbtk_data must point to the release root,
not to metadata/. It also treats placeholder Mash sketches as WARN instead of OK.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Dict, Tuple, List


def parse_simple_yaml(path: Path) -> Dict[str, str]:
    data: Dict[str, str] = {}
    if not path.exists():
        return data
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        key, value = line.split(":", 1)
        value = value.strip().strip('"').strip("'")
        data[key.strip()] = value
    return data


def as_bool(value: str, default: bool = False) -> bool:
    if value is None or value == "":
        return default
    return value.strip().lower() in {"1", "yes", "true", "on"}


def exists_status(path: str, path_type: str = "any") -> Tuple[str, str]:
    if path == "auto":
        return "OK", "AUTO"
    if not path:
        return "WARN", "not configured"
    p = Path(path).expanduser()
    if path_type == "file":
        ok = p.is_file()
    elif path_type == "dir":
        ok = p.is_dir()
    else:
        ok = p.exists()
    return ("OK" if ok else "MISSING"), str(p)


def validate_gtdb_root(path: str) -> Tuple[str, str]:
    if not path:
        return "MISSING", "not configured"
    p = Path(path).expanduser()
    resolved = p.resolve() if p.exists() or p.is_symlink() else p
    required = ["markers", "metadata", "msa", "pplacer", "taxonomy"]
    missing = [x for x in required if not (resolved / x).is_dir()]
    if missing:
        if resolved.name == "metadata":
            return "MISSING", f"{resolved}  <-- wrong: points to metadata/; run: bin/bacseq repair-db"
        return "MISSING", f"{resolved}  missing: {','.join(missing)}"
    return "OK", str(resolved)


def validate_taxdump(path: str) -> Tuple[str, str]:
    if not path:
        return "MISSING", "not configured"
    p = Path(path).expanduser()
    names = p / "names.dmp"
    nodes = p / "nodes.dmp"
    if names.is_file() and nodes.is_file():
        return "OK", str(p)
    return "MISSING", f"{p}  missing names.dmp/nodes.dmp"


def validate_kraken(path: str) -> Tuple[str, str]:
    if not path:
        return "WARN", "not configured"
    p = Path(path).expanduser()
    if (p / "hash.k2d").is_file():
        return "OK", str(p)
    if p.is_dir():
        return "WARN", f"{p} exists but hash.k2d not found"
    return "MISSING", str(p)


def validate_mash(path: str, run_mash: bool) -> Tuple[str, str]:
    if not run_mash:
        return "WARN", "Mash pre-check disabled; supply --mash-fasta to enable"
    if not path:
        return "MISSING", "run_mash_precheck=true but mash_db is not configured"
    p = Path(path).expanduser()
    if p.is_file() and p.stat().st_size > 1024:
        return "OK", str(p)
    if p.is_file():
        return "WARN", f"{p} exists but looks like a placeholder/empty sketch"
    return "MISSING", str(p)


def print_check(mark: str, label: str, key: str, shown: str) -> None:
    print(f"[{mark:7}] {label:36} {key:20} {shown}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Check BacSeq2 database paths")
    parser.add_argument("--config", default="config/config.yaml")
    parser.add_argument("--profile", default=None, choices=["minimal", "standard", "full"])
    args = parser.parse_args()

    config_path = Path(args.config)
    config = parse_simple_yaml(config_path)
    profile = args.profile or config.get("database_profile", "standard")
    run_mash = as_bool(config.get("run_mash_precheck", "false"), False)

    print(f"BacSeq2 database check: {config_path}")
    print(f"Profile: {profile}\n")

    missing = 0
    warn = 0

    checks: List[Tuple[str, str, str, str]] = []

    mark, shown = validate_mash(config.get("mash_db", ""), run_mash)
    checks.append((mark, "Mash species sketch", "mash_db", shown))

    mark, shown = validate_taxdump(config.get("taxdump_dir", ""))
    checks.append((mark, "NCBI taxdump", "taxdump_dir", shown))

    if profile in {"standard", "full"}:
        mark, shown = validate_gtdb_root(config.get("gtdbtk_data", ""))
        checks.append((mark, "GTDB-Tk release root", "gtdbtk_data", shown))
        mark, shown = validate_kraken(config.get("kraken2_db", ""))
        checks.append((mark, "Kraken2 database", "kraken2_db", shown))
        mark, shown = exists_status(config.get("busco_db_path", "auto"), "any")
        checks.append((mark, "BUSCO datasets", "busco_db_path", shown))
        mark, shown = exists_status(config.get("amrfinder_db", ""), "dir")
        checks.append((mark, "AMRFinderPlus database", "amrfinder_db", shown))

    if profile == "full":
        for key, typ, label in [
            ("eggnog_db", "dir", "eggNOG database"),
            ("cazyme_db", "dir", "dbCAN database"),
            ("card_rgi_db", "dir", "CARD/RGI local DB folder"),
            ("resfinder_db", "dir", "ResFinder database"),
            ("pointfinder_db", "dir", "PointFinder database"),
            ("vfdb_nt", "file", "VFDB nucleotide FASTA"),
            ("vfdb_prot", "file", "VFDB protein FASTA"),
            ("vfdb_diamond_db", "file", "VFDB DIAMOND DB"),
            ("mob_suite_db", "dir", "MOB-suite database"),
            ("plasmidfinder_db", "dir", "PlasmidFinder database"),
            ("mefinder_db", "dir", "MobileElementFinder folder"),
            ("phigaro_db", "dir", "Phigaro folder"),
            ("genomad_db", "dir", "geNomad database folder"),
            ("phastest_db", "dir", "PHASTEST/PHASTER folder"),
        ]:
            mark, shown = exists_status(config.get(key, ""), typ)
            checks.append((mark, label, key, shown))

    for mark, label, key, shown in checks:
        if mark == "MISSING":
            missing += 1
        elif mark == "WARN":
            warn += 1
        print_check(mark, label, key, shown)

    if missing:
        print(f"\n{missing} required database item(s) are missing or invalid.")
        print("Suggested first repair command:")
        dbdir = config.get("database_dir", "~/bacseq_db")
        print(f"  bin/bacseq repair-db --db-dir {dbdir} --config {config_path} --profile {profile}")
        raise SystemExit(1)

    if warn:
        print(f"\nDatabase check passed with {warn} warning(s).")
    else:
        print("\nAll required database paths for this profile are present.")


if __name__ == "__main__":
    main()
