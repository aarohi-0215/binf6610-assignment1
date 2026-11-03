set -euo pipefail

#=============================================================================
# Stage 7: analyze. Hard-filter the cohort VCF with GATK VariantFiltration.
# Flags (does not delete) variants failing standard GATK germline thresholds.
# Output cohort.filtered.vcf.gz is one of the two files you submit.
#=============================================================================
stage_analyze() {
    local mdir="${OUT}/merge"
    local dir="${OUT}/analyze"; mkdir -p "$dir"
    local in="${mdir}/cohort.vcf.gz"
    local out="${dir}/cohort.filtered.vcf.gz"

    gatk VariantFiltration \
        -R "$REF" \
        -V "$in" \
        --filter-expression "QD < 2.0"                --filter-name "QD2" \
        --filter-expression "FS > 60.0"               --filter-name "FS60" \
        --filter-expression "MQ < 40.0"               --filter-name "MQ40" \
        --filter-expression "SOR > 3.0"               --filter-name "SOR3" \
        -O "$out" \
        >>"${dir}/variantfiltration.log" 2>&1

    [[ -s "$out" ]] || { log "analyze: no filtered VCF"; return 1; }
    [[ -s "${out}.tbi" ]] || { log "analyze: filtered VCF index missing"; return 1; }

    log "analyze: OK"
}
