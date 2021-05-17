import glob, os

# Get config
configfile: "config.yaml"

# Declare variables
base = config["run_info"]["base_path"]
run = config["run_info"]["run"]
library = config["run_info"]["library"]
threads = config["run_info"]["threads"]
alpha=config["cnv_calling"]["alpha"]
sdprune=config["cnv_calling"]["sdprune"]
if config['cnv_calling']['single_cell']:
	run_type='single'
else:
	run_type='bulk'
# Full path
full_path = f"{base}{run}/{library}/"

# Scripts
cnv = config["cnv"]
plotting = config["plotting"]

# Binsize(s), readlength and path where to find the binning files
# Path to binning files should be structured in the following way:
# /path/to/binning/files/variable_{binsize}_{readlength}_bwa.
binsize = config["analysis"]["binsize"]
readlength = config["analysis"]["readlength"]
binpath = config["bin_path"]
blacklist = binpath + config["blacklist"]

# Get samples
samples = [os.path.basename(x) for x in glob.glob(full_path + "/bamfiles/" + "*bam")]
samples = [x.replace(".dedup_q30.bam", "") for x in samples]

rule all:
	input:
		expand(full_path + "cnv/{binsize}/plots/profiles/{sample}.png",
		sample = samples, binsize = binsize),
		expand(full_path + "cnv/{binsize}/plots/genomewide/genomewideheatmap.png",
		binsize = binsize)

# Bam to bed
rule makeBed:
	input:
		bam=full_path + "bamfiles/{sample}.dedup_q30.bam"
	output:
		bed=full_path + "bedfiles/{sample}.bed.gz"
	shell:
		"bedtools bamtobed -i {input} | sort -k1,1V -k2,2n -k3,3n | gzip -c > {output}"

# Count reads per bin
rule countReads:
	input:
		bed=full_path + "bedfiles/{sample}.bed.gz",
		bins=binpath + "variable_{binsize}_" + str(readlength) + "_bwa.bed"
	output:
		temp(full_path + "cnv/{binsize}/{sample}_counts.tsv")
	params:
		sample_id="{sample}"
	shell:
		"""
		echo {params} > {output}
		bedtools intersect -nonamecheck -F 0.5 -c -a {input.bins} \
		-b {input.bed} | cut -f4 >> {output}
		"""

# Combine counts
rule combineCounts:
	input:
		expand(full_path + "cnv/{binsize}/{sample}_counts.tsv", binsize = binsize, sample = samples)
	output:
		full_path + "cnv/{binsize}/all-counts.tsv.gz"
	shell:
		"paste {input} | gzip > {output}"

# Copy number calling
rule callCNVs:
	input:
		counts=full_path + "cnv/{binsize}/all-counts.tsv.gz",
		blacklist=blacklist,
		bins=binpath + "variable_{binsize}_" + str(readlength) + "_bwa.bed",
		gc=binpath + "GC_variable_{binsize}_" + str(readlength) + "_bwa"
	output:
		full_path + "cnv/{binsize}/cnv.rds"
	params:
		alpha=alpha,
		sdprune=sdprune,
		run_type=run_type
	threads: 
		threads
	shell:
		"Rscript " + cnv + " --counts {input.counts} --bins {input.bins} "
		"--blacklist {input.blacklist} --gc {input.gc} --alpha {params.alpha} "
		"--prune {params.sdprune} --type {params.run_type} --threads {threads} --output {output}"


# Generate plots
rule generatePlots:
	input:
		full_path + "cnv/{binsize}/cnv.rds"
	output:
		expand(full_path + "cnv/{{binsize}}/plots/profiles/{sample}.png",
			sample = samples),
		full_path + "cnv/{binsize}/plots/genomewide/genomewideheatmap.png"
	params:
		outdir=full_path + "cnv/{binsize}/plots/",
		run_type=run_type
	threads:
		threads
	shell:
		"Rscript " + plotting + " --rds {input} --runtype {params.run_type} "
		"--threads {threads} --outdir {params.outdir}"
