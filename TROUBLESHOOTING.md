# TROUBLESHOOTING.md: Assignment 3 (the pipeline in an image)

**Use of AI assistance.** I used an AI assistant (Claude) to help understand the image creation and the job-script changes and to reason about the failures below. I ran every command myself, on my laptop or on Explorer, and every output is pasted from my terminal. The Assignment 2 log is on the `week2` branch.

The four failures were caused on purpose. The throwaway files lived in `~/w3-break1/` on my laptop and `~/w3ts/` on Explorer, outside the repository, and are not committed. Breakages 2 and 3 used copies of `slurm/01_persample.sbatch`, each writing to its own folder under `/scratch`, and were submitted from `slurm/` with `-p courses -A binf6610.202710`.

## 1. An unpinned recipe, rebuilt a day later

**Command.** In `~/w3-break1/`, outside the repository (an unpinned `FROM` inside it would fail the pinning test), a two-line Dockerfile:

```
FROM ubuntu
RUN apt-get update && apt-get install -y curl
```

```
docker build -t break1:day1 .                         # Tue Sep 29 22:35:59 EDT 2026
docker run --rm break1:day1 dpkg -l > day1-dpkg.txt

docker build --pull --no-cache -t break1:day2 .       # Wed Sep 30 21:53:37 EDT 2026
docker run --rm break1:day2 dpkg -l > day2-dpkg.txt
diff day1-dpkg.txt day2-dpkg.txt
```

The two builds were 23 hours 18 minutes apart.

**Output.**

```
ubuntu   latest   sha256:da6fc2be547864451aa253836dd926da33623312df4a9a243e35dc877c378a78   (day 1)
ubuntu   latest   sha256:da6fc2be547864451aa253836dd926da33623312df4a9a243e35dc877c378a78   (day 2)

image ID, day 1: sha256:ae4daa553a9dbb31c587c9bdb3d424529159663a638fa30413ac81978ab1f472
image ID, day 2: sha256:faa8b8071bee610296cbbbc637ca00e1c5a7a9166e5ebc106abfc9919e7e6b5b

  122 day1-dpkg.txt
  122 day2-dpkg.txt

109c109
< ii  openssl   3.5.5-1ubuntu3.5   amd64   Secure Sockets Layer toolkit - cryptographic utility
---
> ii  openssl   3.5.5-1ubuntu3.6   amd64   Secure Sockets Layer toolkit - cryptographic utility
```

The base image did not move: `ubuntu:latest` had the same digest on both days. What moved was the package archive. `apt-get update` on day 2 found a newer `openssl` (`3.5.5-1ubuntu3.6` instead of `3.5.5-1ubuntu3.5`), so the same unchanged recipe produced a different image with different software inside, and nothing in the recipe says so. The two images have different IDs and the same number of packages, so only the package list shows the change. It took one day for one package; the longer the gap, the more lines a diff like this gets.

**Fix.** Pin everything the recipe installs. My `containers/Dockerfile` starts from a tagged base (`mambaorg/micromamba:2.0.5-ubuntu24.04`), installs nothing from the OS package manager, and gives every tool an `=version`. Anything still left to build day is recorded by the pushed image's digest in `IMAGE.md`, which returns the exact image whatever the archives have done since.

## 2. `--bind` removed from one job script

**Command.** A copy of `slurm/01_persample.sbatch` with the `--bind /courses/BINF6610.202710,/scratch/${USER}` line deleted, one sample:

```
sbatch -p courses -A binf6610.202710 --array=1 ~/w3ts/break2-nobind.sbatch
```

**Output.**

```
10712934_1   FAILED   00:01:30   65:0   8

task 1 -> sample NA12878
awk: cannot open "/courses/BINF6610.202710/data/samplesheet-variant8.csv" (No such file or directory)
ERROR: run_sample.sh: no sample named 'NA12878' in /courses/BINF6610.202710/data/samplesheet-variant8.csv
```

It stopped before stage 0, in `run_sample.sh`'s check that the sample is in the samplesheet, with exit code 65. **The path the container could not see was `/courses/BINF6610.202710`**, which holds the samplesheet, the FASTQs and the reference. Without `--bind`, Apptainer shows the container only my home directory, `/tmp` and the directory the job ran from.

The last line of that log is misleading: NA12878 is in the samplesheet. The job script read its name from that same file, outside the container, a line earlier. To be sure, I ran the same lookup in the image with and without the bind:

```
outside the container, first sample in the sheet: NA12878
--- inside the image, with --bind ---
/courses/BINF6610.202710
NA12878,affected,1,paired,/courses/BINF6610.202710/data/fastq-variant/NA12878_R1.fastq.gz,/courses/BINF6610.202710/data/fastq-variant/NA12878_R2.fastq.gz
rows exit: 0
--- inside the image, without --bind ---
ls: cannot access '/courses/BINF6610.202710': No such file or directory
awk: cannot open "/courses/BINF6610.202710/data/samplesheet-variant8.csv" (No such file or directory)
```

So the sample was never missing. The samplesheet could not be opened at all, the lookup returned nothing, and the check reported that as a missing sample. The error you read first is a consequence; the cause is the line above it.

**Fix.** `--bind /courses/BINF6610.202710,/scratch/${USER}` on the `apptainer exec` line, as in both committed job scripts.

## 3. `--env THREADS` removed from one job script

**Command.** A copy of `slurm/01_persample.sbatch` with the `--env THREADS="${THREADS}"` line deleted, one sample, on a job holding 8 cores:

```
sbatch -p courses -A binf6610.202710 --array=1 ~/w3ts/break3-nothreads.sbatch
```

**Output.**

```
10712947_1   COMPLETED   00:10:44   0:0   8

[main] CMD: bwa mem -t 4 -R @RG\tID:NA12878 ...

IntelPairHmm - Available threads: 8
IntelPairHmm - Requested threads: 4
```

Nothing failed. The job completed with exit 0 while holding 8 cores, and `bwa mem` ran with `-t 4`. Under `--cleanenv` the job's `THREADS=8` never reached the container, so the pipeline used the default in `lib/common.sh`, `THREADS=${THREADS:-4}`, and half the cores sat idle. Only the log shows it. In the committed run, with the `--env` line, every sample's log reads `bwa mem -t 8`. GATK's `Requested threads: 4` is the same in both runs, because my pipeline never passes a thread count to HaplotypeCaller and GATK uses its own default of 4; `bwa`'s `-t` is where the missing variable shows.

**Fix.** `--env THREADS="${THREADS}"` on the `apptainer exec` line, as in both committed job scripts.

## 4. An arm64 image on Explorer

**Command.** On a compute node:

```
apptainer pull --arch arm64 arm.sif docker://ubuntu:24.04
apptainer exec arm.sif uname -m
```

**Output.**

```
INFO:    Creating SIF file...
pull exit: 0
FATAL:   While checking container encryption: could not open image /scratch/deshpande.aaro/arm.sif: the image's architecture (arm64) could not run on the host's (amd64)
run exit: 255
```

The pull succeeded: Apptainer downloads and converts an image for whatever architecture it is asked for. The failure appears only when something runs, and the message names both architectures. An arm64 image built on an Apple laptop without `--platform` would pass every step on the laptop, push, and pull, and fail only here.

**Fix.** Build with `docker build --platform linux/amd64`, and check with `docker image inspect --format '{{.Architecture}}'` before pushing. My image reports `amd64`.
