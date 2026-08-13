# BigQuery Graph + Kineviz: privilege escalation paths in audit logs

> **Kineviz** (formerly **GraphXR**) is Kineviz's graph visualization and analytics
> platform. Some product surfaces — the Google Cloud Marketplace listing, the
> `graphxr.kineviz.com` portal, and screenshots in this repo — still show the former name.

## What you'll build

A property graph of Cloud Audit Log records — principals, the resources they touch, and who
can impersonate whom. Then you use it to answer the question a list of IAM grants cannot:
**who can reach sensitive data by going through something else?**

In this dataset only three principals touch sensitive resources directly, and all three are
service accounts. Every other route to that data is an escalation path, and the graph finds
them in one query.

<!-- TODO: hero screenshot of an escalation path on the Kineviz canvas -> img/hero.png -->

## At a glance

| | |
|---|---|
| **Backend** | BigQuery Graph |
| **Status** | Pre-GA — GQL verified working on on-demand pricing ([details](../../docs/PREVIEW_NOTES.md)) |
| **Connection** | Kineviz Desktop → BigQuery Property Graph ([how](../../connect/)) |
| **Dataset** | Synthetic, generated locally — no public dataset, nothing to download |
| **Time** | ~10 minutes |
| **Cost** | ~$0.01 — the data is a few MB and lives in your project |
| **You need** | A Kineviz account (free for individual use, forever), a GCP project with billing enabled |

> **The data is synthetic on purpose.** Real audit logs are the most sensitive data most
> organizations hold, so a public example repo should neither ship them nor ask you to point
> a first run at yours. The schema mirrors the fields that matter in
> `cloudaudit_googleapis_com_activity`, so the graph model and every query here transfer
> directly to real logs — swap the source table and the rest works unchanged.

## Architecture

```
        Kineviz Desktop
              │
              │  BigQuery Property Graph
              ▼
   AuditGraph  (CREATE PROPERTY GRAPH)
              │
              ▼
   nodes_principal · nodes_resource      ← in YOUR project
   edges_accessed  · edges_can_impersonate
              │
              ▼
   raw_principals · raw_impersonations · raw_events
              │
              │  seeded generator, no network
              ▼
   data/generate.py                      ← synthetic, reproducible
```

## Prerequisites

