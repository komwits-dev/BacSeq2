# BacSeq2 report update: AMR/MGE sections

Add `report/templates/report_amr_mge_sections.html.j2` into the main Jinja2 report template.

Recommended report sections:

1. AMR consensus summary
2. AMR tool comparison table
3. VFDB virulence factor table
4. MOB-suite plasmid summary
5. MobileElementFinder / IntegronFinder / ISEScan summary
6. Phigaro prophage summary
7. AMR context table: AMR genes on plasmid/prophage/integron-associated contigs

The report should clearly state that AMR results are genomic predictions and should not replace phenotypic AST for clinical interpretation.
