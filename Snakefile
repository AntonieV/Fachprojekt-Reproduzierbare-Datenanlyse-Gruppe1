configfile: "config.yaml"
import os
import pandas as pd

#kallisto: kerne in config file?

samples = pd.read_csv(config["samples"], sep = "\t")

if not os.path.exists("plots"):
    os.makedirs("plots")

if not os.path.exists("clustering_distance.txt"):
    file = open("clustering_distance.txt", "w")
    file.write("canberra")
    file.close()


rule all:
    input:
        "plots/all_plots.pdf"
        

rule kallisto_idx:
    input:
        config["transcripts"]
    conda:
        "envs/kallisto.yaml"
    output:
        config["kallisto_idx"]
    shell:
        "kallisto index -i {output} {input}"

rule kallisto_quant:
    input:
        id = config["kallisto_idx"],
        fq1 = lambda wildcards: samples.loc[samples['sample'] == wildcards.sample]['fq1'],
        fq2 = lambda wildcards: samples.loc[samples['sample'] == wildcards.sample]['fq2']
    conda:
        "envs/kallisto.yaml"
    params:
        "kallisto/{sample}"
    output:
        "kallisto/{sample}/fusion.txt",
        "kallisto/{sample}/abundance.h5"
    shell:
        "kallisto quant --fusion --bootstrap-samples=2 -i {input.id} -o  {params} {input.fq1} {input.fq2}"

rule sleuth:
    input:
        kal_path = expand("kallisto/{sample}/abundance.h5", sample = samples['sample']), #list of Kallisto-paths
        sam_tab = config["samples"]
    conda:
        "envs/sleuth.yaml"
    output:
        "sleuth/significant_transcripts.csv",
        "sleuth/p-values_all_transcripts.csv",
        "sleuth/sleuth_matrix.csv",
        "sleuth/sleuth_object"
    script:
        "r_scripts/sleuth_script.R"

rule gage:
    input:
        pval = "sleuth/p-values_all_transcripts.csv",
        matrix = "sleuth/sleuth_matrix.csv",
        samples = config["samples"]
    conda:
        "envs/gage.yaml"
    output:
        directory("plots/gage")
    script:
        "r_scripts/gage.R"

rule pizzly:
    input:
        transcript = config["transcripts"],
        gtf = config["transcripts_gtf"],
        fusion = "kallisto/{sample}/fusion.txt"
    conda:
        "envs/pizzly.yaml"
    params:
        "kallisto/{sample}",
        "pizzly/{sample}/result"
    output:
        "pizzly/{sample}/result.json"
    shell:
        "pizzly -k 31 --gtf {input.gtf} --cache {params[0]}/indx.cache.txt --align-score 2 --insert-size 400 --fasta {input.transcript} --output {params[1]} {input.fusion}"


######## PIZZLY CSVs ########

rule pizzly_flatten:
    input:
        "pizzly/{sample}/result.json"# ueber alle; expand("pizzly/{sample}/result.json", sample = samples['sample'])
    output:
        "plots/pizzly/{sample}/pizzly_genetable_{sample}.csv"
    shell:
        "python py_scripts/flatten_json.py {input} {output}"

rule pizzly_fragment_length:
    input:
        "kallisto/{sample}/abundance.h5"
    conda:
        "envs/pizzly_fragment_length.yaml"
    output:
        "plots/pizzly/{sample}/pizzly_fragment_length_{sample}.csv"
    shell:
        "python py_scripts/get_fragment_length.py {input[0]} 0.95 {output} "


######## PLOTS ########

rule volcano:
    input:
        pval = "sleuth/p-values_all_transcripts.csv",
        matrix = "sleuth/sleuth_matrix.csv",
        samples = config["samples"]
    conda:
        "envs/volcano.yaml"
    output:
        "plots/volcano.svg"
    script:
        "r_scripts/volcano.R"

rule heatmap:
    input:
        #sig = config["significance_niveau"],
        matrix = "sleuth/sleuth_matrix.csv",
        dist = config["clust_dist"],
        p_all = "sleuth/p-values_all_transcripts.csv"
    params:
        sig = config["significance_niveau"]
    conda:
        "envs/heatmap.yaml"
    output:
        "plots/heatmap.svg"
    script:
        "r_scripts/complexHeatmap.R"

rule pca:
    input:
        "sleuth/sleuth_matrix.csv",
    conda:
        "envs/pca.yaml"
    output:
        "plots/pca.svg"
    script:
        "py_scripts/pca_plot.py"

rule boxen_plot:
    input:
        "sleuth/sleuth_matrix.csv"
    conda:
        "envs/boxen.yaml"
    output:
        "plots/boxen.svg"
    script:
        "py_scripts/boxen_plot.py"

rule p_value_hist:
    input:
        "sleuth/p-values_all_transcripts.csv"  #sleuth-tabelle mit 'pval'-Spalte  
    conda:
        "envs/boxen.yaml"
    output:
        "plots/p-value.svg"
    script:
        "py_scripts/p-value_histogramm.py"

rule strip_plot:
    input:
        "sleuth/p-values_all_transcripts.csv",  #significant_transcripts.csv"  #sleuth-matrix, mit den Spalten target_id, which_units???  
    conda:
        "envs/boxen.yaml"
    output:
        "plots/strip.svg"
    script:
        "py_scripts/strip_plot.py"


######## ALL PLOTS ########

rule svg_pdf:
    input:
        "plots/strip.svg",
        "plots/p-value.svg",
        "plots/boxen.svg",
        "plots/pca.svg",
	    "plots/heatmap.svg",
        "plots/volcano.svg",
        expand("plots/pizzly/{sample}/pizzly_genetable_{sample}.csv", sample = samples['sample']),
        expand("plots/pizzly/{sample}/pizzly_fragment_length_{sample}.csv", sample = samples['sample']),
        plots = directory("plots"),
        cov_pic = "cover_pic.png"
    conda:
        "envs/svg_pdf.yaml"
    output:
        "plots/all_plots.pdf"
    script:
        "r_scripts/svg_to_pdf.R"

