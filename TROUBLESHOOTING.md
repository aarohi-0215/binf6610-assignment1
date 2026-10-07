# TROUBLESHOOTING.md: Assignment 4 (the pipeline in Nextflow)

**Use of AI assistance.** I used an AI assistant (Claude) to help write the Nextflow processes and to reason about the failures below. I ran every command myself, on my laptop or on Explorer, and every output is pasted from my terminal. The failures of weeks 1 to 3 are on the `master`, `week2` and `week3` branches.

## 1. A smoke run stopped halfway, then `-resume`

**Command.** A fresh laptop run, stopped 80 seconds in, then the same command with `-resume`:

```
timeout -s INT 80 nextflow run main.nf -profile docker -ansi-log false \
    --samplesheet smoke/samplesheet.csv --ref smoke/smoke.fa --region smoke_1mb
nextflow run main.nf -profile docker -resume -ansi-log false \
    --samplesheet smoke/samplesheet.csv --ref smoke/smoke.fa --region smoke_1mb
```

`timeout -s INT` sends SIGINT, the signal Ctrl-C sends. Pressing Ctrl-C by hand twice came too late: both runs finished first, the whole pipeline takes 3 minutes.

**Output.** The interrupted run, `grave_boltzmann`:

```
[e2/b59c2f] Submitted process > HAPLOTYPECALLER (smoke_03)
WARN: Killing running tasks (1)
exit: 124
grave_boltzmann   1m 24s   ERR
```

The `-resume` run, `peaceful_celsius`:

```
[47/131c7a] Cached process > VALIDATE
[5f/856d53] Cached process > FASTQC (smoke_01)        ... and the other two FASTQC
[c9/a35701] Cached process > FASTP (smoke_01)         ... and the other two FASTP
[8a/12967c] Cached process > BWA_MEM (smoke_01)       ... and the other two BWA_MEM
[19/55b269] Cached process > MARKDUPLICATES (smoke_01) ... and the other two MARKDUPLICATES
[e3/fb113b] Submitted process > HAPLOTYPECALLER (smoke_01)
[92/ac1c4b] Submitted process > HAPLOTYPECALLER (smoke_03)
[57/2f8e7e] Submitted process > HAPLOTYPECALLER (smoke_02)
[cd/440b09] Submitted process > MULTIQC
[3b/e45a0f] Submitted process > JOINT_GENOTYPE
[c1/cb5f3a] Submitted process > FILTER
[c5/c00394] Submitted process > PUBLISH
cached: 13   ran again: 7
```

**Cached:** the 13 tasks that had finished before the stop: VALIDATE and all three samples' FASTQC, FASTP, BWA_MEM and MARKDUPLICATES. **Ran again:** HaplotypeCaller for smoke_03, which was killed while running, the two HaplotypeCaller tasks that had not started, and the four steps after them. The half-finished HaplotypeCaller task was not trusted: a task is reused only when it finished. PUBLISH runs on every run in any case, because `publish.nf` sets `cache false`. Before this, a `-resume` of a run that had finished cached 19 of the 20 tasks and took 11 seconds instead of 3 minutes 28 seconds.

**Fix.** Nothing to fix: `-resume` on the same command carried on from where the run stopped.

## 2. The reference as a queue channel

**Command.** In `main.nf`, the stage-3 call only:

```
BWA_MEM(FASTP.out.reads, channel.fromPath(params.ref), ref_index)
```

then the smoke run with `-resume`, its results in a folder of their own (`--outdir /tmp/w4-break2`).

**Output.**

```
[e2/6434c3] Cached process > BWA_MEM (smoke_03)
[39/0e97de] Cached process > MARKDUPLICATES (smoke_03)
[92/ac1c4b] Cached process > HAPLOTYPECALLER (smoke_03)
[5c/b9a812] Submitted process > JOINT_GENOTYPE
[f2/1cdb2f] Submitted process > FILTER
[37/a9b6d5] Submitted process > PUBLISH
exit: 0
samples in the VCF: smoke_03
```

**BWA_MEM ran for one sample of three, and nothing stopped the run.** `channel.fromPath` makes a queue channel holding one item, the reference. BWA_MEM paired it with the first sample to arrive, smoke_03, and no reference was left for smoke_01 and smoke_02, so they were never aligned. Everything after it ran on that one sample: the run exited 0, and the cohort VCF has a single sample column. Its BWA_MEM task was even cached, because its inputs were the same files as in the earlier run.

**Fix.** The reference as a value channel, `ref = file(params.ref)`, which every sample reads.

## 3. The backslash taken off `\$(…)`

**Command.** In `modules/markduplicates.nf`,

```
reads=\$(samtools view -c ${meta.id}.markdup.bam)
```

