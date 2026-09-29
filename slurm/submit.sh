#!/usr/bin/env bash
#=============================================================================
# submit.sh: fire the array, then the cohort job gated on the array SUCCEEDING.
# Two sbatch calls and one dependency. Run this from the repo root on Explorer.
#=============================================================================

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO}"
source "${REPO}/slurm/conf/slurm.env"

mkdir -p logs

# How many samples? data rows in the sheet (minus header).
N=$(( $(wc -l < "${SAMPLESHEET}") - 1 ))
printf 'submitting array of %s samples\n' "${N}" >&2

# 1) the per-sample array. Capture the job id so the cohort job can depend on it.
ARRAY_ID=$(sbatch --parsable --array=1-"${N}" slurm/01_persample.sbatch)
printf 'array job: %s\n' "${ARRAY_ID}" >&2

# 2) the cohort job, gated on afterok (not afterany), runs only if EVERY task succeeded.
#    --kill-on-invalid-dep=yes so it cannot linger PENDING on a cluster whose
#    default does not auto-cancel an unsatisfiable dependency.
COHORT_ID=$(sbatch --parsable \
    --dependency=afterok:"${ARRAY_ID}" \
    --kill-on-invalid-dep=yes \
    slurm/02_cohort.sbatch)
printf 'cohort job: %s (afterok:%s)\n' "${COHORT_ID}" "${ARRAY_ID}" >&2

printf 'submitted. watch with:  squeue -u "$USER"\n' >&2
