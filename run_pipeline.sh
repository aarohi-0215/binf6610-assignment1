#!/usr/bin/env bash
#=============================================================================
# run_pipeline.sh — germline variant-calling pipeline (Week 1, Bash)
#
# Usage:  ./run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]
#=============================================================================

set -euo pipefail

SHEET=${1:?usage: run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]}
OUT=${2:?usage: run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]}
LAST=${3:-publish}
FIRST=${4:-validate}   # first stage to run (default: from the start)

# Load configuration if present (defaults live inside the file).
CONF="$(dirname "$0")/conf/pipeline.env"
[[ -f "$CONF" ]] && source "$CONF"

# Fallbacks in case conf/pipeline.env is missing.
REF="${REF:-smoke/smoke.fa}"
REGION="${REGION:-smoke_1mb}"
THREADS="${THREADS:-4}"
MULTIQC="${MULTIQC:-multiqc}"

# One run_id and start time for the whole run (used by the manifest in stage 9).
RUN_ID="$(date -u +%Y-%m-%dT%H:%M:%SZ)-$$"
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

#-----------------------------------------------------------------------------
# log() — status to stderr (channel 2). stdout (channel 1) is for DATA only.
#-----------------------------------------------------------------------------
log() { printf '%s\n' "$*" >&2; }

#-----------------------------------------------------------------------------
# read_samples CALLBACK — call CALLBACK once per data row of the samplesheet,
# passing: sample_id condition replicate library_type r1 r2
# Uses < <(...) not a pipe, so the caller's variables survive (see stage 0).
#-----------------------------------------------------------------------------
read_samples() {
    local cb="$1" sample_id condition replicate library_type r1 r2
    while IFS=, read -r sample_id condition replicate library_type r1 r2; do
        [[ -z "$sample_id" ]] && continue
        "$cb" "$sample_id" "$condition" "$replicate" "$library_type" "$r1" "$r2"
    done < <(tail -n +2 "$SHEET")
}

STAGES=(validate qc_raw trim align postprocess quantify merge analyze qc_report publish)

#=============================================================================
# Stage 0 — validate. Check the samplesheet and every input BEFORE any compute.
# Golden rule: collect EVERY problem into an array, report them all, fail once.
#=============================================================================
stage_validate() {
    local -a problems=()
    local -A seen=()

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

    done < <(tail -n +2 "$SHEET")

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

#=============================================================================
# Stage 1 — qc_raw. FastQC on every raw FASTQ. Per-sample.
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

#=============================================================================
# Stage 2 — trim. fastp: remove adapters and low-quality tails. Branch on layout.
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

#=============================================================================
# Stage 3 — align. BWA-MEM -> samtools sort -> coordinate-sorted BAM.
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
          | samtools sort -@ "$THREADS" -o "$bam" - 2>>"${dir}/${id}.sort.log"
    else
        bwa mem -t "$THREADS" -R "$rg" "$REF" \
            "${trim}/${id}_R1.trim.fastq.gz" 2>>"${dir}/${id}.bwa.log" \
          | samtools sort -@ "$THREADS" -o "$bam" - 2>>"${dir}/${id}.sort.log"
    fi

    # assert: a non-empty BAM with at least one mapped read.
    [[ -s "$bam" ]] || { log "align: no BAM for ${id}"; return 1; }
    local mapped; mapped=$(samtools view -c -F 4 "$bam")
    (( mapped > 0 )) || { log "align: ${id} produced a BAM with 0 mapped reads"; return 1; }
    log "align: ${id} OK (${mapped} mapped)"
}
stage_align() { read_samples _align_one; }

#=============================================================================
# Stage 4 — postprocess. Mark duplicates, then index the BAM.
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

#=============================================================================
# Stage 5 — quantify. Per-sample variant calling into a GVCF, restricted to
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

#=============================================================================
# Stage 6 — merge. The barrier: cannot start until every sample's GVCF exists.
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
    # never needs to persist — and the many small writes GenomicsDBImport makes
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

#=============================================================================
# Stage 7 — analyze. Hard-filter the cohort VCF with GATK VariantFiltration.
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

#=============================================================================
# Stage 8 — qc_report. MultiQC aggregates the tool logs into one HTML report.
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

