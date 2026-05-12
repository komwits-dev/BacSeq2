# BacSeq2 workflow

![BacSeq2 AMR/MGE workflow](assets/bacseq2_amr_mge_workflow.png)

BacSeq2 processes bacterial WGS data through read QC, assembly, species identification, contamination review, annotation, AMR consensus analysis, virulence screening, plasmid/MGE detection, prophage prediction, and interactive HTML reporting.

The updated BacSeq2 design uses a review-first strategy for potentially dangerous automated decisions:

- suspicious contaminant contigs are reported before removal;
- AMR predictions are labelled as genomic determinants, not clinical phenotypes;
- plasmid, MGE, and prophage context is used to prioritize interpretation rather than automatically overcalling transmission risk.
