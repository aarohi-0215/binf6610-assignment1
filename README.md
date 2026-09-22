# Assignment 1 — A germline variant-calling pipeline in Bash

**Due:** Friday 25 September, 23:59 · **Worth:** 6 % of the course grade

Build a ten-stage variant-calling pipeline in Bash. It is the same architecture as the RNA-seq
pipeline built in class, applied to a different biological question — so the structure transfers and
none of the code does.

You get the acceptance tests that grade it. Run them before you submit.

---

## What you are building

Eight human genomes in, one annotated cohort VCF out.

| Stage | What it does | Tool |
|---|---|---|
| 0 `validate` | check the samplesheet and every input file **before any compute** | bash |
| 1 `qc_raw` | QC metrics from the raw FASTQ | FastQC |
| 2 `trim` | adapter and quality trimming | fastp |
| 3 `align` | align to the whole GRCh38 | BWA-MEM |
| 4 `postprocess` | sort, index, **mark duplicates** | samtools, GATK |
| 5 `quantify` | per-sample variant calling into a GVCF | GATK HaplotypeCaller `-ERC GVCF` |
| 6 `merge` | **joint genotyping** across all eight | GATK GenomicsDBImport + GenotypeGVCFs |
| 7 `analyze` | hard-filter, then annotate | GATK VariantFiltration |
| 8 `qc_report` | one report across the cohort | MultiQC |
| 9 `publish` | tidy TSVs + `manifest.json` | bash |

Stages 0, 1, 2, 8 and 9 are structurally identical to the demo. Stages 3–7 are not. That split is
the point of the assignment: **architecture transfers between problems, code does not.**

### Restrict the analysis region, not the reference

Align to the **complete** GRCh38. Restrict *variant calling* to `chr20:1-10,000,000` with
`-L chr20:1-10000000`.

This is not a shortcut, it is the correct method, and the difference matters. An aligner can only
report that a read is unique among the sequences you gave it. Align to a subset and reads whose true
home is on an absent chromosome pile up somewhere on the ones you kept — with high mapping quality,
because within that subset they really are unique. Measured on this course's own data, a subset
reference produced 106 confident alignments in a region where the sample had no such sequence.

So: whole genome for alignment, ten megabases for calling.

---

## The data

Eight samples from the 1000 Genomes Project. The full table — accessions, read lengths, layout,
sex and the pedigree — is here, and the accessions were checked against live ENA:

<!-- FILE:variant-call-cohort.tsv -->

You build your `samplesheet.csv` from it. `library_type` is what your pipeline branches on.

**The cohort's reads are already on Explorer.** They are at

```
/courses/BINF6610.202710/data/fastq-variant/
```

— eight samples, 1.3 GB in total, extracted by region from the 1000 Genomes aligned CRAMs so that
they cover `chr20:1–10,000,000` at about 37×. That is the copy you run the pipeline against **next
week, on the cluster**, and it is the reason you never have to move sequencing data anywhere.

**This week, on your laptop, you do not use them.** You cut your own development slice instead —
step 3 of *Getting started* below shows how, and it costs about 640 KB and three seconds. The `run`
column is the ENA accession that slice comes from.

| | |
|---|---|
| Samples | 8 — `NA12878`, `NA12891`, `NA12892`, `NA07357`, `NA12003`, `NA10851`, `NA12813`, `NA12873` |
| Sex | 4 female, 4 male |
| Libraries | 6 paired-end, 2 single-end |
| Read length | 150–151 bp |

> **The `phenotype` column is synthetic and every row says so.** `is_synthetic_phenotype` is `true`
> for all eight. These are healthy reference genomes; nobody in this cohort is affected by anything.
> The column exists so the pipeline has a two-level factor to group by, which is what stages 6 and 7
> need. Never present a synthetic label as a finding, and never build a pipeline that lets one pass
> unmarked.

**`NA12878` must stay in your cohort.** It is the Genome in a Bottle benchmark sample, which means
there is a published truth set for it — so your variant calls can be scored for precision and
recall rather than merely inspected. Later modules use that.

### Two samples are single-end

`NA12892` and `NA12003` have an empty `r2_fastq`. That empty field is the authoritative signal, and
your pipeline must branch on the samplesheet rather than on the sample's name. A pipeline that says
`if [[ $sample == NA12892 ]]` fails the acceptance test that swaps which samples are single-end.

