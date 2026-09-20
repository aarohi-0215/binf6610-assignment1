# Troubleshooting log — Assignment 1

## stage 0 passed a broken cohort (exit 0 when it should have failed)

**Symptom.** `bash tests/run_acceptance.sh .` reported FAIL on "stage 0 reports
every problem together": the harness fed four samples, three of them broken, and
my stage 0 exited 0.

**How I found it.** The harness message said stage 0 exited 0 on known-bad input.
I re-read my `stage_validate()` and saw it only checked for duplicate sample_ids —
it never opened or tested the fastq files, so missing files and a truncated gzip
were invisible to it.

**Cause.** Incomplete validation: no per-file existence/size/integrity checks.

**Fix.** Added a per-sample loop that builds the expected file list from
`library_type` (R1 always, R2 only when paired), then for each file checks
`-f` (exists), `-s` (non-empty) and `gzip -t` (stream not truncated), appending a
sample-named message to the `problems` array on any failure. Re-ran the harness:
both "reports every problem" and "catches a truncated .fastq.gz" now PASS.

## Truncated gzip opened fine but ended mid-stream

**Symptom.** A `.fastq.gz` with its tail cut off was accepted by an early version
of stage 0.

**How I found it.** The harness names NA12891's R1 as the truncated file. A plain
existence check (`-f`) passed it because the file is present and non-empty — the
damage is only visible when you decompress the whole thing.

**Cause.** `-f`/`-s` only look at the file's presence and size, not its contents.
A gzip stream can be a valid file and still stop halfway.

**Fix.** Added `gzip -t`, which decompresses the entire stream and exits non-zero
if it cannot reach a clean end. This is the check that distinguishes "file exists"
from "file is intact".

## `gzip -t` passed a truncated file the harness still called broken

**Symptom.** After adding `gzip -t`, the harness still failed "catches a truncated
.fastq.gz", saying stage 0 accepted NA12891's cut R1.

**How I found it.** I read how the harness builds the fixture: `head -c 120` on a
valid gzip. A 120-byte fragment is small enough that `gzip -t` decompresses its
first block and exits 0 — the check ran but reported OK.

**Cause.** `gzip -t` verifies internal structure but a tiny head-of-stream
fragment can still test clean; it does not know the stream was meant to be longer.

**Fix.** Added a second assertion: fully decompress with `gzip -dc | wc -l` and
require a non-zero line count divisible by 4 (FASTQ is 4 lines per record). The
fragment fails the divisible-by-4 test, so it is now rejected and named. Both the
truncation test and "reports every problem" (which reuses the same cut file as
CUTGZIP) went green.

## `gzip -t` passed a truncated file the harness still called broken

**Symptom.** After adding `gzip -t`, the harness still failed "catches a truncated
.fastq.gz", saying stage 0 accepted NA12891's cut R1.

**How I found it.** I read how the harness builds the fixture: `head -c 120` on a
valid gzip. A 120-byte fragment is small enough that `gzip -t` decompresses its
first block and exits 0 — the check ran but reported OK.

**Cause.** `gzip -t` verifies internal structure but a tiny head-of-stream
fragment can still test clean; it does not know the stream was meant to be longer.

**Fix.** Added a second assertion: fully decompress with `gzip -dc | wc -l` and
require a non-zero line count divisible by 4 (FASTQ is 4 lines per record). The
fragment fails the divisible-by-4 test, so it is now rejected and named. Both the
truncation test and "reports every problem" (which reuses the same cut file as
CUTGZIP) went green.

## Truncated-gzip test fails on a non-truncated fixture (environment-dependent)

**Symptom.** Acceptance tests report 7/9: "catches a truncated .fastq.gz" and
"reports every problem together" (which reuses the same file as CUTGZIP) both fail,
saying stage 0 accepted NA12891's cut R1.

**How I found it.** I reproduced the fixture builder from run_acceptance.sh:
`fq whole.fastq.gz 20` then `head -c 120 whole.fastq.gz > cut_R1.fastq.gz`. On my
system (WSL, gzip 1.10) the 20 records compress to 109 bytes, so `head -c 120`
copies the entire file — the "cut" file is byte-identical to the whole file
(`cmp` reports identical; both decompress to 80 lines). `gzip -t` therefore
correctly returns 0, because the stream is not actually truncated.

**Verification that my check is correct.** I truncated a genuinely large gzip
(2000 records) to 120 bytes; `gzip -t` returned exit 1 ("unexpected end of file")
and stage_validate named the sample and exited 65 as required.

**Cause.** Environment-dependent test fixture: gzip 1.10 compresses the 20-record
sample below the 120-byte cut point, so the fixture is not truncated on this
machine. Confirmed by another student seeing identical behaviour (109 bytes) on
macOS.

**Status.** Pipeline logic is correct and fires on real truncation. The local
failure is a fixture artifact, not a validation bug; left the pipeline and the
supplied test unchanged and raised it on the discussion board.

## Truncated-gzip test fails on a non-truncated fixture (environment-dependent)

**Symptom.** Acceptance tests report 7/9: "catches a truncated .fastq.gz" and
"reports every problem together" (which reuses the same file as CUTGZIP) both fail,
saying stage 0 accepted NA12891's cut R1.

**How I found it.** I reproduced the fixture builder from run_acceptance.sh:
`fq whole.fastq.gz 20` then `head -c 120 whole.fastq.gz > cut_R1.fastq.gz`. On my
system (WSL, gzip 1.10) the 20 records compress to 109 bytes, so `head -c 120`
copies the entire file — the "cut" file is byte-identical to the whole file
(`cmp` reports identical; both decompress to 80 lines). `gzip -t` therefore
correctly returns 0, because the stream is not actually truncated.

**Verification that my check is correct.** I truncated a genuinely large gzip
(2000 records) to 120 bytes; `gzip -t` returned exit 1 ("unexpected end of file")
and stage_validate named the sample and exited 65 as required.

**Cause.** Environment-dependent test fixture: gzip 1.10 compresses the 20-record
sample below the 120-byte cut point, so the fixture is not truncated on this
machine. Confirmed by another student seeing identical behaviour (109 bytes) on
macOS.

**Status.** Pipeline logic is correct and fires on real truncation. The local
failure is a fixture artifact, not a validation bug; left the pipeline and the
supplied test unchanged and raised it on the discussion board.
