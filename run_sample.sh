#!/usr/bin/env bash
#=============================================================================
# run_sample.sh: the per-sample entry point, stages 0-5 for ONE sample.
#
# An array task runs ONE sample; run_pipeline.sh runs all of them. Both call
# the SAME stage functions, from stages/.
#
# It DECLINES the cohort stages (6-9: merge, analyze, qc_report, publish) on
# purpose: those need every sample, and one array task cannot know whether the
# others have finished. Running merge here would build a cohort from one sample,
# once per task, each overwriting the last.
#
# Usage:  ./run_sample.sh <samplesheet.csv> <outdir> <sample_id> [last-stage]
#=============================================================================

set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

SHEET=${1:?usage: run_sample.sh <samplesheet.csv> <outdir> <sample_id> [last-stage]}
OUT=${2:?usage: run_sample.sh <samplesheet.csv> <outdir> <sample_id> [last-stage]}
SAMPLE=${3:?usage: run_sample.sh <samplesheet.csv> <outdir> <sample_id> [last-stage]}
LAST=${4:-quantify}

source "${HERE}/lib/common.sh"

case "${LAST}" in
    merge|analyze|qc_report|publish|cohort)
        die "run_sample.sh: refusing cohort stage '${LAST}'. This entry point runs one sample through stages 0-5 only; cohort stages need all samples." ;;
    validate|qc_raw|trim|align|postprocess|quantify) ;;
    *) die "run_sample.sh: unknown stage '${LAST}'" ;;
esac

[[ -n "$(rows "$SHEET" "$SAMPLE")" ]] || die "run_sample.sh: no sample named '${SAMPLE}' in ${SHEET}"

setup_dirs
for f in "${HERE}"/stages/*.sh; do source "$f"; done

log "run_sample.sh: running stages 0-5 for ${SAMPLE}"

PER_SAMPLE=(validate qc_raw trim align postprocess quantify)
n=0
for stage in "${PER_SAMPLE[@]}"; do
    log "===== stage ${n} : ${stage} ====="
    "stage_${stage}"
    [[ "$stage" == "$LAST" ]] && break
    n=$(( n + 1 ))
done
log "done"
