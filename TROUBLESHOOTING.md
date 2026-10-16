# TROUBLESHOOTING.md: Assignment 5 (the pipeline in Snakemake)

## 1. A smoke run stopped halfway, then the same command

**Command.** On the laptop, a smoke run from empty outputs, stopped 25 seconds in with SIGINT, the signal Ctrl-C sends, then the same command again:

```
timeout -s INT 25 snakemake --profile profiles/laptop --config samplesheet=... ref=... region=smoke_1mb
snakemake --profile profiles/laptop --config samplesheet=... ref=... region=smoke_1mb
```

**What Snakemake said.** The stopped run:

```
9 of 21 steps (43%) done
Terminating processes on user request, this might take some time.
CalledProcessError in file ".../Snakefile", line 167:
Error in rule markduplicates:
    log: logs/markduplicates/smoke_02.log (check log file(s) for error details)
Error in rule markduplicates:
    log: logs/markduplicates/smoke_01.log (check log file(s) for error details)
```

Nine jobs had finished. The two MarkDuplicates jobs running at that moment were stopped, and Snakemake recorded them as failed.

**The same command** started without complaint and ran the 12 jobs that had not finished:

```
bwa_mem                1
markduplicates         3
haplotypecaller        3
multiqc                1
joint_genotype         1
filter                 1
publish                1
all                    1
total                 12
12 of 12 steps (100%) done
```

**I aimed at `IncompleteFilesException` and the option `--rerun-incomplete`, and got neither.** Stopped with Ctrl-C, Snakemake terminated its jobs itself and treated them as failed jobs, whose outputs it does not keep, so nothing was left marked incomplete and no option was needed: the next run made those files again. The session's slides say the same: `IncompleteFilesException`, with its advice to add `--rerun-incomplete`, comes when Snakemake is killed outright and cannot clean up, as when the terminal is closed. Run afterwards with `--rerun-incomplete`, Snakemake found only `publish` and `all` to run, the two rules that run every time.

**Fix.** Nothing to fix: the same command carried on from the nine finished jobs.

## 2. The stage-3 log without `{sample}`

**Command.** In the Snakefile, the `log:` of `bwa_mem` changed from `"logs/bwa_mem/{sample}.log"` to `"logs/bwa_mem.log"`, then:

```
snakemake --profile profiles/laptop -n --config samplesheet=... ref=... region=smoke_1mb
```

**Output.**

```
RuleException in file "/home/aaroubu/binf6610/assignment1/Snakefile", line 135:
Not all output, log and benchmark files of rule bwa_mem contain the same wildcards. This is crucial though, in order to avoid that two or more jobs write to the same file.
```

**Why Snakemake refuses it.** `bwa_mem` runs once per sample, and each job is told its own file names by filling `{sample}` into the output and log patterns. A log without `{sample}` names the same file for every sample, so the three jobs, eight on Explorer, would all write into one log at once. Snakemake checks this when it reads the Snakefile and stops before planning any job.

**Fix.** `log: "logs/bwa_mem/{sample}.log"`, as in the committed Snakefile.

## 3. The two `wildcard_constraints:` removed

**Command.** Both `wildcard_constraints:` blocks deleted, from `fastp_paired` and from `fastp_single`, then `snakemake -n` as above.

**Output.**

```
AmbiguousRuleException:
Rules fastp_single and fastp_paired are ambiguous for the file work/trim/smoke_01_R1.trim.fastq.gz.
Consider starting rule output with a unique prefix, constrain your wildcards, or use the ruleorder directive.
Wildcards:
     fastp_single: sample=smoke_01
     fastp_paired: sample=smoke_01
Expected input files:
     fastp_single: .../smoke/smoke_01_R1.fastq.gz work/validate/samplesheet.csv
     fastp_paired: .../smoke/smoke_01_R1.fastq.gz .../smoke/smoke_01_R2.fastq.gz work/validate/samplesheet.csv
```

**The two rules and the file.** `fastp_paired` and `fastp_single` both name the output `work/trim/{sample}_R1.trim.fastq.gz`, so without constraints either one can make `work/trim/smoke_01_R1.trim.fastq.gz`, and Snakemake will not guess which. It even shows what each would read: the single-end rule one FASTQ, the paired rule two. With the constraints, `sample` may only be a paired sample in one rule and a single-end sample in the other, so each sample has exactly one rule.

**Fix.** Both `wildcard_constraints:` back: `sample=one_of(PAIRED)` and `sample=one_of(SINGLE)`.

## 4. No Apptainer, on the first Explorer run

**Command.** `software-deployment-method: apptainer` deleted from `profiles/explorer/profile.yaml`, then `sbatch slurm/snakemake.sbatch`: head job 11042456.

**Output.** The head job ended `FAILED` after 19 minutes 38 seconds. **`validate` finished**; its log, `logs/validate.log`, says `validate: OK, 8 samples`. **The rules that failed were `fastqc`, `fastp_paired` and `fastp_single`**, for all eight samples. The Slurm log of one of them, `.snakemake/slurm_logs/rule_fastqc/NA12878/11042561.log`:

```
Command 'set -euo pipefail;  (mkdir -p work/fastqc/NA12878 && fastqc -q -o work/fastqc/NA12878 /courses/.../NA12878_R1.fastq.gz /courses/.../NA12878_R2.fastq.gz) 2> logs/fastqc/NA12878.log' returned non-zero exit status 127.
```

The rules' own logs:

```
logs/fastqc/NA12878.log:  /usr/bin/bash: line 1: fastqc: command not found
logs/fastp/NA12878.log:   /usr/bin/bash: line 1: fastp: command not found
```

Without the line, Snakemake ignores every rule's `container:` and runs the command on the compute node itself, where `fastqc` and `fastp` are not installed. Exit status 127 is bash's "command not found". `validate` needs only `bash`, `gzip` and `awk`, which every node has, so it was the one rule that passed.

**Fix.** The line put back. Before submitting again, `snakemake -n` planned `validate` again although it had finished:

```
rule validate:
    reason: Software environment definition has changed since last execution
```

Snakemake records how each job's software was provided, and a job made without the image is not the same as one made in it, so it reruns. The next head job, 11046443, stopped at 15 of 46 steps for a reason that was not my pipeline: Slurm refused two submissions,

```
sbatch: error: Batch job submission failed: Unexpected message received
```

and the same head job submitted once more, 11051634, ran the 29 steps that were left and ended `COMPLETED` after 25 minutes 31 seconds. The logs of all three head jobs are in `cluster-run-smk/`.
