# RESOURCES.md — what I asked for, what I measured, what I set

Explorer, partition `short`, the eight-sample cohort (`chr20:1-10,000,000`),
course conda environment. Every number below is from `sacct` or from a timed run
I submitted.

## Summary

| Job | Resource | First asked | Measured | Set to | Why |
|---|---|---|---|---|---|
| per-sample | `--mem` | 12G | MaxRSS up to 19.3 GB (task 7) | **24G** (raised) | I under-asked. It only finished because Explorer does not enforce `--mem`. |
| per-sample | `--cpus-per-task` | 8 | 8 is the knee (table below) | **8** (kept) | 16 cores was 3% faster for 27% more CPU time |
| per-sample | `--time` | 02:00:00 | slowest task 00:11:14 | **00:30:00** (lowered) | about 2.7x headroom over the slowest real task |
| cohort | `--cpus-per-task` | 4 | ~1.0 core busy on average | **2** (lowered) | GenomicsDBImport and GenotypeGVCFs are mostly single-threaded |
| cohort | `--mem` | 16G | MaxRSS 2.2 GB | **4G** (lowered) | 16G reserved roughly 7x what the job used |
| cohort | `--time` | 02:00:00 | 00:08:09 | **00:30:00** (lowered) | headroom over 8 minutes, not over 2 hours |

## The array: eight samples, 8 CPUs, 12G each (what I first asked for)

```
$ sacct -j 10671974 --format=JobID,State,Elapsed,TotalCPU,MaxRSS,AllocCPUS
JobID             State    Elapsed   TotalCPU     MaxRSS  AllocCPUS
10671974_1.+  COMPLETED   00:07:50  20:55.713   8045808K          8
10671974_2.+  COMPLETED   00:08:45  21:14.948  11689824K          8
10671974_3.+  COMPLETED   00:05:24  11:25.925  12358844K          8
10671974_4.+  COMPLETED   00:08:27  22:26.812  16047392K          8
10671974_5.+  COMPLETED   00:05:44  12:57.467  17405976K          8
10671974_6.+  COMPLETED   00:07:46  21:47.910  13002236K          8
10671974_7.+  COMPLETED   00:11:14  30:35.327  20187380K          8
10671974_8.+  COMPLETED   00:11:05  25:40.987  10137468K          8
```

**Memory.** Five of the eight tasks went over the 12G I requested. Task 7 peaked
at 20,187,380K ≈ 19.3 GB. They all completed only because `--mem` is not enforced
on Explorer. On a cluster that enforces it, five tasks would have been killed. Even
here I was a bad neighbour: the scheduler placed other jobs on those nodes believing
there was room. MaxRSS is sampled every 30 s and counts file cache, so one reading
can be misleading. I sized from the largest of all twelve runs (eight array tasks plus
four core-count runs), which is 19.3 GB. **So I raised `--mem` to 24G.**

**CPU.** The number that matters is CPU time ÷ wall time. For task 1 that is
20:55 / 07:50 ≈ 2.7 cores busy on average, and task 7 is 30:35 / 11:14 ≈ 2.7.
So on average I used about 2.7 of the 8 cores I reserved. That does not mean 8 is
wrong. Alignment is the only thread-hungry stage, and it dominates the wall clock,
which is what the core-count study below measures.

**Time.** The slowest task took 00:11:14. A two-hour request made the scheduler
hold a slot for far longer than it needed. **I lowered `--time` to 00:30:00**, which
still covers a slow node.

## The core-count study (the measurement seff cannot give)

Same sample (NA12891), same input, only `--cpus-per-task` changed. Wall clock is
from a timer inside the job.

```
CORES=2  WALL_SECONDS=759
CORES=4  WALL_SECONDS=705
CORES=8  WALL_SECONDS=477
CORES=16 WALL_SECONDS=463

$ sacct -j 10673145,10673146,10673147,10673148 --format=JobID,State,Elapsed,TotalCPU,MaxRSS,AllocCPUS
10673145.ba+  COMPLETED   00:12:51  19:48.172  16301584K          2
10673146.ba+  COMPLETED   00:12:07  30:46.119   8559888K          4
10673147.ba+  COMPLETED   00:08:06  21:56.612  12761936K          8
10673148.ba+  COMPLETED   00:08:05  27:55.865  12023092K         16
```

| --cpus-per-task | wall (s) | vs. previous | CPU time |
|---|---|---|---|
| 2  | 759 | —          | 19:48 |
| 4  | 705 | 7% faster  | 30:46 |
| 8  | 477 | 32% faster | 21:56 |
| 16 | 463 | 3% faster  | 27:55 |

Going from 4 to 8 cores saved almost 4 minutes. Going from 8 to 16 saved 14 seconds
and burned 27% more CPU time, because the extra cores were mostly idle. More cores
past 8 is not faster, just more expensive for the cluster. **Therefore I kept
`--cpus-per-task=8`.** `THREADS` comes from `SLURM_CPUS_PER_TASK`, so the tools
follow this number automatically.

Caveat: each core count is one run, on different nodes (the 4- and 16-core runs
shared node c0281), so each figure carries some noise. The 4→8 gap of 228 s is far
larger than any node-to-node variation I saw across the eight array tasks, so the
decision does not depend on the noise. The 2→4 step is small enough that I would not
rely on it without repeats.

## The cohort job: 4 CPUs, 16G (what I first asked for)

```
$ sacct -j 10672822 --format=JobID,State,Elapsed,TotalCPU,MaxRSS,AllocCPUS
10672822.ba+  COMPLETED   00:08:09  08:16.806   2276408K          4
```

CPU time 08:16 over wall 08:09 is about 1.0 core busy out of 4, and MaxRSS was
2.2 GB out of 16G. Joint genotyping here is essentially single-threaded, which is
also why it is one job rather than an array. **So I lowered the cohort job to 2 CPUs
(one to spare for `--reader-threads`), 4G, and 00:30:00.**

## What the array bought

The eight samples ran at once on eight nodes (c0587, c0607, c0641, c0658, c0668,
c0678, c0683, c3015). The whole array finished in the time of its slowest task,
00:11:14. Run one after another, the same eight tasks add up to about 66 minutes
of wall clock.

## One storage finding

The first cohort job spent 33 minutes in GenomicsDBImport because its workspace was
on shared `/home`. Moving the workspace to node-local `$TMPDIR` brought the whole
cohort job down to 00:08:09. Details are in TROUBLESHOOTING.md.
