#!/usr/bin/env bash
set -Eeuo pipefail

# BacSeq2 AMR/VFDB/plasmid/MGE/prophage database setup helper
# This script is intentionally best-effort because some databases require
# manual download, registration, or database-specific license acceptance.

DB_DIR="$HOME/bacseq_db"
THREADS=8
CONFIG="config/config.yaml"
FORCE=0
SKIP_OPTIONAL=0

usage() {
  cat <<USAGE
BacSeq2 AMR/MGE database setup

Usage:
  bash scripts/setup_amr_mge_databases.sh [options]

Options:
  --db-dir DIR      Database directory [default: ~/bacseq_db]
  --threads N      Threads [default: 8]
  --config FILE    Config file to update [default: config/config.yaml]
  --force          Re-download/rebuild when possible
  --skip-optional  Skip tools/databases that are not installed
  -h, --help       Show help

Example:
  bash scripts/setup_amr_mge_databases.sh \
    --db-dir /media/mecob/komwit/BacSeq_DB \
    --threads 16 \
    --config config/config.yaml
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db-dir) DB_DIR="$2"; shift 2 ;;
    --threads) THREADS="$2"; shift 2 ;;
    --config) CONFIG="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --skip-optional) SKIP_OPTIONAL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

DB_DIR="$(python3 - <<PY
from pathlib import Path
print(Path('$DB_DIR').expanduser().resolve())
PY
)"
mkdir -p "$DB_DIR" "$DB_DIR/logs" "$(dirname "$CONFIG")"
LOG="$DB_DIR/logs/setup_amr_mge_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
trap 'echo "ERROR at line $LINENO. See log: '$LOG'" >&2' ERR

msg() { echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }
warn() { echo "WARNING: $*" >&2; }

safe_download() {
  local url="$1"
  local out="$2"
  mkdir -p "$(dirname "$out")"
  if [[ -s "$out" && "$FORCE" -eq 0 ]]; then
    echo "Found existing: $out"
    return 0
  fi
  if has_cmd aria2c; then
    aria2c -x 8 -s 8 -c -o "$(basename "$out")" -d "$(dirname "$out")" "$url"
  elif has_cmd wget; then
    wget -c "$url" -O "$out"
  elif has_cmd curl; then
    curl -L -C - "$url" -o "$out"
  else
    warn "Need aria2c, wget, or curl to download $url"
    return 1
  fi
}

msg "BacSeq2 AMR/MGE database setup started"
echo "Database directory : $DB_DIR"
echo "Threads            : $THREADS"
echo "Config             : $CONFIG"
echo "Log                : $LOG"

mkdir -p \
  "$DB_DIR/amrfinderplus" \
  "$DB_DIR/card_rgi" \
  "$DB_DIR/resfinder_db" \
  "$DB_DIR/pointfinder_db" \
  "$DB_DIR/vfdb" \
  "$DB_DIR/mob_suite" \
  "$DB_DIR/plasmidfinder_db" \
  "$DB_DIR/mobileelementfinder" \
  "$DB_DIR/phigaro" \
  "$DB_DIR/genomad"

# AMRFinderPlus
msg "AMRFinderPlus database"
if has_cmd amrfinder_update; then
  amrfinder_update --database "$DB_DIR/amrfinderplus" || warn "amrfinder_update failed; AMRFinderPlus may use its default DB."
else
  warn "amrfinder_update not found. Install ncbi-amrfinderplus in the AMR/MGE environment."
fi

# CARD/RGI
msg "CARD/RGI database"
if has_cmd rgi; then
  if rgi auto_load --help >/dev/null 2>&1; then
    rgi auto_load --local || warn "rgi auto_load failed. CARD may require manual download."
  else
    cat > "$DB_DIR/card_rgi/README.txt" <<CARD
RGI is installed, but automatic CARD loading is not available in this version.
Download CARD data from the official CARD website and run, for example:

  rgi load --card_json /path/to/card.json --local

Then re-run BacSeq2.
CARD
  fi
else
  warn "rgi not found. Install rgi or skip CARD/RGI module."
fi

# ResFinder and PointFinder databases
msg "ResFinder and PointFinder databases"
if has_cmd git; then
  if [[ ! -d "$DB_DIR/resfinder_db/.git" || "$FORCE" -eq 1 ]]; then
    rm -rf "$DB_DIR/resfinder_db"
    git clone https://bitbucket.org/genomicepidemiology/resfinder_db.git "$DB_DIR/resfinder_db" || warn "Could not clone ResFinder DB."
  else
    (cd "$DB_DIR/resfinder_db" && git pull --ff-only) || true
  fi
  if [[ ! -d "$DB_DIR/pointfinder_db/.git" || "$FORCE" -eq 1 ]]; then
    rm -rf "$DB_DIR/pointfinder_db"
    git clone https://bitbucket.org/genomicepidemiology/pointfinder_db.git "$DB_DIR/pointfinder_db" || warn "Could not clone PointFinder DB."
  else
    (cd "$DB_DIR/pointfinder_db" && git pull --ff-only) || true
  fi
