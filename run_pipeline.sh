#!/usr/bin/env bash
#=============================================================================
# run_pipeline.sh: germline variant-calling pipeline, every sample, stages 0-9.
#
# Usage:  ./run_pipeline.sh <samplesheet.csv> <outdir> [last-stage] [first-stage]
#=============================================================================

set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export RUN_STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

SHEET=${1:?usage: run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]}
OUT=${2:?usage: run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]}
LAST=${3:-publish}
FIRST=${4:-validate}   # first stage to run (default: from the start)
SAMPLE=""

source "${HERE}/lib/common.sh"
setup_dirs
for f in "${HERE}"/stages/*.sh; do source "$f"; done

STAGES=(validate qc_raw trim align postprocess quantify merge analyze qc_report publish)

#=============================================================================
# The driver: run stages in order, stop after the one named in LAST.
#=============================================================================
n=0
started=0
for stage in "${STAGES[@]}"; do
    [[ "$stage" == "$FIRST" ]] && started=1
    if (( started )); then
        log "===== stage ${n} : ${stage} ====="
        "stage_${stage}"
        [[ "$stage" == "$LAST" ]] && break
    fi
    n=$(( n + 1 ))
done
log "done"