---

## What to submit

```
your-repo/
├── run_pipeline.sh          # the driver
├── lib/                     # your libraries
├── stages/                  # one script per stage
├── conf/pipeline.env        # configuration, no secrets
├── samplesheet.csv          # the eight samples
├── TROUBLESHOOTING.md       # see below
└── results/                 # DO NOT COMMIT — .gitignore it
```

> **That is the layout you hand in, not the one you start with.** Week 1's demo is a single
> file and so is the first thing you should write — one script, one function per stage, run
> in order. Splitting it into `lib/` and `stages/` is week 2's work, and week 2 gives you the
> reason: a Slurm job array runs *stages 0–5 for one sample*, which needs a per-sample entry
> point, and eight copies running at once need the logging and the sheet reading to live in
> one place.
>
> Split it before you have that reason and you get a broken script and no lesson.

**`run_pipeline.sh` may take its arguments either way, and both are accepted.** The demo takes
three positional arguments and one slide in the lecture writes the same thing as flags:

```bash
./run_pipeline.sh samplesheet.csv out validate                        # positional, like the demo
./run_pipeline.sh --samplesheet samplesheet.csv --outdir out --to validate   # flags
```

Pick one and be consistent. The acceptance harness reads your driver once, calls it the way you
wrote it, and prints which form it detected in its first two lines. The third argument is the
**last stage to run** — being able to stop after `validate` is what gives you a one-second
edit-run loop, and most of the tests depend on it.

Submit a link to a Git repository. Do not commit FASTQ files, BAMs, VCFs, or the reference.

### Set the repository up first — before your first run

This repository is where the whole course lives: every week adds to it, and week 8 automates it.
Create it now, on GitHub, and **make one commit before you run the pipeline for the first time**:

```bash
git init
git add .
git commit -m "week 1: pipeline skeleton"
```

The reason is one line in `results/manifest.json`. Your pipeline records `git_sha` — the commit
your code was on when it ran — and that is why this assignment asks for a repository link instead
of a zip file. A zip says what you produced; the sha says which code produced it.

Run before you commit and the field reads `unknown`. That is honest, and useless.

There is a third value, and it is the one worth knowing about now. If you commit, then edit a
script, then run without committing again, the manifest records **`<sha>-dirty`**. It is telling
you that the sha no longer describes the code that ran — somebody checking out that commit would
get something different from what you executed. Seeing `-dirty` in your own manifest is not an
error to fix; it is the pipeline being straight with you about what it can and cannot vouch for.

---

## How it is graded

**90 points — acceptance tests.** In `tests/`. You run them; they are the same file used to grade.
**Every one of them checks something week 1 taught**, and when one fails it says what to go back to.

| Pts | Test | Full marks | Partial |
|---:|---|---|---|
| 20 | stage 0 reports every problem together | four samples, three of them broken, non-zero exit, all three named | **10** — it fails, but names only the first problem it met |
| 15 | survives a sample named `Donor 3-rep1` | the name is carried through intact | — |
| 10 | catches a truncated `.fastq.gz` | fails in stage 0 **and** names the sample | **5** — caught, but the message never says which sample |
| 10 | rejects a duplicate `sample_id` | non-zero exit **and** the message names it | **5** — rejected, but never names the duplicate |
| 10 | single-end read from `library_type` | branches on the column, not on the sample's name | — |
| 10 | `set -euo pipefail` in every script | all three flags, in every `.sh` you ship | **5** — some scripts only |
| 10 | progress messages go to stderr | stage 0 reports on stderr and leaves stdout empty | — |
| 5 | no sample is named in the code | none of the eight ids appears outside a comment | — |

The partial bands are transcriptions of what the harness printed, not estimates of how nearly
something worked. Four criteria have none, because there the harness cannot tell two failures apart
and an invented middle rating would turn a measurement into an argument.

Run them:

```bash
bash tests/run_acceptance.sh /path/to/your-repo
```

They need no sequencing data. Every one runs in seconds against fixtures the harness builds itself —
so there is no excuse for finding out at submission time. They invoke your driver as

```bash
./run_pipeline.sh <samplesheet.csv> <outdir> validate
```

