#!/usr/bin/env bash
#=============================================================================
# run_pipeline.sh — germline variant-calling pipeline (Week 1, Bash)
#
# Usage:  ./run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]
#=============================================================================

set -euo pipefail

SHEET=${1:?usage: run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]}
OUT=${2:?usage: run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]}
LAST=${3:-publish}
# Load configuration if present (defaults live in the file itself).
CONF="$(dirname "$0")/conf/pipeline.env"
[[ -f "$CONF" ]] && source "$CONF"
log() { printf '%s\n' "$*" >&2; }

STAGES=(validate qc_raw trim align postprocess quantify merge analyze qc_report publish)

#-----------------------------------------------------------------------------
# Stage 0 — validate. Check the samplesheet and every input BEFORE any compute.
# Golden rule: collect EVERY problem into an array, report them all, fail once.
#-----------------------------------------------------------------------------
stage_validate() {
    local -a problems=()
    local -A seen=()

    while IFS=, read -r sample_id condition replicate library_type r1 r2; do
        [[ -z "$sample_id" ]] && continue

        # --- duplicate sample_id ---
        if [[ -n "${seen[$sample_id]:-}" ]]; then
            problems+=( "duplicate sample_id: ${sample_id}" )
        fi
        seen[$sample_id]=1

        # --- decide which fastqs this sample should have, from library_type ---
        # branch on the COLUMN, never on the sample's name.
        local -a files=( "$r1" )
        if [[ "$library_type" == "paired" ]]; then
            files+=( "$r2" )
        fi

        # --- check each expected fastq ---
        local f
        for f in "${files[@]}"; do
            if [[ -z "$f" ]]; then
                problems+=( "${sample_id}: library_type is '${library_type}' but a fastq path is empty" )
                continue
            fi
            if [[ ! -f "$f" ]]; then
                problems+=( "${sample_id}: file not found: ${f}" )
                continue
            fi
            if [[ ! -s "$f" ]]; then
                problems+=( "${sample_id}: file is empty: ${f}" )
                continue
            fi
            # Integrity: gzip -t catches most corruption, but a tiny truncated
            # fragment can still pass -t. So also fully decompress and require a
            # non-zero line count divisible by 4 (FASTQ = 4 lines per record).
            local nlines
            if ! gzip -t "$f" 2>/dev/null; then
                problems+=( "${sample_id}: truncated or corrupt gzip: ${f}" )
            elif ! nlines=$(gzip -dc "$f" 2>/dev/null | wc -l) \
                 || (( nlines == 0 )) || (( nlines % 4 != 0 )); then
                problems+=( "${sample_id}: not a whole FASTQ (${nlines:-0} lines, not a multiple of 4): ${f}" )
            fi
        done

    done < <(tail -n +2 "$SHEET")

    if (( ${#problems[@]} > 0 )); then
        log "validate: found ${#problems[@]} problem(s):"
        local p
        for p in "${problems[@]}"; do
            log "  - ${p}"
        done
        return 65
    fi

    log "validate: OK"
}

stage_qc_raw()      { log "qc_raw: (not written yet)"; }
stage_qc_raw()      { log "qc_raw: (not written yet)"; }
stage_trim()        { log "trim: (not written yet)"; }
stage_align()       { log "align: (not written yet)"; }
stage_postprocess() { log "postprocess: (not written yet)"; }
stage_quantify()    { log "quantify: (not written yet)"; }
stage_merge()       { log "merge: (not written yet)"; }
stage_analyze()     { log "analyze: (not written yet)"; }
stage_qc_report()   { log "qc_report: (not written yet)"; }
stage_publish()     { log "publish: (not written yet)"; }

n=0
for stage in "${STAGES[@]}"; do
    log "===== stage ${n} : ${stage} ====="
    "stage_${stage}"
    [[ "$stage" == "$LAST" ]] && break
    n=$(( n + 1 ))
done
log "done"
