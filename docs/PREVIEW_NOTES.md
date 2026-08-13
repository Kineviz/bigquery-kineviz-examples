# BigQuery Graph is pre-GA

> **Kineviz** (formerly **GraphXR**) is Kineviz's graph visualization and analytics
> platform. Some product surfaces still show the former name.

**Delete this file at GA**, and remove the `status: preview` and `maturity_note` fields from
every `demo.yaml`. It is kept as one file, rather than scattered through the prose, so GA
cleanup is a single commit.

## What "pre-GA" means here

BigQuery Graph is covered by Google's
[Pre-GA Offerings Terms](https://cloud.google.com/terms/service-terms). It is available as
is, with potentially limited support, and its behavior can change.

## The constraint that will actually bite you

**GQL queries require a reservation on the Enterprise or Enterprise Plus edition.**

On on-demand pricing you can call
[`GRAPH_EXPAND`](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/graph-sql-queries),
but not the full GQL surface — so `GRAPH ... MATCH ... RETURN` fails.

This is the most common reason a first run in this repo looks broken when nothing is wrong.
It is called out in three places on purpose: the repo README, each demo's **At a glance**
table, and `preflight.sh`, which warns before creating anything.

Check what you have:

```bash
bq ls --reservation --location=US
```

Create one, if your org allows it:

```bash
bq mk --reservation --location=US --slots=100 --edition=ENTERPRISE kineviz-demo
```

Reservations bill by slot-hour. **Delete it when you're done:**

```bash
bq rm --reservation --location=US kineviz-demo
```

## What this repo pins to

The demos use standard GQL syntax — `CREATE PROPERTY GRAPH`, `GRAPH ... MATCH ... RETURN` —
per the [ISO GQL standard](https://docs.cloud.google.com/bigquery/docs/graph-iso-standards)
that BigQuery Graph implements. No preview-only syntax, so GA should require no query
changes.

## At GA

1. Delete this file.
2. Remove `status: preview` and `maturity_note` from every `demo.yaml`.
3. Remove the reservation warning from `scripts/preflight.sh`.
4. Remove the caveat rows from the repo README and each demo's **At a glance**.
5. Re-run every demo and update `last_verified`.

## Reference

- [Introduction to BigQuery Graph](https://docs.cloud.google.com/bigquery/docs/graph-overview)
- [Create and query a graph](https://docs.cloud.google.com/bigquery/docs/graph-create)
- [GQL overview](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/graph-intro)
