#!/usr/bin/env python3
"""A results page for the runs in the week-9 database.

    python3 dashboard/app.py runs.db [port]

Two pages: / lists the runs, and /results?run=<run_id> shows one run's samples, five plots of its
sites, and the sites themselves. A click on a bar of a count plot narrows the sites table to that bar.
"""
import os
import sqlite3
import sys
from urllib.parse import parse_qs, quote

import dash_ag_grid as dag
import pandas as pd
import plotly.express as px
from dash import Dash, Input, Output, State, ctx, dcc, html

DB = sys.argv[1]
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8050
HERE = os.path.dirname(os.path.abspath(__file__))
Q1 = os.path.join(HERE, "..", "db", "queries", "q1.sql")

QUESTIONS = {
    "plot-filter": "How many sites passed, and why did the others fail?",
    "plot-qual": "How confident are the calls?",
    "plot-position": "Where along the region are the sites?",
    "plot-type": "How many SNPs, indels and multiallelic sites?",
    "plot-titv": "Among SNPs, how many transitions and transversions?",
}
COUNT_PLOTS = ("plot-filter", "plot-type", "plot-titv")
COLOR = "#2a9d8f"


def query(sql, params=()):
    """Run one SELECT on the database named on the command line, on a connection of its own."""
    con = sqlite3.connect(DB)
    try:
        return pd.read_sql_query(sql, con, params=params)
    finally:
        con.close()


def site_type(ref, alt):
    if "," in alt:
        return "multiallelic"
    if len(ref) == 1 and len(alt) == 1:
        return "SNP"
    return "indel"


def snp_class(ref, alt):
    return "transition" if {ref.upper(), alt.upper()} in ({"A", "G"}, {"C", "T"}) else "transversion"


def category(plot, ref, alt, filt):
    """The bar of a count plot a site belongs to, or None for a site that is not a SNP in plot-titv."""
    if plot == "plot-filter":
        return filt
    if plot == "plot-type":
        return site_type(ref, alt)
    return snp_class(ref, alt) if site_type(ref, alt) == "SNP" else None


def same_bar(plot, a, b):
    a, b = str(a).strip(), str(b).strip()
    return a == b if plot == "plot-filter" else a.lower() == b.lower()


def run_of(search):
    values = parse_qs((search or "").lstrip("?")).get("run")
    return values[0] if values else None


def sites_of(run_id):
    return query("SELECT chrom, pos, ref, alt, qual, filter FROM variants WHERE run_id = ? ORDER BY chrom, pos",
                 (run_id,))


def grid(grid_id, df):
    return dag.AgGrid(id=grid_id,
                      rowData=df.to_dict("records"),
                      columnDefs=[{"field": c} for c in df.columns],
                      columnSize="sizeToFit",
                      dashGridOptions={"pagination": True, "paginationPageSize": 20})


def count_figure(plot, sites):
    bars = [category(plot, r, a, f) for r, a, f in zip(sites["ref"], sites["alt"], sites["filter"])]
    counts = pd.Series([b for b in bars if b is not None], dtype=object).value_counts()
    df = pd.DataFrame({"category": [str(c) for c in counts.index], "sites": [int(n) for n in counts.values]})
    fig = px.bar(df, x="category", y="sites", title=QUESTIONS[plot], color_discrete_sequence=[COLOR])
    fig.update_layout(xaxis_title=None)
    return fig


def value_figure(plot, sites, column):
    return px.histogram(sites, x=column, nbins=60, title=QUESTIONS[plot], color_discrete_sequence=[COLOR])


def runs_page():
    with open(Q1) as f:
        runs = query(f.read())
    links = html.Ul([html.Li(dcc.Link(run_id, href=f"/results?run={quote(run_id)}"))
                     for run_id in runs["run_id"]])
    return html.Div([
        html.H2("Runs"),
        html.P("Every run in the database. Open a run's results:"),
        links,
        grid("runs-table", runs),
    ])


def results_page(search):
    run_id = run_of(search)
    if not run_id or query("SELECT run_id FROM runs WHERE run_id = ?", (run_id,)).empty:
        return html.Div([html.H2("No such run"), html.P(f"The database has no run {run_id!r}."),
                         dcc.Link("All runs", href="/")])
    samples = query("SELECT run_samples.sample_id, run_samples.condition, samples.phenotype,"
                    " samples.is_synthetic_phenotype"
                    " FROM run_samples LEFT JOIN samples ON samples.sample_id = run_samples.sample_id"
                    " WHERE run_samples.run_id = ? ORDER BY run_samples.sample_id", (run_id,))
    sites = sites_of(run_id)
    plots = [dcc.Graph(id=p, figure=count_figure(p, sites)) for p in ("plot-filter", "plot-type", "plot-titv")]
    plots += [dcc.Graph(id="plot-qual", figure=value_figure("plot-qual", sites, "qual")),
              dcc.Graph(id="plot-position", figure=value_figure("plot-position", sites, "pos"))]
    return html.Div([
        dcc.Link("All runs", href="/"),
        html.H2(f"Run {run_id}"),
        html.H3("Samples"),
        html.P("The phenotypes are synthetic: they were made up for this course, as is_synthetic_phenotype says."
               " A sample the metadata does not describe has no phenotype."),
        grid("samples-table", samples),
        html.H3("Sites"),
        *plots,
        html.P("Click a bar of the first three plots to show only its sites below."),
        grid("sites-table", sites),
    ])


app = Dash(__name__, suppress_callback_exceptions=True)
app.layout = html.Div([dcc.Location(id="url"), html.H1("Variant-call runs"), html.Div(id="page")])


@app.callback(Output("page", "children"), Input("url", "pathname"), Input("url", "search"))
def draw(pathname, search):
    if pathname == "/results":
        return results_page(search)
    return runs_page()


@app.callback(Output("sites-table", "rowData"),
              Input("plot-filter", "clickData"), Input("plot-type", "clickData"), Input("plot-titv", "clickData"),
              State("url", "search"),
              prevent_initial_call=True)
def narrow(filter_click, type_click, titv_click, search):
    plot = ctx.triggered_id
    click = {"plot-filter": filter_click, "plot-type": type_click, "plot-titv": titv_click}.get(plot)
    sites = sites_of(run_of(search))
    if not click or not click.get("points"):
        return sites.to_dict("records")
    point = click["points"][0]
    bar = point.get("label", point.get("x"))
    keep = []
    for r, a, f in zip(sites["ref"], sites["alt"], sites["filter"]):
        c = category(plot, r, a, f)
        keep.append(c is not None and same_bar(plot, c, bar))
    return sites[pd.Series(keep, index=sites.index, dtype=bool)].to_dict("records")


if __name__ == "__main__":
    app.run(port=PORT, debug=True)
