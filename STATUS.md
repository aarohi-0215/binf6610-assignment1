# BINF6610 Assignment 1 — where I am

## Local test result: 7/9 passing
Run to re-check:  bash tests/run_acceptance.sh .

## PASSING (7)
Donor 3-rep1, duplicate sample_id, single-end from library_type,
set -euo pipefail, stderr, no sample named in code, TROUBLESHOOTING.md present.

## FAILING (2) — NOT my bug, waiting on TA
- "catches a truncated .fastq.gz"
- "reports every problem together" (reuses same CUTGZIP fixture)
Cause: gzip 1.10 compresses the 20-record fixture to 109 bytes, so `head -c 120`
does NOT truncate it. Verified my gzip -t check DOES fire on a real truncation
(2000-record file -> exit 1). Environment-dependent fixture bug. Another student
(Meng) hit the same on macOS. Following the discussion-board thread; not posting
a duplicate. Pipeline + supplied test left unchanged on purpose.

## DONE
- run_pipeline.sh: driver + full stage_validate (stage 0). Other stages are stubs.
- samplesheet.csv (8 samples, NA12892 & NA12003 single-end)
- .gitignore, TROUBLESHOOTING.md
- git init + first commit done locally

## TODO to submit
1. Wait for TA reply on the gzip fixture.
2. conf/pipeline.env  (needs: REF_DIR, THREADS, calling region chr20:1-10000000)
3. Push to GitHub, submit the repo URL on Canvas.

## Notes
- Develop against dev/ slice, not Explorer data (that's Week 2).
- gzip -t + decompress check is correct; don't "fix" it to satisfy the broken fixture.