#=============================================================================
# Stage 9 — publish. Copy the contract outputs to results/ and write
# manifest.json (validated against tests/manifest.schema.json).
#=============================================================================
_sha256() { printf 'sha256:%s' "$(sha256sum "$1" | cut -d' ' -f1)"; }

stage_publish() {
    local rdir="${OUT}/results"; mkdir -p "$rdir"
    local filtered="${OUT}/analyze/cohort.filtered.vcf.gz"
    local multiqc="${OUT}/qc_report/multiqc_report.html"

    # Publish the contract artifacts into results/.
    cp "$filtered"       "${rdir}/cohort.filtered.vcf.gz"
    cp "${filtered}.tbi" "${rdir}/cohort.filtered.vcf.gz.tbi" 2>/dev/null || true
    [[ -f "$multiqc" ]] && cp "$multiqc" "${rdir}/multiqc_report.html"

    # git sha (why the first commit matters). -dirty if uncommitted changes.
    local sha
    sha="$(git -C "$(dirname "$0")" rev-parse --short=7 HEAD 2>/dev/null || echo unknown)"
    if ! git -C "$(dirname "$0")" diff --quiet 2>/dev/null; then
        sha="${sha}-dirty"
    fi

    local finished_at; finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # --- samples[] built from the samplesheet (no names in code) ------------
    local samples_json="" first=1
    _sample_json() {
        local id=$1 cond=$2 lib=$4
        local sep=""; [[ $first -eq 0 ]] && sep=","; first=0
        samples_json+="${sep}{\"sample_id\":\"${id}\",\"library_type\":\"${lib}\",\"condition\":\"${cond}\"}"
    }
    read_samples _sample_json

    # --- outputs[] : published artifacts, each with a real checksum ----------
    local vcf_sum; vcf_sum="$(_sha256 "${rdir}/cohort.filtered.vcf.gz")"
    local outputs_json="{\"stage\":\"analyze\",\"type\":\"cohort_vcf\",\"path\":\"cohort.filtered.vcf.gz\",\"checksum\":\"${vcf_sum}\"}"
    if [[ -f "${rdir}/multiqc_report.html" ]]; then
        local mq_sum; mq_sum="$(_sha256 "${rdir}/multiqc_report.html")"
        outputs_json+=",{\"stage\":\"qc_report\",\"type\":\"multiqc\",\"path\":\"multiqc_report.html\",\"checksum\":\"${mq_sum}\"}"
    fi

    # --- metrics[] : numeric metrics ----------------------------------------
    local n_total n_pass
    n_total="$(zcat "$filtered" | grep -vc '^#' || true)"
    n_pass="$(zcat "$filtered" | awk -F'\t' '!/^#/ && $7=="PASS"' | wc -l || true)"
    local metrics_json
    metrics_json="{\"metric\":\"n_variants_total\",\"value\":${n_total:-0},\"stage\":\"merge\"},"
    metrics_json+="{\"metric\":\"n_variants_pass\",\"value\":${n_pass:-0},\"stage\":\"analyze\"}"

    # --- assemble manifest.json ---------------------------------------------
    cat > "${rdir}/manifest.json" <<JSON
{
  "pipeline": {
    "name": "variant-call",
    "version": "1.0.0",
    "implementation": "bash",
    "git_sha": "${sha}",
    "run_id": "${RUN_ID}",
    "started_at": "${STARTED_AT}",
    "finished_at": "${finished_at}",
    "exit_status": "success"
  },
  "platform": {
    "kind": "laptop",
    "region": "${REGION}"
  },
  "reference": {
    "genome": "${REF}"
  },
  "samples": [ ${samples_json} ],
  "outputs": [ ${outputs_json} ],
  "metrics": [ ${metrics_json} ]
}
JSON

    [[ -s "${rdir}/manifest.json" ]] || { log "publish: manifest not written"; return 1; }
    log "publish: OK -> ${rdir}/cohort.filtered.vcf.gz , ${rdir}/manifest.json"
}

#=============================================================================
# The driver — run stages in order, stop after the one named in LAST.
#=============================================================================
n=0
started=0
for stage in "${STAGES[@]}"; do
    [[ "$stage" == "$FIRST" ]] && started=1
    if (( started )); then
        log "===== stage ${n} : ${stage} ====="
        "stage_${stage}"
        [[ "$stage" == "$LAST" ]] && break
    fi
    n=$(( n + 1 ))
done
log "done"