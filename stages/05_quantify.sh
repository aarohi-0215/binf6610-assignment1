set -euo pipefail

#=============================================================================
# Stage 5: quantify. Per-sample variant calling into a GVCF, restricted to
# REGION. GVCF mode (-ERC GVCF) records reference confidence at every position
# so stage 6 can joint-genotype across all samples.
#=============================================================================
_quantify_one() {
    local id=$1
    local pdir="${OUT}/postprocess"
    local dir="${OUT}/quantify"; mkdir -p "$dir"
    local in="${pdir}/${id}.markdup.bam"
    local gvcf="${dir}/${id}.g.vcf.gz"

    gatk HaplotypeCaller \
        -R "$REF" \
        -I "$in" \
        -L "$REGION" \
        -ERC GVCF \
        -O "$gvcf" \
        >>"${dir}/${id}.hc.log" 2>&1

    [[ -s "$gvcf" ]] || { log "quantify: no GVCF for ${id}"; return 1; }
    [[ -s "${gvcf}.tbi" ]] || { log "quantify: GVCF index missing for ${id}"; return 1; }

    log "quantify: ${id} OK"
}
stage_quantify() { read_samples _quantify_one; }
