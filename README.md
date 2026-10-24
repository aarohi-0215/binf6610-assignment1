# BINF6610: Germline Variant-Calling Pipeline (Bash)

A ten-stage bash pipeline that turns raw sequencing reads into a filtered cohort VCF: validate, QC, trim, align (BWA-MEM), postprocess, per-sample calling (GATK HaplotypeCaller), joint genotyping, hard-filtering, MultiQC, and publish. Driven entirely by a samplesheet, with strict validation that fails loudly rather than producing plausible wrong answers.

Run: `./run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]`

This branch is Assignment 6. Each earlier assignment is on its own branch: `master` (Assignment 1), `week2` (Slurm), `week3` (containers), `week4` (Nextflow) and `week5` (Snakemake).

## Assignment 6: the pipeline on AWS Batch, both ways

The pipeline ran on AWS Batch with Fargate, on the smoke dataset, from an S3 bucket. Part A, the general way: the week-3 image with the AWS CLI, the pipeline and `aws/batch_run.sh` added (`aws/Dockerfile`), pushed to ECR (`IMAGE.md`), ran the whole pipeline (`run_pipeline.sh`, `lib/`, `stages/`) as one Batch job; its manifest and VCF are in `aws-run/`. Part B: the week-4 Nextflow pipeline (`main.nf`, `modules/`, `bin/`) sent each task to Batch as a job of its own through the `awsbatch` profile in `nextflow.config`; its results are in `aws-run-nf/`. Both runs' variant records match the laptop's run in `smoke-run/`. `teardown-check.txt` shows that everything made in AWS was deleted afterwards.
