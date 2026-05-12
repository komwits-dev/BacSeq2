#!/usr/bin/env bash
set -Eeuo pipefail

# BacSeq2 automatic core database setup
# Profiles:
#   minimal  = config + taxdump only, suitable for testing Snakemake structure
#   standard = routine bacterial WGS: taxdump, GTDB-Tk, Kraken2, AMRFinderPlus, optional Mash
#   full     = standard + eggNOG/dbCAN/VFDB/PlasmidFinder placeholders
#
# Design notes:
# - Never points GTDBTK_DATA_PATH to metadata/. It validates the release root.
# - Detects and repairs wrong GTDB-Tk symlinks from older setup scripts.
# - Avoids aria2 pre-allocation, which looks like a stalled 0B download.
# - Validates gzip archives before extraction and re-downloads corrupt files.

DB_DIR="$HOME/bacseq_db"
PROFILE="standard"
THREADS=8
CONFIG="config/config.yaml"
FORCE=0
SKIP_GTDBTK=0
SKIP_KRAKEN=0
SKIP_MASH=0
KRAKEN_MODE="standard"
MASH_FASTA=""
GTDB_URL="https://data.ace.uq.edu.au/public/gtdb/data/releases/latest/auxillary_files/gtdbtk_package/full_package/gtdbtk_data.tar.gz"
LOG_DIR=""

usage() {
  cat <<USAGE
BacSeq2 automatic core database setup

Usage:
  bin/bacseq setup-db [options]
  bash scripts/setup_databases.sh [options]

Options:
  --db-dir DIR          Database directory [default: ~/bacseq_db]
  --profile PROFILE    minimal, standard, or full [default: standard]
  --threads N          Threads for database building [default: 8]
  --config FILE        BacSeq2 config file to update [default: config/config.yaml]
  --kraken-mode MODE   standard or pluspf [default: standard]
  --mash-fasta FILE    Optional reference FASTA/FASTA.GZ to sketch for Mash
  --gtdb-url URL       Override GTDB-Tk database archive URL
  --skip-gtdbtk        Skip GTDB-Tk download/setup
  --skip-kraken        Skip Kraken2 download/build
  --skip-mash          Skip Mash setup
  --force              Rebuild/redownload selected databases when possible
  -h, --help           Show this help

Recommended large-disk example:
  bin/bacseq setup-db \
    --db-dir /path/to/large_disk/BacSeq_DB \
    --profile standard \
    --threads 16 \
    --config config/config.yaml

If you already downloaded GTDB-Tk but the symlink is wrong:
  bin/bacseq repair-db --db-dir /path/to/large_disk/BacSeq_DB --config config/config.yaml
USAGE
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
    --skip-gtdbtk) SKIP_GTDBTK=1; shift ;;
    --skip-kraken) SKIP_KRAKEN=1; shift ;;
    --skip-mash) SKIP_MASH=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown option: $1" >&2; usage; exit 1 ;;
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
LOG_FILE="$LOG_DIR/setup_core_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'echo "ERROR at line $LINENO. See log: '$LOG_FILE'" >&2' ERR

