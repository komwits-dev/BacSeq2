#!/usr/bin/env python3
"""
Update BacSeq v2 config.yaml database paths automatically.

This script is intentionally dependency-light and uses only the Python standard
library plus optional PyYAML when available. It preserves unknown user settings
where possible and only updates database-related keys.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Dict, List


def quote_yaml(value: str) -> str:
    # Always quote to avoid issues with colon, spaces, or shell-expanded paths.
    escaped = value.replace('"', '\\"')
    return f'"{escaped}"'


def database_values(db_dir: Path, profile: str) -> Dict[str, str]:
    db_dir = db_dir.expanduser().resolve()
    values = {
        "database_dir": str(db_dir),
        "database_profile": profile,
        "mash_db": str(db_dir / "mash" / "bacseq_refseq.msh"),
        "gtdbtk_data": str(db_dir / "gtdbtk" / "gtdbtk_data"),
        "kraken2_db": str(db_dir / "kraken2" / "standard"),
        "kraken2_pluspf_db": str(db_dir / "kraken2" / "pluspf"),
        "taxdump_dir": str(db_dir / "taxdump"),
        "busco_db_path": "auto",
        "eggnog_db": str(db_dir / "eggnog"),
        "cazyme_db": str(db_dir / "dbcan"),
        "phastest_db": str(db_dir / "phastest"),
        "vfdb_path": str(db_dir / "vfdb" / "VFDB_setB_pro.fas"),
        "plasmidfinder_db": str(db_dir / "plasmidfinder"),
        "amrfinder_db": str(db_dir / "amrfinderplus"),
    }
    return values


def update_config_text(original: str, values: Dict[str, str]) -> str:
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

    new_lines.append("# BacSeq database paths managed by scripts/setup_databases.sh")
    for key in values:
        if key not in seen:
            new_lines.append(f"{key}: {quote_yaml(values[key])}")

    return "\n".join(new_lines).rstrip() + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Update BacSeq database paths in config.yaml")
    parser.add_argument("--config", required=True, help="Path to BacSeq config YAML")
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


if __name__ == "__main__":
    main()
