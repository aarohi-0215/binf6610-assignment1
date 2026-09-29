# TROUBLESHOOTING.md — Assignment 2 (job array on Explorer)

**Use of AI assistance.** I used an AI assistant (Claude) to help scaffold the
Slurm scripts and to reason about failures. Every job below was submitted by me
on Explorer, and every sacct line is pasted from my own terminal. The Assignment 1
log is on the `main` branch.

The cohort data is small enough that nothing breaks on its own, so I broke the
pipeline four times on purpose. The throwaway scripts for these lived in `ts/` on
Explorer; they are not part of the pipeline and are not committed.

---

## 1. A `--time` that is too short → TIMEOUT

**Broke it.** One per-sample task (NA12878) with `--time=00:02:00`. A full
sample takes about 8 minutes.

```
JobID             State    Elapsed ExitCode     MaxRSS
10672029_1      TIMEOUT   00:02:21      0:0
10672029_1.+  CANCELLED   00:02:22     0:15  12914972K
```

**Where it stopped.** The log ran through validate, qc_raw and trim, printed
`===== stage 3 : align =====`, and ended with
`slurmstepd: error: *** JOB 10672029 ON c0672 CANCELLED AT 2026-09-28T20:14:51 DUE TO TIME LIMIT ***`.

**What was left on disk.** `qc_raw/` reports and both trimmed FASTQs, and in
`align/` only `NA12878.bwa.log` and `NA12878.sort.log`. There was no BAM at all. The job
died inside `bwa mem | samtools sort` before sort wrote anything. `--time` is
enforced on Explorer (`--mem` is not), so it is the limit that actually kills a job.
A stage that is killed like this leaves a directory that looks as if it started.
A pipeline that trusted "the folder exists" would be wrong.

## 2. A task that exits 1, with the cohort job on afterok → cohort CANCELLED

**Broke it.** A two-task array in which task 2 runs `exit 1`, plus a dependent
job submitted exactly as `submit.sh` submits the cohort:
`--dependency=afterok:<array id> --kill-on-invalid-dep=yes`. I used a stand-in
dependent job (`--wrap`) rather than the real `02_cohort.sbatch` so that the
failure could not overwrite my real cohort outputs. The dependency mechanism is
identical.

```
JobID             State ExitCode
10672638_1    COMPLETED      0:0
10672638_2       FAILED      1:0
10672639      CANCELLED            Reason=Dependency
```

**What happened.** Task 2 failed, so `afterok` could never be satisfied, and the
dependent job was CANCELLED with Reason=Dependency within seconds. It never
started. That is the scheduler refusing to build a wrong answer. Under `afterany`
the cohort job would have joint-genotyped the samples that did finish. The result
would be a VCF of the right shape, one sample short, and nothing would say so.

## 3. An array wider than the samplesheet → the out-of-range task refuses

**Broke it.** Submitted the real `01_persample.sbatch` with `--array=9` against the
eight-row `samplesheet.cluster.csv`. I ran index 9 on its own rather than
`--array=1-9`, to avoid rerunning the eight real samples. Index 9 is the task
that `--array=1-9` would have added, and it sees exactly the same thing.

```
JobID             State    Elapsed ExitCode
10672081_9       FAILED   00:00:10     65:0
```

**What task 9 did.** It found no row 10 in the sheet and exited 65 in 10 seconds,
with `task 9: no row 10 in samplesheet.cluster.csv — out-of-range array index, refusing.`
That is the `[[ -z "${SAMPLE}" ]]` guard in `01_persample.sbatch`.

**What it would have done without the guard.** `SAMPLE` would be empty and
`run_sample.sh` would have been called with no sample. Every stage would loop over
nothing, succeed at each, and exit 0. The result: nine COMPLETED tasks and eight
results, and nothing in `squeue` or `sacct` says which one is fake. This is the only
one of the four failures that can succeed while being wrong. The other three announce
themselves.

## 4. scancel mid-write, then resubmit → did the rerun trust the leftovers?

**Broke it.** Submitted a per-sample job (NA12878), let it get past alignment, and
ran `scancel` during stage 4 (postprocess). Then I resubmitted the identical job.

```
JobID             State    Elapsed ExitCode
10672650     CANCELLED+   00:03:32      0:0     (cancelled during postprocess)
10672678     CANCELLED+   00:04:14      0:0     (the rerun; I cancelled it once it had answered the question)
```

**What was left behind.** `align/NA12878.sorted.bam` (105,849,847 bytes) and
`postprocess/NA12878.markdup.bam` (132,412,347 bytes) with its `.bai` and
metrics file.

**I aimed at X and got Y.** I meant to cancel while MarkDuplicates was still
writing and to leave a truncated, partial BAM. The `.bai` and metrics file were
already there, so MarkDuplicates had most likely finished before the cancel landed.
I cannot claim the leftover BAM was truncated. I did not run `samtools quickcheck`
on it before the rerun overwrote it.

**What the rerun did.** It did not trust or even look at the leftovers. It
restarted at stage 0 and redid validate, qc_raw, trim, align (2,447,146 mapped again)
and postprocess, overwriting every file. It had reached stage 5 when I cancelled it.
My pipeline has no resume logic, so a rerun is always safe. It can never build on a
half-written file, but it also re-spends the full ~8 minutes. The better fix is to
write each output under a temporary name and rename it only once it is complete.
Then a rerun can skip finished stages and still never trust a partial one.

---

## Problems I did not cause on purpose (found while running the cohort)

**The cohort job re-aligned every sample.** Symptom: 12 minutes into the first
cohort job, `merge/` was empty. `logs/cohort_10671975.err` showed
`===== stage 3 : align =====` for NA12873. Cause: `02_cohort.sbatch` called
`run_pipeline.sh` with no stage bounds, so it ran all ten stages and redid, one sample
at a time, the work the array had just finished. Fix: I added a FIRST-stage argument to
`run_pipeline.sh` and made the cohort job run `publish merge` (stages 6–9 only). I
tested it on the smoke data before resubmitting.

**GenomicsDBImport crawled on shared storage.** Symptom: the second cohort job
sat on `Importing batch 1 with 8 samples` for 33 minutes. `du` on the workspace
showed it growing only about 3 MB a minute, so it was working, not hung. The inputs
were correctly region-limited (18–25 MB GVCFs, `Processing 10000000 bp`), so the
cause was not the region. Cause: the GenomicsDB workspace was written under the
run directory in `/home`, which is shared storage, and GenomicsDBImport makes many
small writes. Fix: I build the workspace in `$TMPDIR` (node-local `/tmp/$SLURM_JOB_ID`,
cleaned by the trap). GenotypeGVCFs reads it in the same job, so it never needs to
persist. The next cohort job finished in 8:09. (Adding `--batch-size` and
`--reader-threads` first made the preload instant but did not fix the import; the
storage location was the real cause.)

**REF would have silently fallen back to the smoke reference.** Found before any
job ran. `run_pipeline.sh` reads `REF="${REF:-smoke/smoke.fa}"`, and the first
`slurm.env` did not set REF at all. So on Explorer the pipeline would have used a
relative smoke path that does not exist there. I checked by sourcing `slurm.env`
and echoing `$REF` from a child shell, which printed an empty value. Fix: `slurm.env`
now `export`s absolute REF and REGION. The same child-shell check then printed the
Explorer paths. The single-sample `srun` test confirmed the real reference loaded
before I submitted the array.
