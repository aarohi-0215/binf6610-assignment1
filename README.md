# BINF6610: a results page for the variant-call runs

A Dash app that reads the database of the pipeline's runs and shows it. `/` lists every run, and `/results?run=<run_id>` shows one run: its samples, five plots of its sites, and the sites themselves. A click on a bar of the filter, type or Ts/Tv plot leaves only that bar's sites in the sites table.

| Folder | The run |
|---|---|
| `smoke-run-nf/` | Nextflow, laptop, the smoke dataset (3 samples) |
| `cluster-run-nf/` | Nextflow, Explorer, the cohort (8 samples) |
| `smoke-run-smk/` | Snakemake, laptop, the smoke dataset (3 samples) |
| `cluster-run-smk/` | Snakemake, Explorer, the cohort (8 samples) |
| `aws-run-nf/` | Nextflow on AWS Batch, the smoke dataset (3 samples) |

Build the database, then start the app, from the top of the repository:

    sqlite3 runs.db < db/schema.sql
    python3 db/load.py runs.db db/variant-call-cohort.tsv smoke-run-nf cluster-run-nf smoke-run-smk cluster-run-smk aws-run-nf
    pip install -r dashboard/requirements.txt
    python3 dashboard/app.py runs.db

and open http://127.0.0.1:8050. `runs.db` is not committed.