else
  warn "git not found; cannot clone ResFinder/PointFinder databases."
fi

# VFDB
msg "VFDB database"
# VFDB links have historically existed at these locations; if they fail, download manually from VFDB.
if [[ ! -s "$DB_DIR/vfdb/VFDB_setB_pro.fas" || "$FORCE" -eq 1 ]]; then
  safe_download "http://www.mgc.ac.cn/VFs/Down/VFDB_setB_pro.fas.gz" "$DB_DIR/vfdb/VFDB_setB_pro.fas.gz" || warn "VFDB protein download failed."
  [[ -s "$DB_DIR/vfdb/VFDB_setB_pro.fas.gz" ]] && gunzip -kf "$DB_DIR/vfdb/VFDB_setB_pro.fas.gz" || true
fi
if [[ ! -s "$DB_DIR/vfdb/VFDB_setB_nt.fas" || "$FORCE" -eq 1 ]]; then
  safe_download "http://www.mgc.ac.cn/VFs/Down/VFDB_setB_nt.fas.gz" "$DB_DIR/vfdb/VFDB_setB_nt.fas.gz" || warn "VFDB nucleotide download failed."
  [[ -s "$DB_DIR/vfdb/VFDB_setB_nt.fas.gz" ]] && gunzip -kf "$DB_DIR/vfdb/VFDB_setB_nt.fas.gz" || true
fi
if [[ -s "$DB_DIR/vfdb/VFDB_setB_pro.fas" && ( ! -s "$DB_DIR/vfdb/VFDB_setB_pro.dmnd" || "$FORCE" -eq 1 ) ]]; then
  if has_cmd diamond; then
    diamond makedb --in "$DB_DIR/vfdb/VFDB_setB_pro.fas" --db "$DB_DIR/vfdb/VFDB_setB_pro" || warn "DIAMOND VFDB build failed."
  else
    warn "diamond not found; VFDB DIAMOND database was not built."
  fi
fi

# ABRicate setup for VFDB/ResFinder/PlasmidFinder convenience
msg "ABRicate database index setup"
if has_cmd abricate; then
  abricate --setupdb || warn "abricate --setupdb failed."
  abricate --list || true
else
  warn "abricate not found. VFDB/PlasmidFinder via ABRicate will be unavailable."
fi

# MOB-suite
msg "MOB-suite database"
if has_cmd mob_init; then
  mob_init -d "$DB_DIR/mob_suite" || warn "mob_init failed."
else
  warn "mob_init not found. Install mob_suite."
fi

# PlasmidFinder DB note
msg "PlasmidFinder database"
cat > "$DB_DIR/plasmidfinder_db/README.txt" <<PLASMID
Place PlasmidFinder database files here, or use ABRicate's plasmidfinder database.
If the plasmidfinder package provides a download-db.sh command in your environment,
run it from this directory.
PLASMID
if has_cmd download-db.sh; then
  (cd "$DB_DIR/plasmidfinder_db" && download-db.sh) || warn "download-db.sh failed."
fi

# MobileElementFinder
msg "MobileElementFinder / MEFinder"
cat > "$DB_DIR/mobileelementfinder/README.txt" <<MEFINDER
MobileElementFinder is usually installed as a Python package and run with:

  mefinder find --contig assembly.fasta output_name

If your version requires a separate database, place it in this folder.
MEFINDER

# Phigaro
msg "Phigaro"
cat > "$DB_DIR/phigaro/README.txt" <<PHIGARO
Phigaro is usually installed with its required HMM resources.
Test with:

  phigaro --help

Run example:

  phigaro -f assembly.fasta -o sample_phigaro -p --not-open
PHIGARO

# geNomad optional database
msg "geNomad database"
if has_cmd genomad; then
  genomad download-database "$DB_DIR/genomad" || warn "geNomad database download failed."
else
  warn "genomad not found. Optional geNomad module will be unavailable."
fi

# Write environment helper
cat > "$DB_DIR/activate_bacseq_db.sh" <<ENV
# Source this before running BacSeq2 when databases are outside Home.
export BACSEQ_DB="$DB_DIR"
export GTDBTK_DATA_PATH="$DB_DIR/gtdbtk/gtdbtk_data"
export AMRFINDER_DB="$DB_DIR/amrfinderplus"
export MOB_SUITE_DB="$DB_DIR/mob_suite"
ENV

# Update config paths using existing helper when available
msg "Updating config paths"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/update_config_paths.py" ]]; then
  python3 "$SCRIPT_DIR/update_config_paths.py" --config "$CONFIG" --db-dir "$DB_DIR" --profile full
else
  warn "update_config_paths.py not found; config not updated automatically."
fi

msg "Finished AMR/MGE setup"
echo "Next:"
echo "  source $DB_DIR/activate_bacseq_db.sh"
echo "  bin/bacseq check-db --config $CONFIG"
