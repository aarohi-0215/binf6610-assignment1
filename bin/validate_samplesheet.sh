#!/usr/bin/env bash
set -euo pipefail

SHEET=${1:?usage: validate_samplesheet.sh <samplesheet.csv> <reference.fa>}
REF=$(basename "${2:?usage: validate_samplesheet.sh <samplesheet.csv> <reference.fa>}")

log() { printf '%s\n' "$*" >&2; }

problems=()
declare -A seen=()

header=$(head -1 "$SHEET" | tr -d '\r')
for c in sample_id library_type r1_fastq r2_fastq; do
    [[ ",${header}," == *",${c},"* ]] || problems+=( "samplesheet has no column named ${c}" )
done

if (( ${#problems[@]} == 0 )); then
    while IFS=, read -r id lt r1 r2; do
        if [[ -z "$id" ]]; then
            problems+=( "a row has no sample_id" )
            continue
        fi
        if [[ -n "${seen[$id]:-}" ]]; then
            problems+=( "duplicate sample_id: ${id}" )
        fi
        seen[$id]=1

        files=( "$r1" )
        if [[ "$lt" == "paired" ]]; then
            files+=( "$r2" )
        fi

        for f in "${files[@]}"; do
            if [[ -z "$f" ]]; then
                problems+=( "${id}: library_type is '${lt}' but a fastq path is empty" )
                continue
            fi
            f=$(basename "$f")
            if [[ ! -f "$f" ]]; then
                problems+=( "${id}: file not found: ${f}" )
                continue
            fi
            if [[ ! -s "$f" ]]; then
                problems+=( "${id}: file is empty: ${f}" )
                continue
            fi
            if ! gzip -t "$f" 2>/dev/null; then
                problems+=( "${id}: truncated or corrupt gzip: ${f}" )
            elif ! n=$(gzip -dc "$f" 2>/dev/null | wc -l) || (( n == 0 )) || (( n % 4 != 0 )); then
                problems+=( "${id}: not a whole FASTQ (${n:-0} lines, not a multiple of 4): ${f}" )
            fi
        done
    done < <(awk -F, -v OFS=, '
        { gsub(/\r/, "") }
        NR == 1 { for (i = 1; i <= NF; i++) col[$i] = i; next }
        { print $col["sample_id"], $col["library_type"], $col["r1_fastq"], $col["r2_fastq"] }' "$SHEET")
fi

for f in "$REF" "${REF}.fai" "${REF%.*}.dict" "${REF}.bwt"; do
    [[ -s "$f" ]] || problems+=( "reference file missing: ${f}" )
done

if (( ${#problems[@]} > 0 )); then
    log "validate: found ${#problems[@]} problem(s):"
    for p in "${problems[@]}"; do
        log "  - ${p}"
    done
    exit 65
fi

log "validate: OK, $(awk 'NR > 1 && $0 != ""' "$SHEET" | wc -l | tr -d ' ') samples"
