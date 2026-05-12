# BacSeq2 optional AMR/VFDB/plasmid/MGE/prophage Snakemake rules
# Include from the main Snakefile after the final assembly FASTA is standardized.
# Assumption: final assembly path is results/assembly/{sample}/final.fasta

rule amrfinderplus:
    input:
        assembly="results/assembly/{sample}/final.fasta"
    output:
        tsv="results/amr/{sample}/amrfinderplus.tsv"
    params:
        db=lambda wildcards, config: config.get("amrfinder_db", "")
    threads: lambda wildcards, config: int(config.get("threads", 8))
    conda:
        "../envs/amr_mge.yaml"
    shell:
        r"""
        mkdir -p $(dirname {output.tsv})
        amrfinder --nucleotide {input.assembly} --database {params.db} --output {output.tsv} --threads {threads}
        """

rule card_rgi:
    input:
        assembly="results/assembly/{sample}/final.fasta"
    output:
        txt="results/amr/{sample}/card_rgi.txt"
    threads: lambda wildcards, config: int(config.get("threads", 8))
    conda:
        "../envs/amr_mge.yaml"
    shell:
        r"""
        mkdir -p results/amr/{wildcards.sample}
        rgi main --input_sequence {input.assembly} --output_file results/amr/{wildcards.sample}/card_rgi \
          --input_type contig --local --clean --num_threads {threads}
        test -s results/amr/{wildcards.sample}/card_rgi.txt
        """

rule resfinder:
    input:
        assembly="results/assembly/{sample}/final.fasta"
    output:
        directory("results/amr/{sample}/resfinder")
    params:
        db_res=lambda wildcards, config: config.get("resfinder_db", ""),
        species=lambda wildcards, config: config.get("resfinder_species", "Other")
    conda:
        "../envs/amr_mge.yaml"
    shell:
        r"""
        mkdir -p {output}
        run_resfinder.py -ifa {input.assembly} -o {output} -s "{params.species}" -db_res {params.db_res} -acq
        """

rule vfdb_abricate:
    input:
        assembly="results/assembly/{sample}/final.fasta"
    output:
        tsv="results/virulence/{sample}/vfdb_abricate.tsv"
    conda:
        "../envs/amr_mge.yaml"
    shell:
        r"""
        mkdir -p $(dirname {output.tsv})
        abricate --db vfdb {input.assembly} > {output.tsv}
        """

rule mob_recon:
    input:
        assembly="results/assembly/{sample}/final.fasta"
    output:
        directory("results/plasmids/{sample}/mob_recon")
    threads: lambda wildcards, config: int(config.get("threads", 8))
    conda:
        "../envs/amr_mge.yaml"
    shell:
        r"""
        mkdir -p {output}
        mob_recon --infile {input.assembly} --outdir {output} --num_threads {threads}
        """

rule mobileelementfinder:
    input:
        assembly="results/assembly/{sample}/final.fasta"
    output:
        directory("results/mge/{sample}/mobileelementfinder")
    conda:
        "../envs/amr_mge.yaml"
    shell:
        r"""
        mkdir -p results/mge/{wildcards.sample}
        mefinder find --contig {input.assembly} results/mge/{wildcards.sample}/mobileelementfinder
        """

rule integronfinder:
    input:
        assembly="results/assembly/{sample}/final.fasta"
    output:
        directory("results/mge/{sample}/integronfinder")
    threads: lambda wildcards, config: int(config.get("threads", 8))
    conda:
        "../envs/amr_mge.yaml"
    shell:
        r"""
        mkdir -p {output}
        integron_finder {input.assembly} --outdir {output} --cpu {threads}
        """

rule isescan:
    input:
        assembly="results/assembly/{sample}/final.fasta"
    output:
        directory("results/mge/{sample}/isescan")
    threads: lambda wildcards, config: int(config.get("threads", 8))
    conda:
        "../envs/amr_mge.yaml"
    shell:
        r"""
        mkdir -p {output}
        isescan.py --seqfile {input.assembly} --output {output} --nthread {threads}
        """

rule phigaro:
    input:
        assembly="results/assembly/{sample}/final.fasta"
    output:
        directory("results/prophage/{sample}/phigaro")
    conda:
        "../envs/amr_mge.yaml"
    shell:
        r"""
        mkdir -p {output}
        phigaro -f {input.assembly} -o {output}/{wildcards.sample} -p --not-open
        """

rule genomad_optional:
    input:
        assembly="results/assembly/{sample}/final.fasta"
    output:
        directory("results/mge/{sample}/genomad")
    params:
        db=lambda wildcards, config: config.get("genomad_db", "")
    threads: lambda wildcards, config: int(config.get("threads", 8))
    conda:
        "../envs/amr_mge.yaml"
    shell:
        r"""
        mkdir -p {output}
        genomad end-to-end {input.assembly} {output} {params.db} --threads {threads}
        """
