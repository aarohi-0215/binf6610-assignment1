#!/usr/bin/env Rscript
# analyze.R — DESeq2, called from rnaseq.sh stage 7.
#
#   Rscript analyze.R <expression.tsv> <samples.tsv> <outdir> <reference level>
#
# Deliberately small. R is not a week-1 topic; this is here so the pipeline has
# a real stage 7 rather than a placeholder.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 4) stop("usage: analyze.R <expression> <samples> <outdir> <ref level>")
expr_path <- args[1]; samples_path <- args[2]; outdir <- args[3]; ref <- args[4]

suppressPackageStartupMessages(library(DESeq2))

counts  <- as.matrix(read.delim(expr_path, row.names = 1, check.names = FALSE))
coldata <- read.delim(samples_path, check.names = FALSE, colClasses = "character")
rownames(coldata) <- coldata$sample_id

# DESeq2 matches counts to metadata BY POSITION. Reorder explicitly.
counts <- counts[, rownames(coldata), drop = FALSE]
if (!ref %in% coldata$condition) stop("reference level '", ref, "' not in condition column")
coldata$condition <- relevel(factor(coldata$condition), ref = ref)

keep <- rowSums(counts) >= 10
dds  <- DESeqDataSetFromMatrix(counts[keep, , drop = FALSE], coldata, ~ condition)
dds  <- DESeq(dds, quiet = TRUE)

res <- as.data.frame(results(dds))
res <- data.frame(gene_id = rownames(res), res, row.names = NULL)
res <- res[order(res$pvalue), ]
write.table(res, file.path(outdir, "de_results.tsv"),
            sep = "\t", quote = FALSE, row.names = FALSE)

cat(sprintf("%d genes tested, %d with padj < 0.05\n",
            nrow(res), sum(res$padj < 0.05, na.rm = TRUE)), file = stderr())
