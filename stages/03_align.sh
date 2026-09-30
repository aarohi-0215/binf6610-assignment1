set -euo pipefail

#=============================================================================
# Stage 3: align. BWA-MEM -> samtools sort -> coordinate-sorted BAM.
# The read group's SM tag MUST equal the sample_id: GATK reads it to name the
# VCF column, and the smoke test matches columns to truth files by that name.
#=============================================================================
_align_one() {
    local id=$1 lib=$4
    local dir="${OUT}/align"; mkdir -p "$dir"
    local trim="${OUT}/trim"
    local rg="@RG\tID:${id}\tSM:${id}\tPL:ILLUMINA\tLB:${id}"
    local bam="${dir}/${id}.sorted.bam"

    if [[ "$lib" == "paired" ]]; then
        bwa mem -t "$THREADS" -R "$rg" "$REF" \
            "${trim}/${id}_R1.trim.fastq.gz" "${trim}/${id}_R2.trim.fastq.gz" 2>>"${dir}/${id}.bwa.log" \
          | samtools sort -@ "$THREADS" -T "${TMPDIR:-/tmp}/sort.${id}.$$" -o "$bam" - 2>>"${dir}/${id}.sort.log"
    else
        bwa mem -t "$THREADS" -R "$rg" "$REF" \
            "${trim}/${id}_R1.trim.fastq.gz" 2>>"${dir}/${id}.bwa.log" \
          | samtools sort -@ "$THREADS" -T "${TMPDIR:-/tmp}/sort.${id}.$$" -o "$bam" - 2>>"${dir}/${id}.sort.log"
    fi

    # assert: a non-empty BAM with at least one mapped read.
    [[ -s "$bam" ]] || { log "align: no BAM for ${id}"; return 1; }
    local mapped; mapped=$(samtools view -c -F 4 "$bam")
    (( mapped > 0 )) || { log "align: ${id} produced a BAM with 0 mapped reads"; return 1; }
    log "align: ${id} OK (${mapped} mapped)"
}
stage_align() { read_samples _align_one; }
