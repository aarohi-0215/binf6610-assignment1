# merge_counts.awk — combine per-sample featureCounts output into one matrix.
#
#   awk -f merge_counts.awk out/counts/*.counts.tsv > expression.tsv
#
# featureCounts writes two lines of header, then one row per gene:
#   gene_id  chr  start  end  strand  length  count
# We want column 1 and column 7.
#
# It reads every file into memory keyed by gene and prints the union, so the
# files do not have to be sorted or even contain the same genes -- a gene
# missing from one sample comes out as 0, which is a measurement.
#
# Three awk features here were not in the lecture, named so you can look them
# up: FNR (line number within the current file), FILENAME, and sub().

FNR == 1 {                      # first line of a new file: take the sample name
    n++
    f = FILENAME
    sub(/.*\//, "", f)          # drop the directory
    sub(/\.counts\.tsv$/, "", f)
    sample[n] = f
    next
}
FNR == 2 { next }               # featureCounts' own column header

{ gene[$1] = 1; count[$1, n] = $7 }

END {
    printf "gene_id"
    for (i = 1; i <= n; i++) printf "\t%s", sample[i]
    printf "\n"
    for (g in gene) {
        printf "%s", g
        for (i = 1; i <= n; i++) printf "\t%d", count[g, i] + 0
        printf "\n"
    }
}
