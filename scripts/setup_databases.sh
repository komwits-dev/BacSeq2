#!/usr/bin/env bash
set -Eeuo pipefail

# BacSeq v2 automatic database setup
#
# Profiles:
#   minimal  = tiny/fast test setup; no large taxonomy DB download
#   standard = routine bacterial WGS: Mash, GTDB-Tk, Kraken2, taxdump, AMRFinderPlus
#   full     = standard + eggNOG, dbCAN, VFDB, PlasmidFinder, PHASTEST folder
#
# Example:
#   bash scripts/setup_databases.sh --db-dir ~/bacseq_db --profile standard --threads 16

DB_DIR="$HOME/bacseq_db"
PROFILE="standard"
THREADS=8
CONFIG="config/config.yaml"
FORCE=0
SKIP_GTDGTK=0
SKIP_KRAKEN=0
SKIP_MASH=0
KRAKEN_MODE="standard"   # standard or pluspf; pluspf is optional and larger
MASH_FASTA=""            # optional user-curated reference FASTA for Mash
GTDB_URL="https://data.ace.uq.edu.au/public/gtdb/data/releases/latest/auxillary_files/gtdbtk_package/full_package/gtdbtk_data.tar.gz"
LOG_DIR=""

usage() {
  cat <<EOF
BacSeq v2 automatic database setup

Usage:
  bash scripts/setup_databases.sh [options]

Options:
  --db-dir DIR          Database directory [default: ~/bacseq_db]
  --profile PROFILE    minimal, standard, or full [default: standard]
  --threads N          Threads for database building [default: 8]
  --config FILE        BacSeq config file to update [default: config/config.yaml]
  --kraken-mode MODE   standard or pluspf [default: standard]
  --mash-fasta FILE    Optional reference FASTA to sketch for Mash
  --gtdb-url URL       Override GTDB-Tk database archive URL
  --skip-gtdbtk        Skip GTDB-Tk database download
  --skip-kraken        Skip Kraken2 database build/download
  --skip-mash          Skip Mash sketch creation
  --force              Rebuild/redownload selected databases when possible
  -h, --help           Show this help

Recommended first run:
  bash scripts/setup_databases.sh --db-dir ~/bacseq_db --profile standard --threads 16

Minimal test run:
  bash scripts/setup_databases.sh --db-dir ~/bacseq_db --profile minimal
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db-dir) DB_DIR="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --threads) THREADS="$2"; shift 2 ;;
    --config) CONFIG="$2"; shift 2 ;;
    --kraken-mode) KRAKEN_MODE="$2"; shift 2 ;;
    --mash-fasta) MASH_FASTA="$2"; shift 2 ;;
    --gtdb-url) GTDB_URL="$2"; shift 2 ;;
    --skip-gtdbtk) SKIP_GTDGTK=1; shift ;;
    --skip-kraken) SKIP_KRAKEN=1; shift ;;
    --skip-mash) SKIP_MASH=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ "$PROFILE" != "minimal" && "$PROFILE" != "standard" && "$PROFILE" != "full" ]]; then
  echo "ERROR: --profile must be minimal, standard, or full" >&2
  exit 1
fi
if [[ "$KRAKEN_MODE" != "standard" && "$KRAKEN_MODE" != "pluspf" ]]; then
  echo "ERROR: --kraken-mode must be standard or pluspf" >&2
  exit 1
fi

DB_DIR="$(python3 - <<PY
from pathlib import Path
print(Path('$DB_DIR').expanduser().resolve())
PY
)"
LOG_DIR="$DB_DIR/logs"
mkdir -p "$DB_DIR" "$LOG_DIR" "$(dirname "$CONFIG")"

LOG_FILE="$LOG_DIR/setup_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

trap 'echo "ERROR at line $LINENO. See log: $LOG_FILE" >&2' ERR

msg() { echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    echo "Install it in your BacSeq conda environment or use --skip options where appropriate." >&2
    exit 1
  fi
}

safe_download() {
  local url="$1"
  local out="$2"
  mkdir -p "$(dirname "$out")"
  if [[ -s "$out" && "$FORCE" -eq 0 ]]; then
    echo "Found existing: $out"
    return 0
  fi
  if command -v aria2c >/dev/null 2>&1; then
    aria2c -x 8 -s 8 -c -o "$(basename "$out")" -d "$(dirname "$out")" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -c "$url" -O "$out"
  elif command -v curl >/dev/null 2>&1; then
    curl -L -C - "$url" -o "$out"
  else
    echo "ERROR: need aria2c, wget, or curl for downloads" >&2
    exit 1
  fi
}

