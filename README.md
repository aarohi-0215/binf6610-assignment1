# BINF6610: Germline Variant-Calling Pipeline (Bash)

A ten-stage bash pipeline that turns raw sequencing reads into a filtered cohort VCF: validate, QC, trim, align (BWA-MEM), postprocess, per-sample calling (GATK HaplotypeCaller), joint genotyping, hard-filtering, MultiQC, and publish. Driven entirely by a samplesheet, with strict validation that fails loudly rather than producing plausible wrong answers.

Run: `./run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]`

## Assignment 8: CI and CD

CI (`.github/workflows/ci.yml`) runs on every push to `main` and every pull request: ShellCheck over the pipeline's scripts, then the whole pipeline on the smoke dataset in `tests/smoke/`, inside the image built from `containers/Dockerfile`. It checks the manifest against the course's contract (`tools/check_manifest.py`), that the manifest names the commit tested, and that the variant records match `aws-run/`, made by the same tools.

CD (`.github/workflows/cd.yml`) runs on every version tag: it builds `aws/Dockerfile`, pushes it to ECR, registers `aws/job-definition.json` with that image by its digest, and runs the smoke dataset on AWS Batch. The results of release `v1.0.0` are in `cd-run/`. `teardown-check.txt` shows that everything made in AWS was deleted afterwards.

Each earlier assignment is on its own branch: `master` (Assignment 1), `week2` (Slurm), `week3` (containers), `week4` (Nextflow), `week5` (Snakemake) and `week6` (AWS Batch).
