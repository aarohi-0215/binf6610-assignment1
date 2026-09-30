set -euo pipefail

#=============================================================================
# Stage 0: validate. Check the samplesheet and every input BEFORE any compute.
# Golden rule: collect EVERY problem into an array, report them all, fail once.
#=============================================================================
stage_validate() {
    local -a problems=()
    local -A seen=()

    rows "$SHEET" > /dev/null || return 65

    while IFS=, read -r sample_id condition replicate library_type r1 r2; do
        [[ -z "$sample_id" ]] && continue

        # --- duplicate sample_id ---
        if [[ -n "${seen[$sample_id]:-}" ]]; then
            problems+=( "duplicate sample_id: ${sample_id}" )
        fi
        seen[$sample_id]=1

        # --- decide expected fastqs from library_type (branch on COLUMN) ---
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
            # Integrity: gzip -t catches most corruption; also require a whole
            # FASTQ (non-zero line count divisible by 4).
            local nlines
            if ! gzip -t "$f" 2>/dev/null; then
                problems+=( "${sample_id}: truncated or corrupt gzip: ${f}" )
            elif ! nlines=$(gzip -dc "$f" 2>/dev/null | wc -l) \
                 || (( nlines == 0 )) || (( nlines % 4 != 0 )); then
                problems+=( "${sample_id}: not a whole FASTQ (${nlines:-0} lines, not a multiple of 4): ${f}" )
            fi
        done

    done < <(rows "$SHEET" "$SAMPLE")

    if (( ${#problems[@]} > 0 )); then
        log "validate: found ${#problems[@]} problem(s):"
        local p
        for p in "${problems[@]}"; do
            log "  - ${p}"
        done
        return 65          # EX_DATAERR: the input data was bad
    fi

    log "validate: OK"
}
