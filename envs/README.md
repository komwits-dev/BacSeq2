# BacSeq2 conda environments

- `bacseq_core.yaml`: main launcher, Snakemake, Python reporting tools.
- `database_tools.yaml`: database setup helpers.
- `amr_mge.yaml`: optional AMR, virulence, plasmid, MGE, and prophage module tools.

Recommended installation:

```bash
mamba env create -f envs/bacseq_core.yaml
mamba env create -f envs/amr_mge.yaml
```

If `amr_mge.yaml` fails because of optional packages, create the fallback environment from the README and install remaining tools separately.
