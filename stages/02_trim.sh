set -euo pipefail

#=============================================================================
# Stage 2: trim. fastp removes adapters and low-quality tails. Branch on layout.
#=============================================================================
_trim_one() {
    local id=$1 lib=$4 r1=$5 r2=$6
    local dir="${OUT}/trim"
    mkdir -p "$dir"
    if [[ "$lib" == "paired" ]]; then
        fastp -i "$r1" -I "$r2" \
              -o "${dir}/${id}_R1.trim.fastq.gz" -O "${dir}/${id}_R2.trim.fastq.gz" \
              -j "${dir}/${id}.fastp.json" -h "${dir}/${id}.fastp.html" >&2
        [[ -s "${dir}/${id}_R1.trim.fastq.gz" && -s "${dir}/${id}_R2.trim.fastq.gz" ]] \
            || { log "trim: empty output for ${id}"; return 1; }
    else
        fastp -i "$r1" \
              -o "${dir}/${id}_R1.trim.fastq.gz" \
              -j "${dir}/${id}.fastp.json" -h "${dir}/${id}.fastp.html" >&2
        [[ -s "${dir}/${id}_R1.trim.fastq.gz" ]] \
            || { log "trim: empty output for ${id}"; return 1; }
    fi
    log "trim: ${id} OK"
}
stage_trim() { read_samples _trim_one; }
