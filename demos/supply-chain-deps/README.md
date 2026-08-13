# BigQuery Graph + Kineviz: open-source supply-chain risk

> **Kineviz** (formerly **GraphXR**) is Kineviz's graph visualization and analytics
> platform. Some product surfaces — the Google Cloud Marketplace listing, the
> `graphxr.kineviz.com` portal, and screenshots in this repo — still show the former name.

## What you'll build

A property graph over [deps.dev](https://deps.dev), Google's public Open Source Insights
dataset, connecting packages to the packages they depend on and the repos that back them.
Then you use it to find where supply-chain risk actually concentrates: not the packages with
the most dependents, but the ones with many dependents *and* an under-resourced repo behind
them.

![The dependency graph in Kineviz](img/hero.png)

## At a glance

| | |
|---|---|
| **Backend** | BigQuery Graph |
| **Status** | ⚠️ Pre-GA — **GQL requires an Enterprise or Enterprise Plus reservation** |
| **Connection** | Kineviz Desktop → BigQuery ([how](../../connect/)) |
| **Dataset** | `bigquery-public-data.deps_dev_v1` — public, no download |
| **Time** | ~12 minutes, mostly waiting on one query |
| **Cost** | ~$0.05 — setup materializes ~200 MB into your project; every query capped at 2 GB |
| **You need** | A Kineviz account (free for individual use, forever), a GCP project with billing enabled |

> The reservation requirement is the single most common reason a first run fails. On
> on-demand pricing you can use `GRAPH_EXPAND` but not full GQL. Details:
> [`docs/PREVIEW_NOTES.md`](../../docs/PREVIEW_NOTES.md).

## Architecture

```
        Kineviz Desktop
              │
              │  BigQuery project type, service account key
              ▼
   DepsGraph  (CREATE PROPERTY GRAPH)
              │
              ▼
   nodes_package · nodes_project          ← in YOUR project
   edges_depends_on · edges_maintained_in    (~200 MB, bounded)
              │
              │  one-time materialization
              ▼
   bigquery-public-data.deps_dev_v1       ← Google's public dataset
```

The materialization step exists so nothing downstream ever scans the public dataset. That
keeps exploration fast and the cost near zero.

## Prerequisites

1. **A Kineviz account** — [sign up](https://www.kineviz.com/). Kineviz Desktop is **free
   for individual use, forever**, but the app requires sign-in. Do this first.
2. **Kineviz Desktop v0.17.1+** —
   [releases](https://github.com/Kineviz/kineviz-desktop/releases). ~600 MB installed, 16 GB RAM.
3. **A Google Cloud project** with billing enabled and these roles on your account:
   - [`roles/bigquery.jobUser`](https://cloud.google.com/bigquery/docs/access-control#bigquery.jobUser) — run queries
   - [`roles/bigquery.dataEditor`](https://cloud.google.com/bigquery/docs/access-control#bigquery.dataEditor) — create the demo dataset

   Kineviz itself only needs **`dataViewer` + `jobUser`** to read the finished graph. The
   editor role is for building it. See [`connect/service-account.md`](../../connect/service-account.md).
4. **An Enterprise or Enterprise Plus reservation** in your BigQuery location, while
   BigQuery Graph is pre-GA.
5. **`gcloud` and `bq`** — [install](https://cloud.google.com/sdk/docs/install).

## Quick start

```bash
cp .env.example .env      # set GCP_PROJECT
../../gxr up supply-chain-deps
```

Preflight, setup, verify, then instructions for connecting. Most people stop here.

## Or do it step by step

The same procedure, one command at a time — for understanding what happens, working in a
restricted environment, or reviewing the API calls without reading bash.

**1. Check prerequisites.** Creates nothing, bills nothing.

```bash
./scripts/preflight.sh
```

Verifies auth, project access, the BigQuery API, that you can run jobs, whether a reservation
exists, and whether Kineviz Desktop is installed.

**2. Create the dataset.**

```bash
set -a; . .env; set +a
bq --project_id="$GCP_PROJECT" mk --dataset --location="$BQ_LOCATION" \
   "$GCP_PROJECT:$BQ_DATASET"
```

**3. Materialize a bounded slice of deps.dev.**

```bash
sed -e "s|\${PROJECT}|$GCP_PROJECT|g" -e "s|\${DATASET}|$BQ_DATASET|g" \
    -e "s|\${SYSTEM}|$DEPS_SYSTEM|g" -e "s|\${TOP_N}|$TOP_N_PACKAGES|g" \
    sql/01_materialize.sql \
  | bq query --project_id="$GCP_PROJECT" --use_legacy_sql=false \
      --maximum_bytes_billed="$MAX_BYTES_BILLED"
```

[`sql/01_materialize.sql`](sql/01_materialize.sql) builds four tables — the top
`TOP_N_PACKAGES` in one ecosystem, the dependency edges between them, the repos behind them,
and the package→repo edges. Edges are restricted to packages already in the node table, so
the graph is closed and every edge resolves.

Cheaper or bigger: change `TOP_N_PACKAGES` in `.env`. **Don't raise
`MAX_BYTES_BILLED`** — if a query exceeds the cap, lower the row count instead.

**4. Create the property graph.**

```bash
sed -e "s|\${PROJECT}|$GCP_PROJECT|g" -e "s|\${DATASET}|$BQ_DATASET|g" \
    -e "s|\${GRAPH}|$BQ_GRAPH|g" sql/02_property_graph.sql \
  | bq query --project_id="$GCP_PROJECT" --use_legacy_sql=false
```

[`sql/02_property_graph.sql`](sql/02_property_graph.sql) is what Kineviz connects to.

**5. Verify** — a real GQL query and a row count, not an assumption.

```bash
./scripts/verify.sh
```

## Connect Kineviz

The walkthrough with screenshots is in **[`connect/`](../../connect/)** — same six steps for
every demo here, so it's documented once.

Values for this demo:

| Field | Value |
|---|---|
| Database Type | BigQuery |
| Key file | your service account JSON ([how to make one](../../connect/service-account.md)) |
| Database | `kineviz_deps_demo` |
| Region | whatever you set as `BQ_LOCATION` (default `US`) |
| Graph | `DepsGraph` |

## Explore

Four questions, in [`queries/`](queries/). Run them in Kineviz's query panel.

**1. Which packages does the most of this ecosystem depend on?** —
[`01-fan-in.gql`](queries/01-fan-in.gql)

```sql
GRAPH `PROJECT.kineviz_deps_demo.DepsGraph`
MATCH (dependent:Package)-[:DEPENDS_ON]->(p:Package)
RETURN p.name AS package, COUNT(DISTINCT dependent.id) AS dependents
ORDER BY dependents DESC
LIMIT 25
```

High fan-in isn't itself a problem — it's what a healthy shared library looks like. It's the
starting point: these are where a compromise propagates furthest.

**2. Which of those sit on an under-resourced repo?** —
[`02-bus-factor.gql`](queries/02-bus-factor.gql)

The pairing is the finding. Heavy fan-in *and* a low-activity project is where risk
concentrates; either signal alone says little.

**3. What is one package's blast radius?** —
[`03-transitive-blast-radius.gql`](queries/03-transitive-blast-radius.gql)

Everything within three hops. **Run this one in Kineviz rather than the CLI** — the shape of
the result is the finding, and it's far easier to see than to read.

**4. Which packages secretly share a repo?** —
[`04-shared-project.gql`](queries/04-shared-project.gql)

Depending on three packages from the same repo is one point of failure wearing three names.
This is the query that most often surprises people.

## How the graph is modeled

| Node label | Source table | Key | Properties |
|---|---|---|---|
| `Package` | `nodes_package` | `id` (name) | `name`, `system`, `latest_version`, `dependent_count` |
| `Project` | `nodes_project` | `id` (repo name) | `name`, `host`, `stars`, `forks`, `open_issues`, `license` |

| Edge label | From → To | Source table | Properties |
|---|---|---|---|
| `DEPENDS_ON` | `Package` → `Package` | `edges_depends_on` | `minimum_depth` |
| `MAINTAINED_IN` | `Package` → `Project` | `edges_maintained_in` | — |

`minimum_depth` is the shortest path from a root package to that dependency: `1` is a direct
dependency, higher is transitive.

## Troubleshooting

**`Query requires a reservation` / an edition error**

The pre-GA reservation requirement. GQL needs Enterprise or Enterprise Plus; on-demand
pricing gets `GRAPH_EXPAND` only. Your data is already built — only the query is blocked.
See [`docs/PREVIEW_NOTES.md`](../../docs/PREVIEW_NOTES.md).

**`Exceeded maximum_bytes_billed`**

Working as intended. Lower `TOP_N_PACKAGES` in `.env` and re-run; don't raise the cap.

**Kineviz says the graph doesn't exist**

The region must match your dataset's location exactly — `US` and `us-central1` are different.
Check with `bq show --format=prettyjson "$GCP_PROJECT:$BQ_DATASET" | grep location`, or run
[`connect/verify.sh`](../../connect/verify.sh), which reports the exact value to enter.

**The graph is there but nearly empty**

Some ecosystems are sparse at low `TOP_N_PACKAGES`. Try `DEPS_SYSTEM=NPM` with
`TOP_N_PACKAGES=2000`.

**Desktop won't sign in**

An account is required, free for individual use. [Sign up](https://www.kineviz.com/).

## Clean up

```bash
../../gxr down supply-chain-deps
```

Or by hand:

```bash
bq --project_id="$GCP_PROJECT" rm -r -f --dataset "$GCP_PROJECT:$BQ_DATASET"
```

Two things teardown deliberately leaves alone: your Kineviz project (delete it in Desktop)
and your service account key (delete it if you made one just for this).

## What's next

- [`connect/`](../../connect/) — point Kineviz at your own BigQuery graph
- [Google's BigQuery Graph docs](https://docs.cloud.google.com/bigquery/docs/graph-overview)
- [`spanner-kineviz-examples`](https://github.com/Kineviz/spanner-kineviz-examples) — the same
  ideas on Spanner Graph, which is GA