msg() { echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
warn() { echo "WARNING: $*" >&2; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }
need_cmd() {
  if ! has_cmd "$1"; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

safe_download() {
  local url="$1"
  local out="$2"
  local tries=2
  mkdir -p "$(dirname "$out")"

  if [[ -s "$out" && "$FORCE" -eq 0 ]]; then
    echo "Found existing: $out"
    return 0
  fi

  rm -f "$out.aria2" 2>/dev/null || true
  for attempt in $(seq 1 "$tries"); do
    echo "Download attempt $attempt/$tries: $url"
    if has_cmd aria2c; then
      aria2c \
        --continue=true \
        --max-connection-per-server=8 \
        --split=8 \
        --file-allocation=none \
        --auto-file-renaming=false \
        --allow-overwrite=true \
        -o "$(basename "$out")" \
        -d "$(dirname "$out")" \
        "$url" && return 0
    elif has_cmd wget; then
      wget -c "$url" -O "$out" && return 0
    elif has_cmd curl; then
      curl -L -C - "$url" -o "$out" && return 0
    else
      echo "ERROR: need aria2c, wget, or curl for downloads" >&2
      return 1
    fi
    sleep 5
  done
  return 1
}

valid_gzip() {
  local archive="$1"
  [[ -s "$archive" ]] && gzip -t "$archive" >/dev/null 2>&1
}

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

  # Prefer release folders because official GTDB-Tk archives usually extract this way.
  while IFS= read -r candidate; do
    if validate_gtdb_root "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done < <(find "$base" -maxdepth 4 -type d \( -name 'release*' -o -name 'gtdbtk_*' \) 2>/dev/null | sort -V)

  # Fallback: scan any nearby directory for the required root structure.
  while IFS= read -r candidate; do
    if validate_gtdb_root "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done < <(find "$base" -maxdepth 4 -type d 2>/dev/null | sort -V)

  return 1
}

repair_gtdb_symlink_if_possible() {
  local link="$DB_DIR/gtdbtk/gtdbtk_data"
  local root=""

  if validate_gtdb_root "$link"; then
    echo "GTDB-Tk root is valid: $(readlink -f "$link" 2>/dev/null || echo "$link")"
    return 0
  fi

  if [[ -e "$link" || -L "$link" ]]; then
    warn "Existing gtdbtk_data path is not a valid GTDB-Tk root: $(readlink -f "$link" 2>/dev/null || echo "$link")"
  fi

  if root="$(find_gtdb_root)"; then
    rm -rf "$link"
    ln -sfn "$root" "$link"
    echo "Repaired GTDB-Tk symlink: $link -> $root"
    return 0
  fi

  return 1
}

make_mash_db() {
  msg "Preparing Mash database"
  mkdir -p "$DB_DIR/mash"
  local out="$DB_DIR/mash/bacseq_refseq.msh"

  if [[ "$SKIP_MASH" -eq 1 ]]; then
    echo "Skipping Mash setup (--skip-mash)."
    rm -f "$out"
    : > "$DB_DIR/mash/MASH_SKIPPED"
    return 0
  fi

  if [[ -n "$MASH_FASTA" ]]; then
    need_cmd mash
    if [[ ! -s "$MASH_FASTA" ]]; then
      echo "ERROR: --mash-fasta not found or empty: $MASH_FASTA" >&2
      exit 1
    fi
    rm -f "$out"
    mash sketch -p "$THREADS" -k 21 -s 10000 -o "$DB_DIR/mash/bacseq_refseq" "$MASH_FASTA"
    rm -f "$DB_DIR/mash/MASH_PLACEHOLDER"
    echo "Mash sketch created: $out"
  elif [[ -s "$out" && "$FORCE" -eq 0 && ! -e "$DB_DIR/mash/MASH_PLACEHOLDER" ]]; then
    echo "Mash sketch already exists: $out"
  else
    warn "No --mash-fasta supplied. Mash pre-check will be disabled until a real sketch is provided."
    rm -f "$out"
    : > "$out"
    : > "$DB_DIR/mash/MASH_PLACEHOLDER"
    cat > "$DB_DIR/mash/README.txt" <<MASH
This is a placeholder. For production species pre-check, build a real Mash sketch:

  bin/bacseq setup-db --db-dir $DB_DIR --profile standard --mash-fasta /path/to/references.fna.gz --config config/config.yaml

or build manually:

  mash sketch -p 16 -k 21 -s 10000 -o $DB_DIR/mash/bacseq_refseq /path/to/references.fna.gz
MASH
  fi
}

setup_taxdump() {
  msg "Preparing NCBI taxdump"
  mkdir -p "$DB_DIR/taxdump"
  local archive="$DB_DIR/taxdump/taxdump.tar.gz"

  if [[ -s "$DB_DIR/taxdump/names.dmp" && -s "$DB_DIR/taxdump/nodes.dmp" && "$FORCE" -eq 0 ]]; then
    echo "NCBI taxdump already exists."
    return 0
  fi

  if [[ -s "$archive" ]]; then
    if valid_gzip "$archive"; then
      echo "Existing taxdump archive is valid: $archive"
    else
      warn "Existing taxdump archive is corrupt. Removing and re-downloading: $archive"
      rm -f "$archive" "$archive.aria2"
    fi
  fi

  safe_download "https://ftp.ncbi.nlm.nih.gov/pub/taxonomy/taxdump.tar.gz" "$archive"
  if ! valid_gzip "$archive"; then
    warn "Downloaded taxdump archive failed gzip test. Retrying from scratch."
    rm -f "$archive" "$archive.aria2"
    safe_download "https://ftp.ncbi.nlm.nih.gov/pub/taxonomy/taxdump.tar.gz" "$archive"
    valid_gzip "$archive" || { echo "ERROR: taxdump archive remains invalid." >&2; exit 1; }
  fi
  tar -xzf "$archive" -C "$DB_DIR/taxdump"
  [[ -s "$DB_DIR/taxdump/names.dmp" && -s "$DB_DIR/taxdump/nodes.dmp" ]] || { echo "ERROR: taxdump extraction did not create names.dmp/nodes.dmp" >&2; exit 1; }
}

setup_gtdbtk() {
  msg "Preparing GTDB-Tk database"
  mkdir -p "$DB_DIR/gtdbtk"

  if [[ "$SKIP_GTDBTK" -eq 1 ]]; then
    echo "Skipping GTDB-Tk setup (--skip-gtdbtk)."
    mkdir -p "$DB_DIR/gtdbtk"
    return 0
  fi

  if [[ "$FORCE" -eq 0 ]]; then
    if repair_gtdb_symlink_if_possible; then
      echo "GTDB-Tk database is ready."
      echo "GTDBTK_DATA_PATH=$DB_DIR/gtdbtk/gtdbtk_data" > "$DB_DIR/gtdbtk/activate_gtdbtk.env"
      return 0
    fi
  fi

  local archive="$DB_DIR/gtdbtk/gtdbtk_data.tar.gz"

  if [[ -s "$archive" ]]; then
    if valid_gzip "$archive"; then
      echo "Existing GTDB-Tk archive is valid: $archive"
    else
      warn "Existing GTDB-Tk archive is corrupt. Removing and re-downloading: $archive"
      rm -f "$archive" "$archive.aria2"
    fi
  fi

  [[ -s "$archive" ]] || safe_download "$GTDB_URL" "$archive"
  if ! valid_gzip "$archive"; then
    warn "Downloaded GTDB-Tk archive failed gzip test. Retrying from scratch."
    rm -f "$archive" "$archive.aria2"
    safe_download "$GTDB_URL" "$archive"
    valid_gzip "$archive" || { echo "ERROR: GTDB-Tk archive remains invalid." >&2; exit 1; }
  fi

  rm -rf "$DB_DIR/gtdbtk/extracted.tmp"
  mkdir -p "$DB_DIR/gtdbtk/extracted.tmp"
  tar -xzf "$archive" -C "$DB_DIR/gtdbtk/extracted.tmp"

  rm -rf "$DB_DIR/gtdbtk/extracted"
  mv "$DB_DIR/gtdbtk/extracted.tmp" "$DB_DIR/gtdbtk/extracted"

  local root=""
  root="$(find_gtdb_root)" || { echo "ERROR: could not find a valid GTDB-Tk release root after extraction." >&2; exit 1; }
  rm -rf "$DB_DIR/gtdbtk/gtdbtk_data"
  ln -sfn "$root" "$DB_DIR/gtdbtk/gtdbtk_data"
  validate_gtdb_root "$DB_DIR/gtdbtk/gtdbtk_data" || { echo "ERROR: repaired GTDB-Tk link is invalid." >&2; exit 1; }

  echo "GTDBTK_DATA_PATH=$DB_DIR/gtdbtk/gtdbtk_data" > "$DB_DIR/gtdbtk/activate_gtdbtk.env"
  echo "GTDB-Tk root: $(readlink -f "$DB_DIR/gtdbtk/gtdbtk_data")"
}

setup_kraken2() {
  msg "Preparing Kraken2 database ($KRAKEN_MODE)"
  mkdir -p "$DB_DIR/kraken2"
  local target="$DB_DIR/kraken2/$KRAKEN_MODE"

  if [[ "$SKIP_KRAKEN" -eq 1 ]]; then
    echo "Skipping Kraken2 setup (--skip-kraken)."
    mkdir -p "$target"
    return 0
  fi

  if [[ -s "$target/hash.k2d" && "$FORCE" -eq 0 ]]; then
    echo "Kraken2 database already exists: $target"
    return 0
  fi

  need_cmd kraken2-build
  rm -rf "$target.tmp"
  mkdir -p "$target.tmp"

  if [[ "$KRAKEN_MODE" == "standard" ]]; then
    kraken2-build --standard --threads "$THREADS" --db "$target.tmp"
  else
    kraken2-build --download-taxonomy --threads "$THREADS" --db "$target.tmp"
    for lib in archaea bacteria viral plasmid fungi protozoa; do
      kraken2-build --download-library "$lib" --threads "$THREADS" --db "$target.tmp" || warn "Kraken2 optional library failed: $lib"
    done
    kraken2-build --build --threads "$THREADS" --db "$target.tmp"
  fi
  kraken2-build --clean --db "$target.tmp" || true
  [[ -s "$target.tmp/hash.k2d" ]] || { echo "ERROR: Kraken2 build did not create hash.k2d" >&2; exit 1; }
  rm -rf "$target"
  mv "$target.tmp" "$target"
}

setup_amrfinder() {
  msg "Preparing AMRFinderPlus database"
  mkdir -p "$DB_DIR/amrfinderplus"
  if has_cmd amrfinder_update; then
    amrfinder_update --database "$DB_DIR/amrfinderplus" || warn "amrfinder_update failed. AMRFinderPlus may use default DB."
  else
    warn "amrfinder_update not found. This is okay if AMRFinderPlus runs through a separate Snakemake conda environment."
  fi
}

setup_full_extra() {
  msg "Preparing optional full-profile folders/databases"
  mkdir -p "$DB_DIR/eggnog" "$DB_DIR/dbcan" "$DB_DIR/phastest" "$DB_DIR/vfdb" "$DB_DIR/plasmidfinder_db"

  if has_cmd download_eggnog_data.py; then
    download_eggnog_data.py --data_dir "$DB_DIR/eggnog" -y || warn "eggNOG database download failed."
  else
    echo "eggNOG downloader not found; leaving folder for manual setup: $DB_DIR/eggnog"
  fi

  if has_cmd run_dbcan; then
    run_dbcan database --db_dir "$DB_DIR/dbcan" || warn "dbCAN database download failed."
  else
    echo "run_dbcan not found; leaving folder for manual setup: $DB_DIR/dbcan"
  fi

  cat > "$DB_DIR/phastest/README.txt" <<PHASTEST
PHASTEST/PHASTER local database is optional. BacSeq2 can use Phigaro/geNomad locally for prophage screening.
Place local PHASTEST/PHASTER database files here only if your deployment uses them.
PHASTEST
}

write_env_hint() {
  cat > "$DB_DIR/activate_bacseq_db.sh" <<ENV
# Source this before running BacSeq2 when databases are stored outside Home.
export BACSEQ_DB="$DB_DIR"
export GTDBTK_DATA_PATH="$DB_DIR/gtdbtk/gtdbtk_data"
export AMRFINDER_DB="$DB_DIR/amrfinderplus"
export MOB_SUITE_DB="$DB_DIR/mob_suite"
ENV
  echo "Wrote environment helper: $DB_DIR/activate_bacseq_db.sh"
}

update_config() {
  msg "Updating BacSeq2 config"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  python3 "$script_dir/update_config_paths.py" --config "$CONFIG" --db-dir "$DB_DIR" --profile "$PROFILE"
}

main() {
  msg "BacSeq2 core database setup started"
  echo "Database directory : $DB_DIR"
  echo "Profile            : $PROFILE"
  echo "Threads            : $THREADS"
  echo "Config             : $CONFIG"
  echo "Log                : $LOG_FILE"

  need_cmd python3
  need_cmd tar
  need_cmd gzip

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

  msg "BacSeq2 core database setup finished"
  echo "Next:"
  echo "  source $DB_DIR/activate_bacseq_db.sh"
  echo "  bin/bacseq setup-amr-mge-db --db-dir $DB_DIR --threads $THREADS --config $CONFIG"
}

main "$@"
