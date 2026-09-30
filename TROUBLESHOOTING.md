# TROUBLESHOOTING.md: Assignment 2 (the pipeline as a job array)

**Use of AI assistance.** I used an AI assistant (Claude) to help understand the Slurm scripts and to reason about the failures below. Every `sacct` line and log line is pasted from my terminal.

The data is small enough that nothing fails by itself, so I broke the current pipeline four times on purpose. Each breakage used a copy of `slurm/01_persample.sbatch` or `slurm/02_cohort.sbatch` kept in `~/w2ts` on Explorer, outside the repository, and each wrote to its own folder under `/scratch`, so the submitted run in `/scratch/<user>/w2-run` was never touched. All were submitted from `slurm/` with `-p courses -A binf6610.202710`.

## 1. `--time=00:02:00` → TIMEOUT

**Command.** The per-sample script with `--time=00:02:00`, one sample (NA12878), which needs about 8 minutes:

```
sbatch -p courses -A binf6610.202710 --array=1 ~/w2ts/break1-timeout.sbatch
```

**What happened.**

```
10711368_1   vc-persample   TIMEOUT   00:02:03   0:0   8

===== stage 3 : align =====
slurmstepd: error: *** JOB 10711368 ON c0617 CANCELLED AT 2026-09-30T16:00:24 DUE TO TIME LIMIT ***
```

It stopped inside stage 3. Left on disk: the FastQC reports, both trimmed FASTQs, and in `align/` only `NA12878.bwa.log` and `NA12878.sort.log`. There was no BAM: `samtools sort` writes its output only after it has read all its input, and the job was killed first. `--time` is the limit Explorer enforces, and a folder with logs in it is not a finished stage.

## 2. One task exits 1, with the cohort job on `afterok` → cohort CANCELLED

**Command.** A copy of the per-sample script with `exit 1` right after it reads `conf/slurm.env`, and the real cohort script, submitted the way `submit.sh` submits it:

```
F=$(sbatch --parsable -p courses -A binf6610.202710 --array=2 ~/w2ts/break2-fail.sbatch)
sbatch -p courses -A binf6610.202710 --dependency=afterok:$F --kill-on-invalid-dep=yes ~/w2ts/break2-cohort.sbatch
```

**What happened.**

```
10711369_2   vc-persample   FAILED      00:00:01   1:0
task 2: failing on purpose

10711370     vc-cohort      CANCELLED   Reason=Dependency
```

The task failed, `afterok` could no longer be met, and the cohort job was cancelled with Reason `Dependency` without ever starting. Under `afterany` it would have started and joint-genotyped whatever samples had finished: a cohort VCF of the right shape, a sample short, and nothing saying so.

## 3. `--array=1-9` against the eight-row samplesheet

**Command.**

```
sbatch -p courses -A binf6610.202710 --array=1-9 ~/w2ts/break3-range.sbatch
```

**What happened.**

```
10711371_1 ... 10711371_8   vc-persample   COMPLETED   (05:07 to 11:23)
10711371_9                  vc-persample   FAILED      00:00:07   65:0

task 9: no row 10 in /courses/BINF6610.202710/data/samplesheet-variant8.csv (out-of-range array index), refusing.
```

Tasks 1 to 8 ran the eight samples and wrote eight GVCFs. Task 9 found no row 10 in the samplesheet and refused in 7 seconds, with exit 65: that is the `[[ -z "${SAMPLE}" ]]` guard in `slurm/01_persample.sbatch`.

**Without the guard,** task 9 would have called `run_sample.sh` with an empty sample name. That is the one failure of the four that can succeed while being wrong: nine COMPLETED tasks and eight results, with nothing in `squeue` or `sacct` saying which task did nothing.

## 4. `scancel` mid-write, then resubmit

**Command.** A copy of the per-sample script, one sample (NA12878), cancelled 45 seconds into stage 3, while `bwa mem` was piping into `samtools sort`, then the same script submitted again:

```
J=$(sbatch --parsable -p courses -A binf6610.202710 --array=1 ~/w2ts/break4-scancel.sbatch)
scancel $J
sbatch -p courses -A binf6610.202710 --array=1 ~/w2ts/break4-scancel.sbatch
```

**What happened.**

```
10711384_1   vc-persample   CANCELLED by user   00:01:58
===== stage 3 : align =====
slurmstepd: error: *** JOB 10711384 ON c0648 CANCELLED AT 2026-09-30T16:00:23 ***

10711401_1   vc-persample   COMPLETED   00:08:13
align: NA12878 OK (2447146 mapped)
postprocess: NA12878 OK
quantify: NA12878 OK
```

**Did the rerun trust what was left behind? No.** It ran every stage again, trimming and aligning from the start (2,447,146 reads mapped, the same as the submitted run), and overwrote each output. My stages have no resume logic: none of them checks whether its output already exists, so a rerun can never build on a half-written file. The cost is that it also redoes work that had finished; skipping finished stages safely would need each output written under a temporary name and renamed only when complete.
