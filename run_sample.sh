#!/usr/bin/env bash
#=============================================================================
# run_sample.sh: the per-sample entry point.
#
# An array task runs ONE sample; run_pipeline.sh runs all of them. Both call
# the SAME stage functions: this wrapper just feeds run_pipeline.sh a
# one-row samplesheet and stops after stage 5 (quantify).
#
# It DECLINES the cohort stages (6-9: merge, analyze, qc_report, publish) on
# purpose: those need every sample, and one array task cannot know whether the
# others have finished. Running merge here would build a cohort from one sample,
# once per task, each overwriting the last.
#
# Usage:  ./run_sample.sh <samplesheet.csv> <sample_id> <outdir>
#=============================================================================

set -euo pipefail

SHEET=${1:?usage: run_sample.sh <samplesheet.csv> <sample_id> <outdir>}
SAMPLE=${2:?usage: run_sample.sh <samplesheet.csv> <sample_id> <outdir>}
OUTDIR=${3:?usage: run_sample.sh <samplesheet.csv> <sample_id> <outdir>}

HERE="$(cd "$(dirname "$0")" && pwd)"

log() { printf '%s\n' "$*" >&2; }

# --- refuse the cohort stages: this entry point is per-sample only ----------
# (named here so the acceptance test can see this script declines 6-9)
# valid single-sample stages are: validate qc_raw trim align postprocess quantify
# cohort stages merge / analyze / qc_report / publish are NOT run here.
case "${4:-}" in
    merge|analyze|qc_report|publish|cohort)
        log "run_sample.sh: refusing cohort stage '${4}'. This entry point runs one"
        log "               sample through stages 0-5 only; cohort stages need all samples."
        exit 64
        ;;
esac

# --- build a one-row samplesheet for just this sample -----------------------
ONEROW="$(mktemp "${TMPDIR:-/tmp}/onerow.XXXXXX.csv")"
trap 'rm -f "${ONEROW}"' EXIT

# header, then the single matching row (exact match on the first column)
head -n 1 "$SHEET" > "$ONEROW"
awk -F',' -v s="$SAMPLE" 'NR>1 && $1==s' "$SHEET" >> "$ONEROW"

# guard: the sample must actually exist in the sheet
rows=$(( $(wc -l < "$ONEROW") - 1 ))
if (( rows < 1 )); then
    log "run_sample.sh: no sample named '${SAMPLE}' in ${SHEET}"
    exit 65
fi

log "run_sample.sh: running stages 0-5 for ${SAMPLE}"

# reuse the exact pipeline, stopping after quantify (stage 5)
bash "${HERE}/run_pipeline.sh" "$ONEROW" "$OUTDIR" quantify