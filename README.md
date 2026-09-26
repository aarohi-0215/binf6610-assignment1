# BINF6610 — Germline Variant-Calling Pipeline (Bash)

A ten-stage bash pipeline that turns raw sequencing reads into a filtered cohort VCF: validate, QC, trim, align (BWA-MEM), postprocess, per-sample calling (GATK HaplotypeCaller), joint genotyping, hard-filtering, MultiQC, and publish. Driven entirely by a samplesheet, with strict validation that fails loudly rather than producing plausible wrong answers.

Run: `./run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]`
