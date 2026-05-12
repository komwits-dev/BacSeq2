#!/usr/bin/env bash
set -Eeuo pipefail

# Repair BacSeq2 database links and config without re-downloading large databases.
# Main use case: older setup script pointed GTDBTK_DATA_PATH to release*/metadata instead of release* root.

DB_DIR="$HOME/bacseq_db"
CONFIG="config/config.yaml"
PROFILE="standard"

usage() {
  cat <<USAGE
BacSeq2 database repair helper

Usage:
  bin/bacseq repair-db --db-dir DIR --config config/config.yaml [--profile standard|full]

What it repairs:
  1. GTDB-Tk gtdbtk_data symlink to the release root folder
  2. config/config.yaml database paths
  3. activate_bacseq_db.sh environment helper
  4. warns about placeholder Mash sketches
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db-dir) DB_DIR="$2"; shift 2 ;;
    --config) CONFIG="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

DB_DIR="$(python3 - <<PY
from pathlib import Path
print(Path('$DB_DIR').expanduser().resolve())
PY
)"

validate_gtdb_root() {
  local d="$1"
  [[ -d "$d" ]] || return 1
  [[ -d "$d/markers" ]] || return 1
  [[ -d "$d/metadata" ]] || return 1
  [[ -d "$d/msa" ]] || return 1
  [[ -d "$d/pplacer" ]] || return 1
  [[ -d "$d/taxonomy" ]] || return 1
  [[ -d "$d/skani" || -d "$d/masks" ]] || return 1
  return 0
}

find_gtdb_root() {
  local base="$DB_DIR/gtdbtk"
  local candidate=""
  while IFS= read -r candidate; do
    if validate_gtdb_root "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done < <(find "$base" -maxdepth 4 -type d \( -name 'release*' -o -name 'gtdbtk_*' \) 2>/dev/null | sort -V)

  while IFS= read -r candidate; do
    if validate_gtdb_root "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done < <(find "$base" -maxdepth 4 -type d 2>/dev/null | sort -V)
  return 1
}

echo "BacSeq2 database repair"
echo "DB_DIR : $DB_DIR"
echo "CONFIG : $CONFIG"
echo "PROFILE: $PROFILE"

mkdir -p "$DB_DIR/gtdbtk"
LINK="$DB_DIR/gtdbtk/gtdbtk_data"

if validate_gtdb_root "$LINK"; then
  echo "GTDB-Tk path already valid: $(readlink -f "$LINK" 2>/dev/null || echo "$LINK")"
else
  if [[ -e "$LINK" || -L "$LINK" ]]; then
    echo "Current GTDB-Tk path is invalid: $(readlink -f "$LINK" 2>/dev/null || echo "$LINK")"
  fi
  ROOT="$(find_gtdb_root)" || {
    echo "ERROR: Could not find valid GTDB-Tk release root under $DB_DIR/gtdbtk" >&2
    echo "Expected a directory containing markers/, metadata/, msa/, pplacer/, taxonomy/." >&2
    exit 1
  }
  rm -rf "$LINK"
  ln -sfn "$ROOT" "$LINK"
  echo "Fixed GTDB-Tk symlink: $LINK -> $ROOT"
fi

cat > "$DB_DIR/activate_bacseq_db.sh" <<ENV
# Source this before running BacSeq2 when databases are stored outside Home.
export BACSEQ_DB="$DB_DIR"
export GTDBTK_DATA_PATH="$DB_DIR/gtdbtk/gtdbtk_data"
export AMRFINDER_DB="$DB_DIR/amrfinderplus"
export MOB_SUITE_DB="$DB_DIR/mob_suite"
ENV

echo "Updated: $DB_DIR/activate_bacseq_db.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$SCRIPT_DIR/update_config_paths.py" --config "$CONFIG" --db-dir "$DB_DIR" --profile "$PROFILE"
python3 "$SCRIPT_DIR/check_databases.py" --config "$CONFIG" --profile "$PROFILE" || true

echo "Done. Now run:"
echo "  source $DB_DIR/activate_bacseq_db.sh"
echo "  bin/bacseq check-db --config $CONFIG"