three positional arguments, the same as the demo. **If you wrote a `--samplesheet/--outdir/--to`
driver instead, that works too** — the harness reads your driver once and calls it the way you wrote
it, and prints which form it detected. Either way it hands you the six-column samplesheet the demo
reads.

**10 points — `TROUBLESHOOTING.md`.** Half a page. What broke, how you found it, what the fix was.

| Pts | |
|---:|---|
| 10 | **Specific and diagnostic** — symptom, the evidence that located the cause, the cause, the fix |
| 8 | **Specific, thin on method** — what broke and what fixed it, but not how you found it |
| 5 | **General** — "I had problems with paths and fixed them" |
| 2 | **Present only** — a sentence or two, or a list of commands |
| 0 | **Absent** |

Specific, not general. Not *"I had a path bug and fixed it."* More like: *"stage 3 produced an empty
BAM for NA12003; the log showed bwa exited 0; I found the pipeline was missing `pipefail`, so
samtools masked bwa's failure; added it, and the run failed properly."*

The tests check that your pipeline works. The log shows you know why it works. They are not the same
thing, and only one of them survives contact with the next problem.

The same criteria are the Canvas rubric on this page, so what you see below the description is what
you are marked against — nothing is hidden and nothing is held back.

---

## Getting started

1. **Read the demo pipeline first.** It is on Canvas: one file, about 290 lines, ten functions
   run in order. Everything you need structurally is in there.
2. **Copy the architecture, not the code.** The samplesheet as the only input, stage 0
   collecting every problem before anything computes, a check after every tool, messages on
   stderr — all of that transfers. None of the tool calls do.
3. **Cut your own development slice before you run anything for real.** A few thousand reads per
   sample is enough to answer *does my code run*, and that is the only question a laptop can answer.

   You do **not** have to download a whole run to get one. The file is gzipped and ENA serves it over
   HTTP, so you can read the front of the stream and stop:

   ```bash
   mkdir -p dev
   URL=ftp.sra.ebi.ac.uk/vol1/fastq/ERR166/081/ERR16657781/ERR16657781_1.fastq.gz
   curl -s "https://${URL}" | gzip -dc | head -16000 | gzip > dev/NA12878_R1.fastq.gz
   ```

   `head` stops after 16,000 lines — 4,000 records — and closing the pipe stops the download.
   Measured against that run: **640 KB and about three seconds for both mates**, out of a file that
   is 19.3 GB. Do the same with `_2.fastq.gz` for R2; the two files are in the same order, so record
   *n* of one is the mate of record *n* of the other. Then point a second samplesheet at `dev/` and
   develop against that.

   **This is a slice for testing code, not for measuring anything.** The first reads in a FASTQ come
   from the edge of the flowcell and are not a random sample of the library — the same caveat that
   applies to the cohort's own read sets. If you already have a full file on disk and want an
   unbiased slice, `seqtk sample -s100 file.fastq.gz 5000` is the tool.

   A run that takes four seconds is a run you will do two hundred times; a run that takes an hour is
   one you will do twice.
4. **Build stage 0 first, and run it constantly.** Six of the nine tests run through stage 0, and
   three of those six are gated on it: they check how a sample is *handled*, so the harness first
   confirms your driver reads the samplesheet at all before it will award them. It is also the stage
   that saves you the most time while you develop.
5. **Then one stage at a time, on one sample**, before you loop over eight.

### How long this should take to run

**Seconds, this week.** You are developing against a slice of a few thousand reads, and the
acceptance tests build their own fixtures and need no sequencing data at all — the whole suite runs
in about ten seconds. If any part of your edit-run loop takes minutes, your slice is too big.

**The full cohort is next week's run, on Explorer.** Measured there on one sample of the prepared
read set: 97 seconds for BWA-MEM on 8 cores, 6.3 GB of memory, a 104 MB BAM. Eight of those as a
job array is minutes, not hours.

What this means for how you work: **do not wait until you have real output to find out whether your
pipeline is correct.** Nine criteria say what correct means and you can run eight of them yourself
right now, before you have aligned a single read.

> **`set -euo pipefail` is necessary and not sufficient.** Six places where `-e` does not fire were
> covered in the lecture, and at least two of them are reachable in this assignment. Assertions on
> your data — the record count divides by four, R1 and R2 agree, the output is not empty — are what
> you actually rely on.
