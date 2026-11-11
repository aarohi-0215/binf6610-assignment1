#!/usr/bin/env python3
"""Load run folders of the variant-call pipeline into the SQLite database built by db/schema.sql.

    python3 db/load.py runs.db db/variant-call-cohort.tsv <run folder> [<run folder> ...]
"""
import csv
import json
import os
import sqlite3
import sys

METADATA_COLUMNS = ["sample_id", "sex", "population", "family", "father", "mother",
                    "phenotype", "is_synthetic_phenotype"]


def read_tsv(path):
    with open(path, newline="") as f:
        lines = [line for line in f if not line.startswith("#")]
    return list(csv.DictReader(lines, delimiter="\t"))


def load_metadata(con, path):
    rows = read_tsv(path)
    added = 0
    with con:
        for row in rows:
            if con.execute("SELECT 1 FROM samples WHERE sample_id = ?", (row["sample_id"],)).fetchone():
                continue
            con.execute(f"INSERT INTO samples ({', '.join(METADATA_COLUMNS)})"
                        f" VALUES ({', '.join('?' for _ in METADATA_COLUMNS)})",
                        [row[c] for c in METADATA_COLUMNS])
            added += 1
    print(f"metadata: {len(rows)} samples, {added} new")


def pipeline_id(con, p):
    key = (p["name"], p["version"], p["implementation"])
    row = con.execute("SELECT pipeline_id FROM pipelines WHERE name = ? AND version = ? AND implementation = ?",
                      key).fetchone()
    if row:
        return row[0]
    return con.execute("INSERT INTO pipelines (name, version, implementation) VALUES (?, ?, ?)", key).lastrowid


def load_run(con, folder):
    folder = os.path.abspath(folder)
    with open(os.path.join(folder, "manifest.json")) as f:
        m = json.load(f)
    p, platform, params = m["pipeline"], m["platform"], m.get("params", {})
    run_id = p["run_id"]
    if con.execute("SELECT 1 FROM runs WHERE run_id = ?", (run_id,)).fetchone():
        print(f"{os.path.basename(folder)}: run {run_id} is already loaded, skipped")
        return
    samples = read_tsv(os.path.join(folder, "samples.tsv"))
    variants = read_tsv(os.path.join(folder, "variants.tsv"))
    library = {s["sample_id"]: s.get("library_type") for s in m.get("samples", [])}
    with con:
        con.execute("INSERT INTO runs (run_id, pipeline_id, started_at, finished_at, exit_status, platform,"
                    " executor, samplesheet, reference, region, git_sha, folder)"
                    " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (run_id, pipeline_id(con, p), p["started_at"], p["finished_at"], p["exit_status"],
                     platform["kind"], platform.get("executor"), params.get("samplesheet"),
                     params.get("ref"), params.get("region"), p.get("git_sha"), folder))
        for s in samples:
            if not con.execute("SELECT 1 FROM samples WHERE sample_id = ?", (s["sample_id"],)).fetchone():
                con.execute("INSERT INTO samples (sample_id) VALUES (?)", (s["sample_id"],))
        for s in samples:
            con.execute("INSERT INTO run_samples (run_id, sample_id, condition, library_type) VALUES (?, ?, ?, ?)",
                        (run_id, s["sample_id"], s.get("condition"), library.get(s["sample_id"])))
        con.executemany("INSERT INTO variants (run_id, chrom, pos, ref, alt, qual, filter)"
                        " VALUES (?, ?, ?, ?, ?, ?, ?)",
                        [(run_id, v["chrom"], int(v["pos"]), v["ref"], v["alt"],
                          None if v["qual"] in ("", ".") else float(v["qual"]), v["filter"]) for v in variants])
        con.executemany("INSERT INTO outputs (run_id, path, sha256) VALUES (?, ?, ?)",
                        [(run_id, o["path"], o["checksum"].lower().replace("sha256:", ""))
                         for o in m["outputs"]])
    print(f"{os.path.basename(folder)}: run {run_id} loaded, {len(samples)} samples,"
          f" {len(variants)} variants, {len(m['outputs'])} outputs")


def main():
    if len(sys.argv) < 4:
        print("usage: python3 db/load.py <runs.db> <metadata.tsv> <run folder> [<run folder> ...]", file=sys.stderr)
        return 64
    db, metadata, folders = sys.argv[1], sys.argv[2], sys.argv[3:]
    con = sqlite3.connect(db)
    con.execute("PRAGMA foreign_keys = ON")
    load_metadata(con, metadata)
    failed = 0
    for folder in folders:
        try:
            load_run(con, folder)
        except (sqlite3.Error, OSError, KeyError, ValueError) as e:
            failed += 1
            print(f"{os.path.basename(os.path.abspath(folder))}: refused, nothing of it loaded: {e}", file=sys.stderr)
    con.close()
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
