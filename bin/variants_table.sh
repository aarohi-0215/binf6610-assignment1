#!/usr/bin/env bash
set -euo pipefail

VCF=${1:?usage: variants_table.sh <vcf.gz>}

printf 'chrom\tpos\tref\talt\tqual\tfilter\n' > variants.tsv
bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%QUAL\t%FILTER\n' "$VCF" >> variants.tsv
