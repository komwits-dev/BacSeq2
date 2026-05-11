#!/usr/bin/env python3
"""
Check BacSeq v2 database availability from config.yaml.

The checker is intentionally conservative: it reports missing paths but does not
attempt to validate every index file format. This makes it suitable for GitHub
support and user debugging.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Dict, Tuple


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


def status(path: str, path_type: str = "any") -> Tuple[bool, str]:
    if path == "auto":
        return True, "AUTO"
    p = Path(path).expanduser()
    if path_type == "file":
        ok = p.is_file()
    elif path_type == "dir":
        ok = p.is_dir()
    else:
        ok = p.exists()
    return ok, str(p)


def main() -> None:
    parser = argparse.ArgumentParser(description="Check BacSeq database paths")
    parser.add_argument("--config", default="config/config.yaml")
    parser.add_argument("--profile", default=None, choices=[None, "minimal", "standard", "full"])
    args = parser.parse_args()

    config = parse_simple_yaml(Path(args.config))
    profile = args.profile or config.get("database_profile", "standard")

    checks = [
        ("mash_db", "file", "Mash species sketch"),
        ("taxdump_dir", "dir", "NCBI taxdump"),
    ]
    if profile in {"standard", "full"}:
        checks.extend([
            ("gtdbtk_data", "dir", "GTDB-Tk database"),
            ("kraken2_db", "dir", "Kraken2 database"),
            ("busco_db_path", "any", "BUSCO datasets"),
            ("amrfinder_db", "dir", "AMRFinderPlus database"),
        ])
    if profile == "full":
        checks.extend([
            ("eggnog_db", "dir", "eggNOG database"),
            ("cazyme_db", "dir", "dbCAN database"),
            ("vfdb_path", "file", "VFDB protein database"),
            ("plasmidfinder_db", "dir", "PlasmidFinder database"),
            ("phastest_db", "dir", "PHASTEST/PHASTER local database folder"),
        ])

    print(f"BacSeq database check: {args.config}")
    print(f"Profile: {profile}\n")

    missing = 0
    for key, typ, label in checks:
        val = config.get(key, "")
        ok, shown = status(val, typ) if val else (False, "not configured")
        mark = "OK" if ok else "MISSING"
        if not ok:
            missing += 1
        print(f"[{mark:7}] {label:32} {key:18} {shown}")

    if missing:
        print(f"\n{missing} database item(s) are missing or not configured.")
        raise SystemExit(1)

    print("\nAll required database paths for this profile are present.")


if __name__ == "__main__":
    main()
