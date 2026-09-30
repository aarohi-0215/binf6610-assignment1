#!/usr/bin/env bash
#=============================================================================
# 01_persample.sbatch: stages 0-5 for ONE sample, as one task of an array.
# Submitted with --array=1-N; task K processes row K of the samplesheet.
# Contains NO bioinformatics tool calls: it decides WHICH sample runs and with
# what resources; run_sample.sh and the stages do the analysis.
#=============================================================================
#SBATCH --job-name=vc-persample
#SBATCH --cpus-per-task=8
#SBATCH --mem=24G
#SBATCH --time=00:30:00
#SBATCH --output=logs/persample_%A_%a.out
#SBATCH --error=logs/persample_%A_%a.err
#SBATCH --export=NONE

set -euo pipefail

# The job must bring its own environment and find its own files, not rely on
# the shell or directory you happened to submit from. sbatch runs a COPY of this
# script from /var/spool/slurmd, so use $SLURM_SUBMIT_DIR to find slurm/conf.
source "${SLURM_SUBMIT_DIR}/conf/slurm.env"

# Slurm will not create the log directory; a job that cannot open its log dies
# with nowhere to say why.
mkdir -p logs


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
    printf 'task %s: no row %s in %s (out-of-range array index), refusing.\n' \
        "${SLURM_ARRAY_TASK_ID}" "$(( SLURM_ARRAY_TASK_ID + 1 ))" "${SAMPLESHEET}" >&2
    exit 65
fi

printf 'task %s -> sample %s\n' "${SLURM_ARRAY_TASK_ID}" "${SAMPLE}" >&2

# Run stages 0-5 for this one sample. run_sample.sh declines the cohort stages.
apptainer exec --cleanenv \
    --env THREADS="${THREADS}" \
    --env TMPDIR="${TMPDIR}" \
    --env SLURM_JOB_ID="${SLURM_JOB_ID}" \
    --env SLURM_CPUS_PER_TASK="${SLURM_CPUS_PER_TASK}" \
    --bind /courses/BINF6610.202710,/scratch/${USER} \
    "${SIF}" \
    bash "${PIPELINE_DIR}/run_sample.sh" "${SAMPLESHEET}" "${RUN_ROOT}" "${SAMPLE}"
