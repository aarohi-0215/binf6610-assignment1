# BINF6610: Germline Variant-Calling Pipeline (Bash)

A ten-stage bash pipeline that turns raw sequencing reads into a filtered cohort VCF: validate, QC, trim, align (BWA-MEM), postprocess, per-sample calling (GATK HaplotypeCaller), joint genotyping, hard-filtering, MultiQC, and publish. Driven entirely by a samplesheet, with strict validation that fails loudly rather than producing plausible wrong answers.

Run: `./run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]`

## Assignment 2: the same pipeline as a Slurm job array on Explorer

Stages 0–5 run as an eight-task array, one sample per task (`slurm/01_persample.sbatch` → `run_sample.sh`). Stages 6–9 run once, only after every task succeeds (`slurm/02_cohort.sbatch`, gated on `afterok`). Submit from the repo root on Explorer: `bash slurm/submit.sh`. The cluster run's filtered VCF and manifest are in `cluster-run/`; measurements are in `RESOURCES.md`.