1. **A Kineviz account** — [sign up](https://www.kineviz.com/). Kineviz Desktop is **free
   for individual use, forever**, but the app requires sign-in. Do this first.
2. **Kineviz Desktop v0.17.1+** —
   [releases](https://github.com/Kineviz/kineviz-desktop/releases). ~600 MB installed,
   16 GB RAM.
3. **A Google Cloud project** with billing enabled and these roles on your account:
   - [`roles/bigquery.jobUser`](https://cloud.google.com/bigquery/docs/access-control#bigquery.jobUser) — run queries
   - [`roles/bigquery.dataEditor`](https://cloud.google.com/bigquery/docs/access-control#bigquery.dataEditor) — create the demo dataset
4. **`gcloud`, `bq`, and Python 3.9+** — [install the SDK](https://cloud.google.com/sdk/docs/install).

   No BigQuery reservation is needed: GQL was verified working on on-demand pricing on
   2026-08-13.

## Quick start

```bash
cp .env.example .env      # set GCP_PROJECT
../../gxr up cloud-audit-access
```

This is the cheapest and fastest demo in the repo — nothing reads a public dataset.

## Or do it step by step

**1. Check prerequisites.** Creates nothing.

```bash
./scripts/preflight.sh
```

**2. Generate the logs.** Seeded, so the same numbers always produce the same graph —
including the escalation paths the queries find.

```bash
set -a; . .env; set +a
python3 data/generate.py --out data/generated --seed "$AUDIT_SEED" \
  --days "$AUDIT_DAYS" --principals "$AUDIT_PRINCIPALS" --events "$AUDIT_EVENTS"
```

It prints the findings it planted, so you know what the queries should surface.

**3. Create the dataset and load the logs.**

```bash
bq --project_id="$GCP_PROJECT" mk --dataset --location="$BQ_LOCATION" \
   "$GCP_PROJECT:$BQ_DATASET"

for t in principals impersonations events; do
  bq --project_id="$GCP_PROJECT" load --replace \
     --source_format=NEWLINE_DELIMITED_JSON --autodetect \
     "$GCP_PROJECT:$BQ_DATASET.raw_$t" "data/generated/$t.ndjson"
done
```

**4. Shape the node and edge tables.**

```bash
sed -e "s|\${PROJECT}|$GCP_PROJECT|g" -e "s|\${DATASET}|$BQ_DATASET|g" \
    sql/01_build_tables.sql \
  | bq query --project_id="$GCP_PROJECT" --use_legacy_sql=false \
      --maximum_bytes_billed="$MAX_BYTES_BILLED"
```

[`sql/01_build_tables.sql`](sql/01_build_tables.sql) aggregates 6,000 log lines into one
edge per principal/resource pair — the graph you can actually read.

**5. Create the property graph.**

```bash
sed -e "s|\${PROJECT}|$GCP_PROJECT|g" -e "s|\${DATASET}|$BQ_DATASET|g" \
    -e "s|\${GRAPH}|$BQ_GRAPH|g" sql/02_property_graph.sql \
  | bq query --project_id="$GCP_PROJECT" --use_legacy_sql=false
```

**6. Verify.**

```bash
./scripts/verify.sh
```

This runs the demo's *headline* query rather than a trivial smoke test. If no escalation
paths come back, the graph technically works but the demo is pointless — so that counts as a
failure here.

## Connect Kineviz

The walkthrough with screenshots is in **[`connect/`](../../connect/)** — the same flow for
every demo here, so it's documented once.

Values for this demo:

| Field | Value |
|---|---|
| Database Type | `BigQuery Property Graph` |
| Upload Service Account | your service account JSON ([how to make one](../../connect/service-account.md)) |
| Select Database | `kineviz_audit_demo` |
| Select location (Optional) | your `BQ_LOCATION` (default `US`) |
| Select Graph Database | `AuditGraph` |

## Explore

Four questions, in [`queries/`](queries/). **Start with `01`** — it's the query this demo
exists for.

**1. Who reaches sensitive data only by impersonation?** —
[`01-escalation-paths.gql`](queries/01-escalation-paths.gql)

Principals that touch nothing sensitive directly but reach it through something that can. An
access review built on direct grants shows these people as harmless.

**2. One principal's blast radius** — [`02-blast-radius.gql`](queries/02-blast-radius.gql)

**Run this in Kineviz, not the CLI.** "How far does this account actually reach" is a shape,
and "should we offboard this contractor first" is usually obvious on sight.

**3. Resources reachable by more than one route** —
[`03-redundant-paths.gql`](queries/03-redundant-paths.gql)

The finding a spreadsheet can't produce. Revoking one grant feels like remediation; if a
second path exists, nothing changed.

**4. Who's accumulating denials?** — [`04-denied-probing.gql`](queries/04-denied-probing.gql)

Usually a broken job. Sometimes someone finding out what they can reach.

### What you should find

Seeded, so these are reproducible rather than lucky:

- **`dana@acme.example`** holds only viewer-tier roles, but impersonates `sa-etl-runner@`
  and through it reads `gs://acme-customer-pii`.
- **`sa-ci-deployer@` → `sa-secrets-reader@` → `secret://acme-prod/stripe-live-key`** — a
  service-account chain with no human in it, so it never appears in a user access review.
- **`contractor-priya@partner.example`** reaches `gs://acme-customer-pii` through *two*
  different service accounts. Revoking one changes nothing.

## How the graph is modeled

| Node label | Source table | Key | Properties |
|---|---|---|---|
| `Principal` | `nodes_principal` | `id` (email) | `name`, `principal_type`, `roles`, `successful_calls`, `denied_calls` |
| `Resource` | `nodes_resource` | `id` (URI) | `name`, `resource_type`, `sensitivity`, `access_count` |

| Edge label | From → To | Source table | Properties |
|---|---|---|---|
| `ACCESSED` | `Principal` → `Resource` | `edges_accessed` | `call_count`, `denied_count`, `methods`, `max_severity_tier`, `first_seen`, `last_seen` |
| `CAN_IMPERSONATE` | `Principal` → `Principal` | `edges_can_impersonate` | `grant_type` |

`CAN_IMPERSONATE` is the edge that does the work. Without it this is a list of who touched
what; with it, reachability becomes a graph problem.

### Pointing this at real logs

Replace `raw_events` with your audit log sink and map four fields —
`protopayload_auditlog.authenticationInfo.principalEmail`, `methodName`, `resourceName`, and
the status — then derive `sensitivity` from your own resource labels. The impersonation
edges come from `iam.serviceAccounts.getAccessToken` calls in the same logs.

## Troubleshooting

**`verify.sh` reports no escalation paths**

Shouldn't happen — the data is seeded. If it does, `data/generate.py` and the demo have
drifted apart. Open an issue; that's a bug, not a configuration problem.

**The load step fails on schema autodetection**

Delete `data/generated/` and re-run setup. A partially written NDJSON file confuses
autodetect.

**A reservation or edition error**

Uncommon — GQL was verified working on on-demand pricing. See
[`docs/PREVIEW_NOTES.md`](../../docs/PREVIEW_NOTES.md) if you hit it.

**Everything looks suspicious**

It's synthetic. `acme.example` and `partner.example` are reserved example domains, and none
of the principals, resources, or secrets are real.

## Clean up

```bash
../../gxr down cloud-audit-access
```

Or by hand:

```bash
bq --project_id="$GCP_PROJECT" rm -r -f --dataset "$GCP_PROJECT:$BQ_DATASET"
rm -rf data/generated
```

Your Kineviz project is separate — delete it in Kineviz Desktop if you no longer want it.

## What's next

- [`supply-chain-deps`](../supply-chain-deps/) — dependency risk on deps.dev
- [`ethereum-flows`](../ethereum-flows/) — tracing value through Ethereum
- [`connect/`](../../connect/) — point Kineviz at your own BigQuery graph
