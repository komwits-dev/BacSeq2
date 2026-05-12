# BacSeq2 AMR/VFDB/plasmid/MGE/prophage Snakemake rules
# Include this file from the main Snakefile after the final assembly FASTA is standardized.
# Expected final assembly path:
#   {output_dir}/assembly/{sample}/final.fasta

OUTDIR = config.get("output_dir", "results")
ASSEMBLY_FINAL = OUTDIR + "/assembly/{sample}/final.fasta"

rule amrfinderplus:
    input:
        assembly=ASSEMBLY_FINAL
    output:
        tsv=OUTDIR + "/amr/{sample}/amrfinderplus.tsv"
    params:
        db=lambda wc: config.get("amrfinder_db", "")
    threads: lambda wc: int(config.get("threads", 8))
    conda:
        "../envs/amr_mge.yaml"
    shell:
        r"""
        mkdir -p $(dirname {output.tsv})
        if [ -n "{params.db}" ] && [ -d "{params.db}" ]; then
          amrfinder --nucleotide {input.assembly} --database {params.db} --output {output.tsv} --threads {threads}
        else
          amrfinder --nucleotide {input.assembly} --output {output.tsv} --threads {threads}
        fi
        """

rule card_rgi:
    input:
        assembly=ASSEMBLY_FINAL
    output:
        txt=OUTDIR + "/amr/{sample}/card_rgi.txt"
    threads: lambda wc: int(config.get("threads", 8))
    conda:
        "../envs/amr_mge.yaml"
    shell:
        r"""
        mkdir -p {OUTDIR}/amr/{wildcards.sample}
        rgi main --input_sequence {input.assembly} \
          --output_file {OUTDIR}/amr/{wildcards.sample}/card_rgi \
          --input_type contig --local --clean --num_threads {threads}
        test -s {output.txt}
        """

rule resfinder:
    input:
        assembly=ASSEMBLY_FINAL
    output:
        directory(OUTDIR + "/amr/{sample}/resfinder")
    params:
        db_res=lambda wc: config.get("resfinder_db", ""),
        db_point=lambda wc: config.get("pointfinder_db", ""),
        species=lambda wc: config.get("resfinder_species", "Other")
    conda:
        "../envs/amr_mge.yaml"
    shell:
        r"""
        mkdir -p {output}
        run_resfinder.py -ifa {input.assembly} -o {output} -s "{params.species}" -db_res {params.db_res} -acq
        """

rule vfdb_abricate:
    input:
        assembly=ASSEMBLY_FINAL
    output:
        tsv=OUTDIR + "/virulence/{sample}/vfdb_abricate.tsv"
    conda:
        "../envs/amr_mge.yaml"
    shell:
        r"""
        mkdir -p $(dirname {output.tsv})
        abricate --db vfdb {input.assembly} > {output.tsv}
        """

rule vfdb_diamond:
    input:
        assembly=ASSEMBLY_FINAL
    output:
        tsv=OUTDIR + "/virulence/{sample}/vfdb_diamond.tsv"
    params:
        db=lambda wc: config.get("vfdb_diamond_db", ""),
        identity=lambda wc: config.get("vfdb_min_identity", 80)
    threads: lambda wc: int(config.get("threads", 8))
    conda:
        "../envs/amr_mge.yaml"
    shell:
        r"""
        mkdir -p $(dirname {output.tsv})
        if [ -s "{params.db}" ]; then
          prodigal -i {input.assembly} -a {OUTDIR}/virulence/{wildcards.sample}/proteins.faa -q
          diamond blastp --query {OUTDIR}/virulence/{wildcards.sample}/proteins.faa \
            --db {params.db} --out {output.tsv} --outfmt 6 \
            --id {params.identity} --threads {threads}
        else
          echo -e "query\tsubject\tpident\tlength\tmismatch\tgapopen\tqstart\tqend\tsstart\tsend\tevalue\tbitscore" > {output.tsv}
        fi
        """

