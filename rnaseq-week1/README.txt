# The week-1 demo pipeline

This is the **instructor's** implementation, the one built in week 1's session. It is here to be
**read**, and it is nothing you submit.

```
rnaseq.sh           the pipeline — ten functions, run in order
merge_counts.awk    stage 6 — every sample's counts into one matrix
analyze.R           stage 7 — DESeq2
samplesheet.csv     the twelve demo samples
```

## Running it

```
bash rnaseq.sh <samplesheet.csv> <outdir> [last-stage]

bash rnaseq.sh samplesheet.csv run validate     stage 0 only
bash rnaseq.sh samplesheet.csv run align        stages 0 to 3
bash rnaseq.sh samplesheet.csv run              all ten
```

The third argument is the **last stage to run**, defaulting to `publish`.

Configuration comes from the environment, all of it with defaults, so no path is written into
the code:

```
REF_DIR         where the reference lives        (data/refs/grch38)
INDEX           the HISAT2 index prefix          ($REF_DIR/hisat2/genome)
GTF             the annotation                   ($REF_DIR/annotation.gtf)
THREADS         threads per tool                 (4)
CONDITION_REF   the DESeq2 reference level       (Healthy)
```

## Run this one command even without any data

```
bash rnaseq.sh samplesheet.csv run validate
```

It **fails**, and that is the point. You have neither the reference nor the FASTQ files, so
stage 0 reports every missing thing at once and exits 65 — rather than dying on the first one
and making you find the rest one run at a time. That is the behaviour your own stage 0 has to
have.

## Two things to notice while you read it

**It is deliberately repetitive.** Every stage reads the samplesheet with its own
`while IFS=, read` loop. Pulling that out into a shared helper is week 2's work, and week 2
gives you the reason to want it.

**Everything in it was in the week-1 lecture.** There is no parallelism, no resuming, no
temp-then-rename, no JSON, no traps and no associative arrays — those are all next week, on the
cluster, where there is a reason for them.

## What this is not

It is not your assignment. Yours is germline variant calling on eight human genomes: the same
ten stages and the same architecture, a different question and different tools. Stages 0, 1, 2,
8 and 9 are structurally the same; stages 3 to 7 are not. **The architecture transfers; the code
does not.**
