# RESOURCES.md: what I asked for, what I measured, what I set

Every number below comes from runs of the current pipeline (`lib/` and `stages/`) on Explorer: partition `courses`, account `binf6610.202710`, the course samplesheet `/courses/BINF6610.202710/data/samplesheet-variant8.csv`, calling region `chr20:1-10,000,000`.

## Summary

| Job | Resource | First asked | Measured | Set to | Why |
|---|---|---|---|---|---|
| per-sample | `--mem` | 12G | MaxRSS up to 13.9 GiB; exact peak 14.3 GiB (`memory.peak`) | **24G** (raised) | 12G is below what one sample uses; 24G is about 1.7x the exact peak |
| per-sample | `--cpus-per-task` | 8 | 8 is the knee of the core-count curve | **8** (kept) | 16 cores was only 5 % faster |
| per-sample | `--time` | 02:00:00 | slowest task 00:11:17 | **00:30:00** (lowered) | about 2.7x headroom over the slowest task |
| cohort | `--cpus-per-task` | 4 | 07:56 of CPU over 07:48 of wall, about 1.0 core busy | **2** (lowered) | joint genotyping here is essentially single-threaded |
| cohort | `--mem` | 16G | MaxRSS 1.7 GiB | **4G** (lowered) | 16G reserved about 9x what the job used |
| cohort | `--time` | 02:00:00 | 00:07:48 | **00:30:00** (lowered) | headroom over 8 minutes, not over 2 hours |

"First asked" is what the job scripts requested before these measurements; the scripts now request the "Set to" column. The measurements were taken with the new requests. That does not change the memory numbers, because Explorer does not enforce `--mem`: a job uses what it needs whatever it asked for.

## The submitted run

Array `10708994` (eight samples) and cohort job `10708998`:

```
$ sacct -j 10708994,10708998 --format=JobID%16,State%12,Elapsed,TotalCPU,MaxRSS,AllocCPUS
10708994_1.batch    COMPLETED   00:08:03  19:11.479  14557908K          8
10708994_2.batch    COMPLETED   00:07:58  21:35.886   7115876K          8
10708994_3.batch    COMPLETED   00:05:07  11:28.369   6872424K          8
10708994_4.batch    COMPLETED   00:08:04  22:00.902   6886364K          8
10708994_5.batch    COMPLETED   00:05:14  12:07.674   6275308K          8
10708994_6.batch    COMPLETED   00:07:59  19:13.523   7078624K          8
10708994_7.batch    COMPLETED   00:11:17  32:24.200  14485552K          8
10708994_8.batch    COMPLETED   00:08:46  23:39.921   7970820K          8
  10708998.batch    COMPLETED   00:07:48  07:56.786   1803768K          2
```

**CPU.** CPU time divided by wall time is the number of cores that were busy: task 1 is 19:11 / 08:03, about 2.4 cores, and task 7 is 32:24 / 11:17, about 2.9 cores. Only alignment keeps many cores busy, and it is also the stage that sets the wall clock, which is what the core-count study below measures.

**Memory.** MaxRSS ranged from 6.0 to 13.9 GiB across the eight tasks. MaxRSS is sampled every 30 seconds and counts file cache, so I also measured the exact high-water mark with the two `memory.peak` lines from the brief (below): at most 15,358,078,976 bytes, 14.3 GiB. Both are above 12G, **so I raised `--mem` to 24G.**

**Time.** The slowest task took 00:11:17 and the cohort job 00:07:48, **so I lowered both `--time` requests from 02:00:00 to 00:30:00.**

**The cohort job** used about one core and 1.7 GiB, **so I lowered it from 4 cores and 16G to 2 cores and 4G.** Its stage 6 workspace is in `${TMPDIR}` on the node's own disk (`stages/06_merge.sh`).

## The core-count study

The same sample (NA12891, array task 2), the same input, only `--cpus-per-task` changed. `WALL_SECONDS` is timed inside the job around `run_sample.sh`; `MEMORY_PEAK_BYTES` is the cgroup's `memory.peak`.

```
CORES=2  WALL_SECONDS=741  MEMORY_PEAK_BYTES=11901628416
CORES=4  WALL_SECONDS=540  MEMORY_PEAK_BYTES=13405491200
CORES=8  WALL_SECONDS=450  MEMORY_PEAK_BYTES=15358078976
CORES=16 WALL_SECONDS=428  MEMORY_PEAK_BYTES=13371453440

$ sacct (the four jobs)
10711372_2   vc-persample   COMPLETED   00:13:23   0:0    2
10711373_2   vc-persample   COMPLETED   00:09:06   0:0    4
10711374_2   vc-persample   COMPLETED   00:07:45   0:0    8
10711383_2   vc-persample   COMPLETED   00:07:41   0:0   16
```

| `--cpus-per-task` | wall (s) | vs. the row above |
|---|---|---|
| 2  | 741 | |
| 4  | 540 | 27 % faster |
| 8  | 450 | 17 % faster |
| 16 | 428 | 5 % faster |

Going from 8 to 16 cores saves 22 seconds for twice the cores. **Therefore I kept `--cpus-per-task=8`.** `THREADS` comes from `SLURM_CPUS_PER_TASK`, so the tools follow this number. Each core count is one run, on whatever node Slurm gave it, so each figure carries some noise; the 8 versus 16 gap is small enough that only more runs would say whether 16 is faster at all.

## What the array bought

The eight tasks ran at the same time, and the array finished in the time of its slowest task, 00:11:17. Run one after another, the same eight tasks add up to 62 minutes.
