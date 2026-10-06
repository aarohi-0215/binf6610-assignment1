#!/usr/bin/env bash
set -euo pipefail

ID=${1:?usage: align.sh <sample_id> <reference.fa> <threads> <reads...>}
REF=${2:?usage: align.sh <sample_id> <reference.fa> <threads> <reads...>}
THREADS=${3:?usage: align.sh <sample_id> <reference.fa> <threads> <reads...>}
shift 3

rg="@RG\tID:${ID}\tSM:${ID}\tPL:ILLUMINA\tLB:${ID}"
bam="${ID}.sorted.bam"

bwa mem -t "$THREADS" -R "$rg" "$REF" "$@" 2> "${ID}.bwa.log" \
  | samtools sort -@ "$THREADS" -T "${TMPDIR:-/tmp}/sort.${ID}.$$" -o "$bam" - 2> "${ID}.sort.log"

[[ -s "$bam" ]] || { printf 'align: no BAM for %s\n' "$ID" >&2; exit 1; }
mapped=$(samtools view -c -F 4 "$bam")
(( mapped > 0 )) || { printf 'align: %s produced a BAM with 0 mapped reads\n' "$ID" >&2; exit 1; }
printf 'align: %s OK (%s mapped)\n' "$ID" "$mapped" >&2
