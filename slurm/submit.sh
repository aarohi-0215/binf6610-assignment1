#!/usr/bin/env bash
#=============================================================================
# submit.sh: fire the array, then the cohort job gated on the array SUCCEEDING.
# Two sbatch calls and one dependency.
#=============================================================================

set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "${HERE}"
source conf/slurm.env

mkdir -p logs

# How many samples? data rows in the sheet (minus header).
N=$(awk -F, 'NR > 1 && $1 != ""' "${SAMPLESHEET}" | wc -l)
printf 'submitting array of %s samples\n' "${N}" >&2

# 1) the per-sample array. Capture the job id so the cohort job can depend on it.
ARRAY_ID=$(sbatch --parsable -p "${PARTITION}" -A "${ACCOUNT}" --array=1-"${N}" 01_persample.sbatch)
printf 'array job: %s\n' "${ARRAY_ID}" >&2

# 2) the cohort job, gated on afterok (not afterany), runs only if EVERY task succeeded.
#    --kill-on-invalid-dep=yes so it cannot linger PENDING on a cluster whose
#    default does not auto-cancel an unsatisfiable dependency.
COHORT_ID=$(sbatch --parsable -p "${PARTITION}" -A "${ACCOUNT}" \
    --dependency=afterok:"${ARRAY_ID}" \
    --kill-on-invalid-dep=yes \
    02_cohort.sbatch)
printf 'cohort job: %s (afterok:%s)\n' "${COHORT_ID}" "${ARRAY_ID}" >&2

printf 'submitted. watch with:  squeue -u "$USER"\n' >&2
