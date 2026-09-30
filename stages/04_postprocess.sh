set -euo pipefail

#=============================================================================
# Stage 4: postprocess. Mark duplicates, then index the BAM.
#=============================================================================
_postprocess_one() {
    local id=$1
    local adir="${OUT}/align"
    local dir="${OUT}/postprocess"; mkdir -p "$dir"
    local in="${adir}/${id}.sorted.bam"
    local out="${dir}/${id}.markdup.bam"

    gatk MarkDuplicates \
        -I "$in" \
        -O "$out" \
        -M "${dir}/${id}.markdup.metrics.txt" \
        >>"${dir}/${id}.markdup.log" 2>&1

    [[ -s "$out" ]] || { log "postprocess: no markdup BAM for ${id}"; return 1; }

    samtools index "$out"
    [[ -s "${out}.bai" ]] || { log "postprocess: index missing for ${id}"; return 1; }

    log "postprocess: ${id} OK"
}
stage_postprocess() { read_samples _postprocess_one; }
