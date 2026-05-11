# BacSeq v2 automatic database setup

BacSeq v2 should not require users to manually edit every database path. Use the automatic setup command instead.

## 1. Create the BacSeq environment

```bash
mamba env create -f envs/bacseq_core.yaml
conda activate bacseq_v2_core
```

For database preparation, install database tools:

```bash
mamba env create -f envs/database_tools.yaml
conda activate bacseq_v2_dbtools
```

## 2. Initialize a config file

```bash
bin/bacseq init
```

This creates:

```text
config/config.yaml
```

Edit only these fields first:

```yaml
input_dir: "fastq"
output_dir: "results"
threads: 16
mode: "short"
```

## 3. Choose a database profile

| Profile | Use case | Databases |
|---|---|---|
| `minimal` | Test/demo only | Mash placeholder, NCBI taxdump |
| `standard` | Routine bacterial WGS | Mash, GTDB-Tk, Kraken2, taxdump, AMRFinderPlus |
| `full` | Publication-level report | Standard + eggNOG, dbCAN, VFDB, PlasmidFinder, PHASTEST folder |

## 4. Standard setup

```bash
bin/bacseq setup-db \
  --db-dir ~/bacseq_db \
  --profile standard \
  --threads 16 \
  --config config/config.yaml
```

The script will:

1. Create the database directory.
2. Download or build selected databases.
3. Write `~/bacseq_db/activate_bacseq_db.sh`.
4. Automatically update `config/config.yaml`.
5. Check whether required database paths exist.

Before running BacSeq, load the database environment variables:

```bash
source ~/bacseq_db/activate_bacseq_db.sh
```

## 5. Minimal test setup

```bash
bin/bacseq setup-db \
  --db-dir ~/bacseq_db \
  --profile minimal \
  --config config/config.yaml
```

Use this only to test the repository layout and Snakemake dry run. It does not prepare the full production databases.

## 6. Full setup

```bash
bin/bacseq setup-db \
  --db-dir ~/bacseq_db \
  --profile full \
  --threads 32 \
  --config config/config.yaml
```

This can require substantial disk space. Use it only when you need functional annotation and publication-level reporting.

## 7. Check databases

```bash
bin/bacseq check-db --config config/config.yaml
```

## 8. Test the workflow

```bash
conda activate bacseq_v2_core
source ~/bacseq_db/activate_bacseq_db.sh

bin/bacseq dry-run \
  --config config/config.yaml \
  --cores 16
```

## 9. Run BacSeq

```bash
bin/bacseq run \
  --config config/config.yaml \
  --cores 16
```

## Recommended design decision

The default decontamination mode should remain:

```yaml
contamination_policy: "review_only"
run_auto_decontam: false
```

This is safer because automated contig removal may accidentally remove plasmids, prophages, or mobile genetic elements. Strict automatic decontamination can be enabled later for well-tested production workflows.
