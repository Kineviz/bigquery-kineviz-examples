# What these demos cost

> **Kineviz** (formerly **GraphXR**) is Kineviz's graph visualization and analytics
> platform. Some product surfaces still show the former name.

Short version: **Kineviz Desktop is free for individual use, forever**, and the demos cost
cents. But they run in *your* Google Cloud project, so the numbers are real.

## Per demo

| Demo | Estimate | What bounds it |
|---|---|---|
| `supply-chain-deps` | ~$0.05 | Materializes ~200 MB once; every query capped at 2 GB via `maximum_bytes_billed` |

Each `demo.yaml` carries the same figures under `cost:`, which is what the repo index is
generated from.

## The one that isn't cents

**A BigQuery reservation — which you probably do not need.** GQL was verified running on
on-demand pricing with no reservation on 2026-08-13, so the demos here cost what the table
above says. Google's docs mention an Enterprise/Enterprise Plus requirement; if your project
turns out to enforce it, note that reservations bill by slot-hour whether or not you query,
and would dwarf every other line item here.

If you do create one, delete it afterwards:

```bash
bq rm --reservation --location=US kineviz-demo
```

## How spend is capped

Three rules, applied to every demo in this repo:

1. **Every query sets `maximum_bytes_billed`.** If a query exceeds it, it fails instead of
   billing. That is the intended behavior — lower the row count rather than raising the cap.
2. **Public datasets are scanned once.** Setup materializes a small bounded slice into your
   project; everything after reads that. Nothing repeatedly scans
   `bigquery-public-data`.
3. **Teardown deletes what setup created.** `./gxr down <demo>` removes the dataset. It
   deliberately does not touch your Kineviz project or your service account key.

## Checking before you run

```bash
bq query --use_legacy_sql=false --dry_run < sql/01_materialize.sql
```

A dry run reports bytes processed and bills nothing.

## Watching what you spent

```bash
bq ls -j --max_results=20 --format=prettyjson \
  | grep -E 'totalBytesBilled|query' | head -40
```

Or [Billing → Reports](https://console.cloud.google.com/billing) filtered to BigQuery.

## If something surprised you

Open an issue. An unexpected charge from an example repo is a bug in the example, not user
error, and we would want to fix the bound.
