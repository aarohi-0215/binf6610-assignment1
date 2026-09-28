#!/usr/bin/env bash
#=============================================================================
# 01_persample.sbatch — stages 0-5 for ONE sample, as one task of an array.
# Submitted with --array=1-N; task K processes row K of the samplesheet.
# Contains NO bioinformatics tool calls: it decides WHICH sample runs and with
# what resources; run_sample.sh -> run_pipeline.sh does the analysis.
#=============================================================================
#SBATCH --job-name=vc-persample
#SBATCH --partition=short
#SBATCH --cpus-per-task=8
#SBATCH --mem=12G
#SBATCH --time=02:00:00
#SBATCH --output=logs/persample_%A_%a.out
#SBATCH --error=logs/persample_%A_%a.err
#SBATCH --export=NONE

set -euo pipefail

# The job must bring its own environment and find its own files, not rely on
# the shell or directory you happened to submit from. sbatch runs a COPY of this
# script from /var/spool/slurmd, so use $SLURM_SUBMIT_DIR to find the repo.
REPO="${SLURM_SUBMIT_DIR}"
cd "${REPO}"
source "${REPO}/slurm/conf/slurm.env"

# Slurm will not create the log directory; a job that cannot open its log dies
# with nowhere to say why.
mkdir -p logs

# Bring the analysis tools in (they live in the conda env, not as modules).
module load "${CONDA_MODULE}"
source activate "${CONDA_ENV}"

# Threads come from what Slurm actually gave us, never a number we typed.
export THREADS="${SLURM_CPUS_PER_TASK}"

# Temp space on the local node, removed by a trap (survives cancel/timeout,
# which a plain rm at the bottom would not).
export TMPDIR="/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

# --- pick this task's sample: row N of the sheet is task N (header skipped) ---
SAMPLE=$(awk -F',' -v n="${SLURM_ARRAY_TASK_ID}" 'NR == n + 1 { print $1 }' "${SAMPLESHEET}")

# An array wider than the sheet hands a task an empty sample name; a pipeline
# given no sample would succeed at every stage over nothing and exit 0. Refuse.
if [[ -z "${SAMPLE}" ]]; then
    printf 'task %s: no row %s in %s — out-of-range array index, refusing.\n' \
        "${SLURM_ARRAY_TASK_ID}" "$(( SLURM_ARRAY_TASK_ID + 1 ))" "${SAMPLESHEET}" >&2
    exit 65
fi

printf 'task %s -> sample %s\n' "${SLURM_ARRAY_TASK_ID}" "${SAMPLE}" >&2

# Run stages 0-5 for this one sample. run_sample.sh declines the cohort stages.
bash "${REPO}/run_sample.sh" "${SAMPLESHEET}" "${SAMPLE}" "${OUTDIR}"