make_mash_db() {
  msg "Preparing Mash database"
  mkdir -p "$DB_DIR/mash"
  local out="$DB_DIR/mash/bacseq_refseq.msh"
  if [[ -s "$out" && "$FORCE" -eq 0 ]]; then
    echo "Mash sketch already exists: $out"
    return 0
  fi
  if [[ "$SKIP_MASH" -eq 1 ]]; then
    echo "Skipping Mash database (--skip-mash)."
    touch "$DB_DIR/mash/PLACEHOLDER_SKIPPED"
    return 0
  fi
  if [[ -n "$MASH_FASTA" ]]; then
    need_cmd mash
    if [[ ! -s "$MASH_FASTA" ]]; then
      echo "ERROR: --mash-fasta not found: $MASH_FASTA" >&2
      exit 1
    fi
    mash sketch -p "$THREADS" -o "$DB_DIR/mash/bacseq_refseq" "$MASH_FASTA"
  else
    echo "No --mash-fasta supplied. Creating a placeholder path for config."
    echo "For production, build a curated bacterial RefSeq/GTDB sketch and save it as:" > "$DB_DIR/mash/README.txt"
    echo "$out" >> "$DB_DIR/mash/README.txt"
    touch "$out"
  fi
}

setup_taxdump() {
  msg "Preparing NCBI taxdump"
  mkdir -p "$DB_DIR/taxdump"
  if [[ -s "$DB_DIR/taxdump/names.dmp" && -s "$DB_DIR/taxdump/nodes.dmp" && "$FORCE" -eq 0 ]]; then
    echo "NCBI taxdump already exists."
    return 0
  fi
  local archive="$DB_DIR/taxdump/taxdump.tar.gz"
  safe_download "https://ftp.ncbi.nlm.nih.gov/pub/taxonomy/taxdump.tar.gz" "$archive"
  tar -xzf "$archive" -C "$DB_DIR/taxdump"
}

setup_gtdbtk() {
  msg "Preparing GTDB-Tk database"
  if [[ "$SKIP_GTDGTK" -eq 1 ]]; then
    echo "Skipping GTDB-Tk database (--skip-gtdbtk)."
    mkdir -p "$DB_DIR/gtdbtk/gtdbtk_data"
    return 0
  fi
  mkdir -p "$DB_DIR/gtdbtk"
  if [[ -d "$DB_DIR/gtdbtk/gtdbtk_data" && "$FORCE" -eq 0 ]]; then
    echo "GTDB-Tk database directory already exists: $DB_DIR/gtdbtk/gtdbtk_data"
    return 0
  fi
  local archive="$DB_DIR/gtdbtk/gtdbtk_data.tar.gz"
  safe_download "$GTDB_URL" "$archive"
  rm -rf "$DB_DIR/gtdbtk/extracted"
  mkdir -p "$DB_DIR/gtdbtk/extracted"
  tar -xzf "$archive" -C "$DB_DIR/gtdbtk/extracted"

  # GTDB archives can contain a release folder. Pick a directory containing metadata or markers if possible.
  local found=""
  found=$(find "$DB_DIR/gtdbtk/extracted" -type f \( -name "metadata.txt" -o -name "VERSION" -o -name "*.sha256" \) -printf '%h\n' 2>/dev/null | head -n 1 || true)
  if [[ -z "$found" ]]; then
    found=$(find "$DB_DIR/gtdbtk/extracted" -maxdepth 2 -type d | tail -n 1 || true)
  fi
  if [[ -z "$found" ]]; then
    echo "ERROR: Could not identify GTDB-Tk extracted directory." >&2
    exit 1
  fi
  ln -sfn "$found" "$DB_DIR/gtdbtk/gtdbtk_data"
  echo "GTDBTK_DATA_PATH=$DB_DIR/gtdbtk/gtdbtk_data" > "$DB_DIR/gtdbtk/activate_gtdbtk.env"
}

setup_kraken2() {
  msg "Preparing Kraken2 database ($KRAKEN_MODE)"
  if [[ "$SKIP_KRAKEN" -eq 1 ]]; then
    echo "Skipping Kraken2 database (--skip-kraken)."
    mkdir -p "$DB_DIR/kraken2/$KRAKEN_MODE"
    return 0
  fi
  need_cmd kraken2-build
  mkdir -p "$DB_DIR/kraken2"
  local target="$DB_DIR/kraken2/$KRAKEN_MODE"
  if [[ -s "$target/hash.k2d" && "$FORCE" -eq 0 ]]; then
    echo "Kraken2 database already exists: $target"
    return 0
  fi
  if [[ "$KRAKEN_MODE" == "standard" ]]; then
    kraken2-build --standard --threads "$THREADS" --db "$target"
  else
    # pluspf support depends on Kraken2 version. If not supported, user can rerun standard.
    kraken2-build --download-library archaea --threads "$THREADS" --db "$target"
    kraken2-build --download-library bacteria --threads "$THREADS" --db "$target"
    kraken2-build --download-library viral --threads "$THREADS" --db "$target"
    kraken2-build --download-library plasmid --threads "$THREADS" --db "$target" || true
    kraken2-build --download-library fungi --threads "$THREADS" --db "$target" || true
    kraken2-build --download-library protozoa --threads "$THREADS" --db "$target" || true
    kraken2-build --download-taxonomy --threads "$THREADS" --db "$target"
    kraken2-build --build --threads "$THREADS" --db "$target"
  fi
  kraken2-build --clean --db "$target" || true
}

