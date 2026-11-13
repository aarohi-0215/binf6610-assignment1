# BINF6610: a database of the variant-call runs

Assignment 9. The runs of the variant-call pipeline from weeks 4 to 6, loaded into one SQLite database, so one query answers a question about every run at once.

| Folder | The run |
|---|---|
| `smoke-run-nf/` | week 4, Nextflow, laptop, the smoke dataset (3 samples) |
| `cluster-run-nf/` | week 4, Nextflow, Explorer, the cohort (8 samples) |
| `smoke-run-smk/` | week 5, Snakemake, laptop, the smoke dataset (3 samples) |
| `cluster-run-smk/` | week 5, Snakemake, Explorer, the cohort (8 samples) |
| `aws-run-nf/` | week 6, Nextflow on AWS Batch, the smoke dataset (3 samples) |

`db/schema.sql` makes the six tables (pipelines, runs, samples, run_samples, variants, outputs), with keys that refuse a repeated run, a row pointing at something that does not exist, and the same sample twice in one run. `db/load.py` loads the sample metadata (`db/variant-call-cohort.tsv`) and each run folder, each run whole or not at all, and skips a run that is already loaded. `db/queries/q1.sql` to `q6.sql` answer the six questions.

Build and query it from the top of the repository:

    sqlite3 runs.db < db/schema.sql
    python3 db/load.py runs.db db/variant-call-cohort.tsv smoke-run-nf cluster-run-nf smoke-run-smk cluster-run-smk aws-run-nf
    sqlite3 -header -column runs.db < db/queries/q1.sql

`runs.db` itself is not committed. Each earlier assignment is on its own branch: `master` (1), `week2` to `week6` (2 to 6) and `week8` (8, CI and CD); assignment 7 was a quiz.