rule mob_recon:
    input:
        assembly=ASSEMBLY_FINAL
    output:
        directory(OUTDIR + "/plasmids/{sample}/mob_recon")
    threads: lambda wc: int(config.get("threads", 8))
    conda:
        "../envs/amr_mge.yaml"
    shell:
        r"""
        mkdir -p {output}
        mob_recon --infile {input.assembly} --outdir {output} --num_threads {threads}
        """

rule plasmidfinder_abricate:
    input:
        assembly=ASSEMBLY_FINAL
    output:
        tsv=OUTDIR + "/plasmids/{sample}/plasmidfinder_abricate.tsv"
    conda:
        "../envs/amr_mge.yaml"
    shell:
        r"""
        mkdir -p $(dirname {output.tsv})
        abricate --db plasmidfinder {input.assembly} > {output.tsv}
        """

rule mobileelementfinder:
    input:
        assembly=ASSEMBLY_FINAL
    output:
        directory(OUTDIR + "/mge/{sample}/mobileelementfinder")
    conda:
        "../envs/amr_mge.yaml"
    shell:
        r"""
        mkdir -p {OUTDIR}/mge/{wildcards.sample}
        mefinder find --contig {input.assembly} {OUTDIR}/mge/{wildcards.sample}/mobileelementfinder
        """

rule integronfinder:
    input:
        assembly=ASSEMBLY_FINAL
    output:
        directory(OUTDIR + "/mge/{sample}/integronfinder")
    threads: lambda wc: int(config.get("threads", 8))
    conda:
        "../envs/amr_mge.yaml"
    shell:
        r"""
        mkdir -p {output}
        integron_finder {input.assembly} --outdir {output} --cpu {threads}
        """

rule isescan:
    input:
        assembly=ASSEMBLY_FINAL
    output:
        directory(OUTDIR + "/mge/{sample}/isescan")
    threads: lambda wc: int(config.get("threads", 8))
    conda:
        "../envs/amr_mge.yaml"
    shell:
        r"""
        mkdir -p {output}
        isescan.py --seqfile {input.assembly} --output {output} --nthread {threads}
        """

rule phigaro:
    input:
        assembly=ASSEMBLY_FINAL
    output:
        directory(OUTDIR + "/prophage/{sample}/phigaro")
    conda:
        "../envs/amr_mge.yaml"
    shell:
        r"""
        mkdir -p {output}
        phigaro -f {input.assembly} -o {output}/{wildcards.sample} -p --not-open
        """

rule genomad_optional:
    input:
        assembly=ASSEMBLY_FINAL
    output:
        directory(OUTDIR + "/mge/{sample}/genomad")
    params:
        db=lambda wc: config.get("genomad_db", "")
    threads: lambda wc: int(config.get("threads", 8))
    conda:
        "../envs/amr_mge.yaml"
    shell:
        r"""
        mkdir -p {output}
        genomad end-to-end {input.assembly} {output} {params.db} --threads {threads}
        """

rule summarize_amr_mge:
    input:
        amrfinder=OUTDIR + "/amr/{sample}/amrfinderplus.tsv",
        card=OUTDIR + "/amr/{sample}/card_rgi.txt",
        vfdb=OUTDIR + "/virulence/{sample}/vfdb_abricate.tsv",
        mob=OUTDIR + "/plasmids/{sample}/mob_recon",
        mefinder=OUTDIR + "/mge/{sample}/mobileelementfinder",
        phigaro=OUTDIR + "/prophage/{sample}/phigaro"
    output:
        json=OUTDIR + "/report/{sample}/amr_mge_summary.json"
    conda:
        "../envs/amr_mge.yaml"
    shell:
        r"""
        mkdir -p $(dirname {output.json})
        python scripts/summarize_amr_mge.py \
          --sample {wildcards.sample} \
          --out {output.json} \
          --amrfinder {input.amrfinder} \
          --card {input.card} \
          --vfdb {input.vfdb} \
          --mob {input.mob} \
          --mefinder {input.mefinder} \
          --phigaro {input.phigaro}
        """