setup_amrfinder() {
  msg "Preparing AMRFinderPlus database"
  mkdir -p "$DB_DIR/amrfinderplus"
  if command -v amrfinder_update >/dev/null 2>&1; then
    amrfinder_update --database "$DB_DIR/amrfinderplus" || {
      echo "WARNING: amrfinder_update failed. The pipeline can still run if AMRFinderPlus uses its default database."
    }
  else
    echo "WARNING: amrfinder_update not found. Skipping AMRFinderPlus database update."
  fi
}

setup_full_extra() {
  msg "Preparing full-profile databases"

  mkdir -p "$DB_DIR/eggnog" "$DB_DIR/dbcan" "$DB_DIR/phastest" "$DB_DIR/vfdb" "$DB_DIR/plasmidfinder"

  if command -v download_eggnog_data.py >/dev/null 2>&1; then
    download_eggnog_data.py --data_dir "$DB_DIR/eggnog" -y || echo "WARNING: eggNOG database download failed."
  else
    echo "WARNING: download_eggnog_data.py not found. Skipping eggNOG."
  fi

  if command -v run_dbcan >/dev/null 2>&1; then
    run_dbcan database --db_dir "$DB_DIR/dbcan" || echo "WARNING: dbCAN database download failed."
  else
    echo "WARNING: run_dbcan not found. Skipping dbCAN."
  fi

  # VFDB protein set. This endpoint has historically been stable but may change.
  local vfdb_zip="$DB_DIR/vfdb/VFDB_setB_pro.fas.gz"
  if [[ ! -s "$DB_DIR/vfdb/VFDB_setB_pro.fas" || "$FORCE" -eq 1 ]]; then
    safe_download "http://www.mgc.ac.cn/VFs/Down/VFDB_setB_pro.fas.gz" "$vfdb_zip" || echo "WARNING: VFDB download failed."
    if [[ -s "$vfdb_zip" ]]; then
      gunzip -kf "$vfdb_zip"
    fi
  fi

  if command -v download-db.sh >/dev/null 2>&1; then
    # PlasmidFinder/ResFinder scripts vary by install. This is best-effort.
    (cd "$DB_DIR/plasmidfinder" && download-db.sh) || true
  else
    echo "PlasmidFinder database auto-download not available in this environment."
    echo "Install plasmidfinder database manually into: $DB_DIR/plasmidfinder" > "$DB_DIR/plasmidfinder/README.txt"
  fi

  echo "PHASTEST/PHASTER local database is optional. Add local database files here if used." > "$DB_DIR/phastest/README.txt"
}

write_env_hint() {
  cat > "$DB_DIR/activate_bacseq_db.sh" <<EOF
# Source this file before running GTDB-Tk through BacSeq when needed.
export BACSEQ_DB="$DB_DIR"
export GTDBTK_DATA_PATH="$DB_DIR/gtdbtk/gtdbtk_data"
EOF
  echo "Wrote environment helper: $DB_DIR/activate_bacseq_db.sh"
}

update_config() {
  msg "Updating BacSeq config"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  python3 "$script_dir/update_config_paths.py" --config "$CONFIG" --db-dir "$DB_DIR" --profile "$PROFILE"
}

main() {
  msg "BacSeq v2 database setup started"
  echo "Database directory : $DB_DIR"
  echo "Profile            : $PROFILE"
  echo "Threads            : $THREADS"
  echo "Config             : $CONFIG"
  echo "Log                : $LOG_FILE"

  need_cmd python3
  need_cmd tar

  make_mash_db
  setup_taxdump

  if [[ "$PROFILE" == "standard" || "$PROFILE" == "full" ]]; then
    setup_gtdbtk
    setup_kraken2
    setup_amrfinder
  fi

  if [[ "$PROFILE" == "full" ]]; then
    setup_full_extra
  fi

  update_config
  write_env_hint

  msg "Checking database paths"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  python3 "$script_dir/check_databases.py" --config "$CONFIG" --profile "$PROFILE" || true

  msg "BacSeq database setup finished"
  echo "Next step:"
  echo "  source $DB_DIR/activate_bacseq_db.sh"
  echo "  snakemake --snakefile Snakefile --configfile $CONFIG --cores $THREADS --use-conda --dry-run"
}

main "$@"
