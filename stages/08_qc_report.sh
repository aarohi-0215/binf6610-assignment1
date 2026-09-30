set -euo pipefail

#=============================================================================
# Stage 8: qc_report. MultiQC aggregates the tool logs into one HTML report.
# Uses $MULTIQC (from conf) so no tool path is baked into the stage.
#=============================================================================
stage_qc_report() {
    local dir="${OUT}/qc_report"; mkdir -p "$dir"
    local mqc="$MULTIQC"
    command -v "$mqc" >/dev/null 2>&1 || [[ -x "$mqc" ]] || mqc="multiqc"
    "$mqc" "$OUT" -o "$dir" -n multiqc_report >>"${dir}/multiqc.log" 2>&1 || true
    [[ -f "${dir}/multiqc_report.html" ]] || { log "qc_report: no MultiQC report"; return 1; }
    log "qc_report: OK"
}
