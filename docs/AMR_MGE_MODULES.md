# BacSeq2 AMR, virulence, plasmid, MGE, and prophage modules

This document summarizes the added BacSeq2 interpretation modules.

## AMR consensus

BacSeq2 should run three complementary AMR tools:

1. **AMRFinderPlus** — curated AMR genes, selected resistance-associated point mutations, and selected stress/virulence genes depending on organism/database support.
2. **CARD/RGI** — CARD ontology-based resistome prediction with strict/perfect/loose hit interpretation.
3. **ResFinder/PointFinder** — acquired AMR genes and supported chromosomal resistance mutations.

Recommended output:

```text
results/amr/<sample>/amrfinderplus.tsv
results/amr/<sample>/card_rgi.txt
results/amr/<sample>/resfinder/
results/amr/<sample>/amr_consensus.tsv
```

## Virulence

Use **VFDB** via ABRicate or BLAST/DIAMOND. Report virulence genes as genomic hits, not confirmed phenotypes.

```text
results/virulence/<sample>/vfdb_abricate.tsv
results/virulence/<sample>/vfdb_diamond.tsv
```

## Plasmid and MGE context

Use **MOB-suite** for plasmid reconstruction/typing, **PlasmidFinder** for replicon detection, **MobileElementFinder** for mobile elements, **IntegronFinder** for integrons, and **ISEScan** for insertion sequences.

Recommended output:

```text
results/plasmids/<sample>/mob_recon/
results/plasmids/<sample>/plasmidfinder/
results/mge/<sample>/mobileelementfinder/
results/mge/<sample>/integronfinder/
results/mge/<sample>/isescan/
```

## Prophage

Use **Phigaro** as the default prophage caller. Add **geNomad** or **PhiSpy** later as optional confirmation modules.

```text
results/prophage/<sample>/phigaro/
results/mge/<sample>/genomad/
```

## Report integration

The HTML report should include:

- AMR consensus table
- AMR tool overlap matrix
- virulence factor table
- plasmid reconstruction summary
- MGE/integron/IS summary
- prophage region summary
- AMR context table showing whether AMR genes occur on plasmid/prophage/integron-associated contigs
