# Troubleshooting log — Assignment 1

**Use of AI assistance.** I used an AI assistant (Claude) in this
assignment: to scaffold the ten-stage pipeline structure, explain tool flags and
bash behaviour (read groups, `set -euo pipefail`, process substitution, GATK/BWA
options), and help diagnose the failures recorded below. All code was reviewed and
is understood by me; the diagnoses here reflect my own working-through of each
problem, confirmed by reading tool output and re-running the acceptance tests.

---## Stage 0 passed a broken cohort (exit 0 when it should have failed)

**Symptom.** `tests/run_acceptance.sh` failed "stage 0 reports every problem
together": four samples, three broken, but my stage 0 exited 0.

**How I found it.** The harness said stage 0 exited 0 on known-bad input. Re-reading
`stage_validate()`, I saw it only checked for duplicate sample_ids — it never opened
or tested the FASTQ files, so missing files and a corrupt gzip were invisible.

**Cause.** Incomplete validation: no per-file existence/size/integrity checks.

**Fix.** Added a per-sample loop that builds the expected file list from
`library_type` (R1 always, R2 only when paired), then checks each file with `-f`
(exists), `-s` (non-empty) and `gzip -t` (intact stream), appending a sample-named
message to the `problems` array on any failure so all problems report at once.

## A truncated .fastq.gz opened fine but ended mid-stream

**Symptom.** A `.fastq.gz` with its tail cut off was accepted by an early stage 0.

**How I found it.** A plain `-f` existence check passed it — the file is present and
non-empty; the damage only shows when you decompress the whole stream.

**Cause.** `-f`/`-s` look at presence and size, not contents. A gzip file can be
valid on disk and still stop halfway.

**Fix.** Added `gzip -t` (tests the whole stream) plus a second assertion: fully
decompress with `gzip -dc | wc -l` and require a non-zero line count divisible by 4
(FASTQ is 4 lines per record). Together these reject a truncated file and name the
sample.

## Truncated-gzip fixture was not actually truncated on my machine

**Symptom.** Even with a correct `gzip -t` check, the harness kept failing the
truncation test, saying stage 0 accepted the cut file.

**How I found it.** I reproduced the fixture builder from the harness: it made a
gzip of 20 records, then `head -c 120` on it. On my system (WSL, gzip 1.10) those
20 records compress to 109 bytes, so `head -c 120` copies the whole file — `cmp`
showed the "cut" file was byte-identical to the original, and both decompressed to
80 lines. `gzip -t` correctly returned 0 because nothing was truncated.

**Verification my check was right.** I truncated a genuinely large gzip (2000
records) to 120 bytes; `gzip -t` returned exit 1 ("unexpected end of file") and
stage_validate named the sample and exited 65.

**Cause / resolution.** Environment-dependent test fixture, not a bug in my code.
The updated harness corrects the fixture: it cuts the file at half its size and asserts the
fixture is really truncated. With the corrected harness my unchanged pipeline passes
the truncation test.

## Stage 8 (MultiQC) crashed on a NumPy binary incompatibility

**Symptom.** Stage 8 failed: "qc_report: no MultiQC report", exit 1.

**How I found it.** Read `qc_report/multiqc.log`. Past a scipy warning, the real
error was `ValueError: numpy.dtype size changed, may indicate binary
incompatibility. Expected 96 from C header, got 88`. The apt MultiQC 1.12 was built
against an older NumPy ABI; the system has NumPy 2.2.6, so MultiQC crashed on import.

**Cause.** Version conflict between the apt MultiQC and the system NumPy — the kind
of environment drift containers (week 3) are meant to eliminate.

**Fix.** Installed `multiqc==1.21` in an isolated Python venv so it uses a
compatible NumPy, and pointed stage 8 at it via a `MULTIQC` variable in
`conf/pipeline.env` (config, not code). Re-ran: stage 8 produced the HTML report and
the pipeline finished all ten stages.

## "No sample is named in the code" failed after building later stages

**Symptom.** The acceptance test "no sample is named in the code" failed.

**How I found it.** I read the test: it scans every `.sh` file (excluding `.git` and
`tests/`) for any of the eight cohort IDs. Running that same `find`, I saw two stray
`.sh` files still in the repo — the demo pipeline (`rnaseq-week1/rnaseq.sh`) and a
backup of the old tests (`tests_OLD/run_acceptance.sh`) — both full of cohort IDs.

**Cause.** Leftover files, not my pipeline. My `run_pipeline.sh` never names a
sample; the IDs live only in `samplesheet.csv`, which the test does not scan.

**Fix.** Removed both stray directories from the repo. The test passed, and the
samplesheet remains the only place a sample is named.
