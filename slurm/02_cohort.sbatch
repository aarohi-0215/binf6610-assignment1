#!/usr/bin/env bash
#=============================================================================
# 02_cohort.sbatch: stages 6-9, ONCE, after every array task has SUCCEEDED.
# The barrier: submitted with --dependency=afterok on the array, so it only
# runs if all samples finished. Contains NO bioinformatics tool calls.
#=============================================================================
#SBATCH --job-name=vc-cohort
#SBATCH --partition=short
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
#SBATCH --time=00:30:00
#SBATCH --output=logs/cohort_%j.out
#SBATCH --error=logs/cohort_%j.err
#SBATCH --export=NONE

set -euo pipefail

REPO="${SLURM_SUBMIT_DIR}"
cd "${REPO}"
source "${REPO}/slurm/conf/slurm.env"

mkdir -p logs


export THREADS="${SLURM_CPUS_PER_TASK}"

export TMPDIR="/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

# Run the full pipeline: stages 0-5 are already done and their outputs exist in
# OUTDIR, so the cohort stages 6-9 (merge, analyze, qc_report, publish) run over
# all samples. Passing "publish merge" runs stages 6-9 only (FIRST=merge,
# LAST=publish), reusing the per-sample GVCFs the array already produced.
printf 'cohort: joint-genotyping and publishing across all samples\n' >&2
apptainer exec --cleanenv \
    --env THREADS="${THREADS}" \
    --env TMPDIR="${TMPDIR}" \
    --env SLURM_JOB_ID="${SLURM_JOB_ID}" \
    --env SLURM_CPUS_PER_TASK="${SLURM_CPUS_PER_TASK}" \
    --env REF="${REF}" \
    --env REGION="${REGION}" \
    --bind "/courses/BINF6610.202710,${SCRATCH_DIR}" \
    "${SIF}" \
    bash "${REPO}/run_pipeline.sh" "${SAMPLESHEET}" "${OUTDIR}" publish merge
