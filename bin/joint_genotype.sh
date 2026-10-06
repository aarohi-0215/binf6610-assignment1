#!/usr/bin/env bash
set -euo pipefail

REF=${1:?usage: joint_genotype.sh <reference.fa> <region> <threads> <gvcf...>}
REGION=${2:?usage: joint_genotype.sh <reference.fa> <region> <threads> <gvcf...>}
THREADS=${3:?usage: joint_genotype.sh <reference.fa> <region> <threads> <gvcf...>}
shift 3

ws="${TMPDIR:-/tmp}/genomicsdb.$$"
rm -rf "$ws"
trap 'rm -rf "$ws"' EXIT

vargs=()
for g in "$@"; do
    vargs+=( -V "$g" )
done

gatk GenomicsDBImport \
    "${vargs[@]}" \
    -L "$REGION" \
    --batch-size 8 \
    --reader-threads "$THREADS" \
    --genomicsdb-workspace-path "$ws"

gatk GenotypeGVCFs \
    -R "$REF" \
    -V "gendb://${ws}" \
    -L "$REGION" \
    -O cohort.vcf.gz

[[ -s cohort.vcf.gz && -s cohort.vcf.gz.tbi ]] || { printf 'merge: no cohort VCF\n' >&2; exit 1; }
