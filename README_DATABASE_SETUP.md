# BacSeq v2 database automation module

This folder adds GitHub-ready automatic setup for BacSeq v2 databases.

## Files

```text
bin/bacseq                         # user-facing launcher
scripts/setup_databases.sh          # automatic database download/build
scripts/update_config_paths.py      # safely updates config/config.yaml
scripts/check_databases.py          # checks configured database paths
config/config.template.yaml         # config template with managed DB paths
envs/bacseq_core.yaml               # core Snakemake environment
envs/database_tools.yaml            # tools needed to build/download databases
docs/INSTALL_DATABASES.md           # README-ready install instructions
```

## Quick start

```bash
mamba env create -f envs/bacseq_core.yaml
conda activate bacseq_v2_core

bin/bacseq init

bin/bacseq setup-db \
  --db-dir ~/bacseq_db \
  --profile standard \
  --threads 16 \
  --config config/config.yaml

source ~/bacseq_db/activate_bacseq_db.sh

bin/bacseq dry-run --config config/config.yaml --cores 16
bin/bacseq run --config config/config.yaml --cores 16
```

## For first GitHub release

Recommended user-facing database profiles:

1. `minimal` for a quick demo/test.
2. `standard` for normal bacterial WGS reports.
3. `full` for publication-level annotation.

Do not make full database setup mandatory on first install because it is large and slow.
