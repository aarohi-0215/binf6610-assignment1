set -euo pipefail

#=============================================================================
# Stage 6: merge. The barrier: cannot start until every sample's GVCF exists.
# GenomicsDBImport combines the per-sample GVCFs; GenotypeGVCFs joint-genotypes
# them into one multi-sample cohort VCF (one column per sample).
#=============================================================================
_collect_gvcf_args() {
    _one() { printf ' -V %s/quantify/%s.g.vcf.gz' "$OUT" "$1"; }
    read_samples _one
}
stage_merge() {
    local dir="${OUT}/merge"; mkdir -p "$dir"
    # Build the GenomicsDB workspace on node-local temp (fast) rather than on
    # shared storage. GenotypeGVCFs reads it immediately in this same job, so it
    # never needs to persist, and the many small writes GenomicsDBImport makes
    # are far faster on a local disk than over shared /home. TMPDIR is set (and
    # trap-cleaned) by the batch script; fall back to /tmp for a plain run.
    local dbdir="${TMPDIR:-/tmp}/genomicsdb.$$"
    local cohort="${dir}/cohort.vcf.gz"

    # GenomicsDBImport needs a fresh (non-existent) workspace directory.
    rm -rf "$dbdir"

    # Build the -V arguments from the samplesheet (never name a sample here).
    local vargs
    vargs="$(_collect_gvcf_args)"

    # shellcheck disable=SC2086
    gatk GenomicsDBImport \
        ${vargs} \
        -L "$REGION" \
        --batch-size 8 \
        --reader-threads "${THREADS:-4}" \
        --genomicsdb-workspace-path "$dbdir" \
        >>"${dir}/genomicsdbimport.log" 2>&1

    [[ -d "$dbdir" ]] || { log "merge: GenomicsDB workspace missing"; return 1; }

    gatk GenotypeGVCFs \
        -R "$REF" \
        -V "gendb://${dbdir}" \
        -L "$REGION" \
        -O "$cohort" \
        >>"${dir}/genotypegvcfs.log" 2>&1

    [[ -s "$cohort" ]] || { log "merge: no cohort VCF"; return 1; }
    [[ -s "${cohort}.tbi" ]] || { log "merge: cohort VCF index missing"; return 1; }

    log "merge: OK"
}
