# BacSeq2 pipeline update notes — 2026-05-12

## Main fixes

### 1. GTDB-Tk path repair
Older setup logic could incorrectly set:

```text
gtdbtk_data -> .../release232/metadata
```

This is wrong because GTDB-Tk needs the release root containing:

```text
markers/
metadata/
msa/
pplacer/
skani/
taxonomy/
```

New commands:

```bash
bin/bacseq repair-db --db-dir /path/to/BacSeq_DB --config config/config.yaml
bin/bacseq check-db --config config/config.yaml
```

### 2. Safer interrupted-download handling
The setup script now validates `.tar.gz` archives with `gzip -t` before extraction. Corrupt archives are removed and re-downloaded.

### 3. No aria2 pre-allocation
`aria2c` now uses:

```bash
--file-allocation=none
```

This avoids long apparent `0B` download periods during allocation.

### 4. Mash placeholder handling
If no `--mash-fasta` is supplied, BacSeq2 disables Mash pre-check automatically:

```yaml
run_mash_precheck: false
mash_db: ""
```

To enable Mash:

```bash
bin/bacseq setup-db \
  --db-dir /path/to/BacSeq_DB \
  --profile standard \
  --mash-fasta /path/to/bacterial_references.fna.gz \
  --config config/config.yaml
```

### 5. AMR/MGE/report update
The AMR/MGE module now includes scripts/rules for:

- AMRFinderPlus
- CARD/RGI
- ResFinder/PointFinder
- VFDB through ABRicate and optional DIAMOND
- MOB-suite
- PlasmidFinder through ABRicate
- MobileElementFinder/MEFinder
- IntegronFinder
- ISEScan
- Phigaro
- optional geNomad
- `scripts/summarize_amr_mge.py` for report JSON

## Recommended update in your GitHub repo

```bash
unzip BacSeq2_pipeline_update_20260512.zip
cp -r BacSeq2_pipeline_update_20260512/* /path/to/your/BacSeq2/
cd /path/to/your/BacSeq2
chmod +x bin/bacseq scripts/*.sh scripts/*.py
git add .
git commit -m "Fix database setup and update AMR MGE report modules"
git push
```
