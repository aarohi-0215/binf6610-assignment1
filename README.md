# BINF6610: Germline Variant-Calling Pipeline (Bash)

A ten-stage bash pipeline that turns raw sequencing reads into a filtered cohort VCF: validate, QC, trim, align (BWA-MEM), postprocess, per-sample calling (GATK HaplotypeCaller), joint genotyping, hard-filtering, MultiQC, and publish. Driven entirely by a samplesheet, with strict validation that fails loudly rather than producing plausible wrong answers.

Run: `./run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]`

## Assignment 2: the same pipeline as a Slurm job array on Explorer

Stages 0–5 run as an eight-task array, one sample per task (`slurm/01_persample.sbatch` → `run_sample.sh`). Stages 6–9 run once, only after every task succeeds (`slurm/02_cohort.sbatch`, gated on `afterok`). Submit from the repo root on Explorer: `bash slurm/submit.sh`. The cluster run's filtered VCF and manifest are in `cluster-run/`; measurements are in `RESOURCES.md`.

## Assignment 3: the pipeline in a container

Last week the software came from the course conda environment; this week it comes from an image built from `containers/Dockerfile`, pinned to the course environment's versions, pushed to Docker Hub and fetched onto Explorer by `slurm/pull.sbatch`. Both job scripts run the pipeline through `apptainer exec --cleanenv --bind`, and the pipeline itself does not change. The run through the image is in `cluster-run-container/`; the base image, the pinned versions and the pushed image's digest are in `IMAGE.md`.

## Assignment 4: the pipeline in Nextflow

The same ten stages, written as Nextflow processes: `main.nf` reads the samplesheet and connects them, one process per stage in `modules/`, the scripts they run in `bin/`, and `nextflow.config` with the profiles `docker` and `explorer`. The weeks 1 to 3 pipeline stays beside it. The laptop run on the smoke dataset is in `smoke-run-nf/`; the Explorer run on the eight samples, submitted by `slurm/nextflow.sbatch`, is in `cluster-run-nf/`.
