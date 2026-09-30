set -euo pipefail

#=============================================================================
# Stage 1: qc_raw. FastQC on every raw FASTQ. Per-sample.
#=============================================================================
_qc_one() {
    local id=$1 lib=$4 r1=$5 r2=$6
    local dir="${OUT}/qc_raw"
    mkdir -p "$dir"
    local -a fq=( "$r1" )
    [[ "$lib" == "paired" ]] && fq+=( "$r2" )
    fastqc -q -o "$dir" "${fq[@]}" >&2
    # assert: FastQC can exit 0 and write nothing. Ask the disk.
    local f base
    for f in "${fq[@]}"; do
        base=$(basename "$f" .fastq.gz)
        [[ -f "${dir}/${base}_fastqc.zip" ]] || { log "qc_raw: no report for ${id} (${f})"; return 1; }
    done
    log "qc_raw: ${id} OK"
}
stage_qc_raw() { read_samples _qc_one; }
