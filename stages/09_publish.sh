set -euo pipefail

#=============================================================================
# Stage 9: publish. Copy the contract outputs to results/ and write
# manifest.json (validated against tests/manifest.schema.json).
#=============================================================================
stage_publish() {
    local rdir="${OUT}/results"; mkdir -p "$rdir"
    local filtered="${OUT}/analyze/cohort.filtered.vcf.gz"
    local multiqc="${OUT}/qc_report/multiqc_report.html"

    cp "$filtered"       "${rdir}/cohort.filtered.vcf.gz"
    cp "${filtered}.tbi" "${rdir}/cohort.filtered.vcf.gz.tbi" 2>/dev/null || true
    [[ -f "$multiqc" ]] && cp "$multiqc" "${rdir}/multiqc_report.html"

    bash "${HERE}/lib/write_manifest.sh" "${rdir}" "${SHEET}" "${REF}" "${REGION}"

    [[ -s "${rdir}/manifest.json" ]] || { log "publish: manifest not written"; return 1; }
    log "publish: OK -> ${rdir}/cohort.filtered.vcf.gz , ${rdir}/manifest.json"
}
