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

## The reservation question

Google's documentation states that GQL queries require a reservation on the **Enterprise** or
**Enterprise Plus** edition, and that on-demand pricing is limited to
[`GRAPH_EXPAND`](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/graph-sql-queries).

**We could not reproduce that.** Tested 2026-08-13:

| | |
|---|---|
| Project | on-demand pricing, US multi-region |
| Reservations | none, in `US`, `EU`, `us-central1`, `us-east1`, `us-west1` |
| Capacity commitments | none |
| `GRAPH … MATCH (c)-[:X]->(m) RETURN …` | ✅ returned rows |
| Variable-length quantifier `-[]->{1,2}` | ✅ returned 320 paths |

So the full GQL surface worked on on-demand pricing with no reservation and no commitment.
This may be because the requirement was relaxed as BigQuery Graph approaches GA, or because
it never applied to these query shapes.

**What this repo therefore assumes:** you do not need a reservation. No demo requires one,
and no preflight blocks on one.

**If your project does hit an edition or reservation error**, that is the cause, and the fix
is to add a reservation:

```bash
bq ls --reservation --location=US            # what you have
bq mk --reservation --location=US --slots=100 --edition=ENTERPRISE kineviz-demo
```

Reservations bill by slot-hour whether or not you query — **delete it when you are done**:

```bash
bq rm --reservation --location=US kineviz-demo
```

Every `verify.sh` in this repo pattern-matches edition and reservation errors specifically,
so you will get that remediation rather than a generic failure.

## What this repo pins to

The demos use standard GQL syntax — `CREATE PROPERTY GRAPH`, `GRAPH … MATCH … RETURN` — per
the [ISO GQL standard](https://docs.cloud.google.com/bigquery/docs/graph-iso-standards) that
BigQuery Graph implements. No preview-only syntax, so GA should require no query changes.

## At GA

1. Delete this file.
2. Remove `status: preview` and `maturity_note` from every `demo.yaml`.
3. Remove the pre-GA rows from the repo README and each demo's **At a glance**.
4. Re-run every demo and update `last_verified`.
5. Re-check the reservation position against Google's GA docs — if it changes, the
   `verify.sh` error branches should say so.

## Reference

- [Introduction to BigQuery Graph](https://docs.cloud.google.com/bigquery/docs/graph-overview)
- [Create and query a graph](https://docs.cloud.google.com/bigquery/docs/graph-create)
- [GQL overview](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/graph-intro)
