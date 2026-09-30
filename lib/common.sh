set -euo pipefail

REF=${REF:-/courses/BINF6610.202710/data/refs/grch38-1000g/GRCh38_full_analysis_set_plus_decoy_hla.fa}
REGION=${REGION:-chr20:1-10000000}
THREADS=${THREADS:-4}
MULTIQC=${MULTIQC:-$HOME/mqc-venv/bin/multiqc}

#-----------------------------------------------------------------------------
# log(): status to stderr (channel 2). stdout (channel 1) is for DATA only.
#-----------------------------------------------------------------------------
log() { printf '%s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 65; }

setup_dirs() {
    mkdir -p "${OUT}"/{qc_raw,trim,align,postprocess,quantify,merge,analyze,qc_report,results}
}

rows() {
    local sheet=$1 only=${2:-}
    awk -F, -v want="$only" '
        BEGIN { n = split("sample_id condition replicate library_type r1_fastq r2_fastq", need, " ") }
        { gsub(/\r/, "") }
        NR == 1 {
            for (i = 1; i <= NF; i++) col[$i] = i
            for (i = 1; i <= n; i++)
                if (!(need[i] in col)) {
                    print "samplesheet has no column named " need[i] > "/dev/stderr"
                    exit 65
                }
            next
        }
        $col["sample_id"] == "" { next }
        want != "" && $col["sample_id"] != want { next }
        { print $col["sample_id"] "," $col["condition"] "," $col["replicate"] "," \
                $col["library_type"] "," $col["r1_fastq"] "," $col["r2_fastq"] }
    ' "$sheet"
}

#-----------------------------------------------------------------------------
# read_samples CALLBACK: call CALLBACK once per data row of the samplesheet,
# passing: sample_id condition replicate library_type r1 r2
# Uses < <(...) not a pipe, so the caller's variables survive (see stage 0).
#-----------------------------------------------------------------------------
read_samples() {
    local cb="$1" sample_id condition replicate library_type r1 r2
    while IFS=, read -r sample_id condition replicate library_type r1 r2; do
        [[ -z "$sample_id" ]] && continue
        "$cb" "$sample_id" "$condition" "$replicate" "$library_type" "$r1" "$r2"
    done < <(rows "$SHEET" "${SAMPLE:-}")
}
