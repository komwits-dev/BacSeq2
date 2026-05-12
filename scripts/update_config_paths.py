#!/usr/bin/env python3
"""
Update BacSeq2 config.yaml database paths automatically.

Dependency-light: standard library only. Unknown user keys are preserved.
This version also turns Mash pre-check off when the Mash sketch is only a placeholder.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Dict, List


def quote_yaml(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    value = str(value)
    escaped = value.replace('"', '\\"')
    return f'"{escaped}"'


def is_real_mash_sketch(db_dir: Path) -> bool:
    mash = db_dir / "mash" / "bacseq_refseq.msh"
    placeholder = db_dir / "mash" / "MASH_PLACEHOLDER"
    skipped = db_dir / "mash" / "MASH_SKIPPED"
    return mash.is_file() and mash.stat().st_size > 1024 and not placeholder.exists() and not skipped.exists()


def database_values(db_dir: Path, profile: str) -> Dict[str, object]:
    db_dir = db_dir.expanduser().resolve()
    mash_real = is_real_mash_sketch(db_dir)
    return {
        "database_dir": str(db_dir),
        "database_profile": profile,
        "run_mash_precheck": mash_real,
        "mash_db": str(db_dir / "mash" / "bacseq_refseq.msh") if mash_real else "",
        "gtdbtk_data": str(db_dir / "gtdbtk" / "gtdbtk_data"),
        "kraken2_db": str(db_dir / "kraken2" / "standard"),
        "kraken2_pluspf_db": str(db_dir / "kraken2" / "pluspf"),
        "taxdump_dir": str(db_dir / "taxdump"),
        "busco_db_path": "auto",
        "eggnog_db": str(db_dir / "eggnog"),
        "cazyme_db": str(db_dir / "dbcan"),
        "phastest_db": str(db_dir / "phastest"),
        "amrfinder_db": str(db_dir / "amrfinderplus"),
        "card_rgi_db": str(db_dir / "card_rgi"),
        "resfinder_db": str(db_dir / "resfinder_db"),
        "pointfinder_db": str(db_dir / "pointfinder_db"),
        "vfdb_nt": str(db_dir / "vfdb" / "VFDB_setB_nt.fas"),
        "vfdb_prot": str(db_dir / "vfdb" / "VFDB_setB_pro.fas"),
        "vfdb_diamond_db": str(db_dir / "vfdb" / "VFDB_setB_pro.dmnd"),
        "mob_suite_db": str(db_dir / "mob_suite"),
        "plasmidfinder_db": str(db_dir / "plasmidfinder_db"),
        "mefinder_db": str(db_dir / "mobileelementfinder"),
        "phigaro_db": str(db_dir / "phigaro"),
        "genomad_db": str(db_dir / "genomad"),
    }


def update_config_text(original: str, values: Dict[str, object]) -> str:
    lines: List[str] = original.splitlines()
    seen = set()
    new_lines: List[str] = []

    for line in lines:
        stripped = line.strip()
        replaced = False
        if stripped and not stripped.startswith("#") and ":" in stripped:
            key = stripped.split(":", 1)[0].strip()
            if key in values:
                indent = line[: len(line) - len(line.lstrip())]
                new_lines.append(f"{indent}{key}: {quote_yaml(values[key])}")
                seen.add(key)
                replaced = True
        if not replaced:
            new_lines.append(line)

    if new_lines and new_lines[-1].strip():
        new_lines.append("")

    new_lines.append("# BacSeq2 database paths managed by scripts/setup_databases.sh")
    for key, value in values.items():
        if key not in seen:
            new_lines.append(f"{key}: {quote_yaml(value)}")

    return "\n".join(new_lines).rstrip() + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Update BacSeq2 database paths in config.yaml")
    parser.add_argument("--config", required=True, help="Path to BacSeq2 config YAML")
    parser.add_argument("--db-dir", required=True, help="Database directory")
    parser.add_argument("--profile", default="standard", choices=["minimal", "standard", "full"], help="Database profile")
    parser.add_argument("--json", action="store_true", help="Print updated values as JSON")
    args = parser.parse_args()

    config_path = Path(args.config)
    db_dir = Path(os.path.expanduser(args.db_dir))
    values = database_values(db_dir, args.profile)

    original = config_path.read_text() if config_path.exists() else ""
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(update_config_text(original, values))

    if args.json:
        print(json.dumps(values, indent=2))
    else:
        print(f"Updated database paths in {config_path}")
        if not values["run_mash_precheck"]:
            print("Note: run_mash_precheck=false because no real Mash sketch was detected.")


if __name__ == "__main__":
    main()
