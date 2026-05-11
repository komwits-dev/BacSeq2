# BacSeq v2 workflow

<p align="center">
  <img src="assets/bacseq_v2_workflow.png" alt="BacSeq v2 workflow" width="100%">
</p>

BacSeq v2 uses a species-first, contamination-aware, report-centered bacterial WGS workflow.

## Main logic

1. **Input reads** are processed by read QC and trimming.
2. Reads are assembled using the selected sequencing mode.
3. Species identification is performed using Mash and GTDB-Tk.
4. Contamination is screened using taxonomy, coverage, GC content, and contig-level evidence.
5. Contamination is reported first; removal is optional and strict.
6. Annotation, AMR, MLST, plasmid, virulence, and MGE modules are run on the selected final assembly.
7. All outputs are integrated into an interactive HTML report.

## Default contamination behavior

```yaml
contamination_policy: "review_only"
run_auto_decontam: false
```