became `reads=$(samtools view -c ${meta.id}.markdup.bam)`, then the smoke run with `-resume`.

**Output.** Nextflow started, MarkDuplicates ran, and the task failed afterwards:

```
Tool returned:
0
.command.sh: line 7: syntax error near unexpected token `)'
Work dir:
  /home/aaroubu/binf6610/assignment1/work/7e/69f50e24dc9a4d7b2e73fc7c363845
```

In that work folder, `.command.sh`:

```
samtools index smoke_01.markdup.bam
reads=smoke_01samtools view -c smoke_01.markdup.bam)
(( reads > 0 )) || { echo "markduplicates:  has no reads" >&2; exit 1; }
```

`.command.err` ends with the same `syntax error near unexpected token ')'`, and `.exitcode` is `2`. `bash .command.run` in that folder ran the task again in its container: MarkDuplicates finished, then the same syntax error, exit 2.

Without the backslash, Nextflow read the `$(` itself instead of passing it to bash. The `$(` disappeared, the sample name landed in front of `samtools`, a lone `)` was left behind, and the sample name in the next line came out empty. Bash stopped on that line. This is unlike the brief's `\$n` example, which stops Nextflow before any task runs: here the run started, and the tool ran, before the script failed.

**Fix.** Put the backslash back. Commands with many `$` signs are in scripts in `bin/` (`align.sh`, `joint_genotype.sh`, `variants_table.sh`, `validate_samplesheet.sh`), where bash reads them as written.

## 4. `time = '2m'` for HAPLOTYPECALLER on the first Explorer run

**Command.** In the `explorer` profile, HAPLOTYPECALLER given a block of its own with `time = '2m'` (BWA_MEM kept `1h`), then `sbatch slurm/nextflow.sbatch`: head job 10853480.

**Output.** From the head job's log:

```
ERROR ~ Error executing process > 'HAPLOTYPECALLER (NA12878)'
Caused by:
  Process `HAPLOTYPECALLER (NA12878)` terminated with an error exit status (140)
```

GATK's progress for NA12878 had reached `chr20:2386358` when it stopped. From `sacct`:

```
             JobID                          JobName            State    Elapsed  Timelimit ExitCode
          10853553     nf-HAPLOTYPECALLER_(NA12878)           FAILED   00:01:54   00:02:00     12:0
          10853565     nf-HAPLOTYPECALLER_(NA12892) CANCELLED by 10+   00:01:39   00:02:00      0:0
          10853566     nf-HAPLOTYPECALLER_(NA10851)           FAILED   00:01:35   00:02:00     12:0
          10853568     nf-HAPLOTYPECALLER_(NA07357)           FAILED   00:01:15   00:02:00     12:0
          10853570     nf-HAPLOTYPECALLER_(NA12891) CANCELLED by 10+   00:01:07   00:02:00      0:0
          10853583     nf-HAPLOTYPECALLER_(NA12003) CANCELLED by 10+   00:00:02   00:02:00      0:0
10853480        nf-head     FAILED   00:07:13   04:00:00      1:0
```

**No job shows TIMEOUT.** Every task's job is submitted with `#SBATCH --signal B:USR2@30`, so Slurm sends SIGUSR2 shortly before the two-minute limit and Nextflow stops the task itself. Exit status 140 is 128 + 12, and 12 is SIGUSR2; `sacct` records exit code 12 for the tasks stopped that way, every one of them with an Elapsed under its Timelimit. The jobs marked `CANCELLED by` were cancelled by Nextflow when it ended the run after the first failure.

**Fix.** `time = '1h'` back, as in the committed `nextflow.config`, and the same `sbatch` again: head job 10878890, COMPLETED in 22 minutes 13 seconds. `-resume` reused the 30 tasks that had finished and ran 15, among them all eight HaplotypeCaller tasks.

## A problem I did not cause: two images converted at once

My first Explorer submission, head job 10852256, failed after 5 minutes 17 seconds, before any analysis task, at `FASTQC (1)`:

```
Failed to pull singularity image
  command: apptainer pull --name quay.io-biocontainers-fastqc-0.12.1--hdfd78af_0.img.pulling... docker://quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0
  status : 255
  FATAL: While making image from oci registry: error fetching image to cache: while building SIF from layers:
         conveyor failed to get: while getting config: no descriptor found for reference "73c60af0c4748c756d33d4e3b6852f775c0d65abbab26571a51d636a17c73761"
```

Nextflow had started converting the fastp and the fastqc images in the same second, and both conversions use one Apptainer cache. The download had finished; the conversion that assembles the image failed. **Fix.** I converted the six images one at a time in a job of their own, into `/scratch/<user>/nxf-apptainer/` under the file names Nextflow looks for, and the next run used them without converting anything.
