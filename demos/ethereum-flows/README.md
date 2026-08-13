# BigQuery Graph + Kineviz: tracing Ethereum fund flows

> **Kineviz** (formerly **GraphXR**) is Kineviz's graph visualization and analytics
> platform. Some product surfaces — the Google Cloud Marketplace listing, the
> `graphxr.kineviz.com` portal, and screenshots in this repo — still show the former name.

## What you'll build

A property graph of one day of Ethereum — roughly 1.2 million transactions, bounded to the
addresses that actually moved value — with wallets, contracts, and the transfers between
them. Then you follow value through it: find the hubs it concentrates in, walk two hops out
from an address, and spot wallets that forward almost everything they receive.

<!-- TODO: hero screenshot of the flow graph on the Kineviz canvas -> img/hero.png -->

## At a glance

| | |
|---|---|
| **Backend** | BigQuery Graph |
| **Status** | Pre-GA — GQL verified working on on-demand pricing ([details](../../docs/PREVIEW_NOTES.md)) |
| **Connection** | Kineviz Desktop → BigQuery Property Graph ([how](../../connect/)) |
| **Dataset** | `bigquery-public-data.crypto_ethereum` — public, no download |
| **Time** | ~15 minutes, mostly one materialization query |
| **Cost** | ~$0.20 — one day partition, then everything reads your own small tables |
| **You need** | A Kineviz account (free for individual use, forever), a GCP project with billing enabled |

> **This is the most expensive demo in the repo, and the one where cost can run away if you
> change things carelessly.** `crypto_ethereum.transactions` is enormous. Every read is
> pinned to a single day with an explicit timestamp range so BigQuery prunes to one
> partition. Preflight dry-runs that query and shows you the estimate before anything runs.

## Architecture

```
        Kineviz Desktop
              │
              │  BigQuery Property Graph
              ▼
   EthGraph  (CREATE PROPERTY GRAPH)
              │
              ▼
   nodes_address · nodes_contract        ← in YOUR project
   edges_sent   · edges_called              (bounded, one day)
              │
              │  one day partition, explicit timestamp range
              ▼
   bigquery-public-data.crypto_ethereum  ← Google's public dataset
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

   Kineviz itself only needs `dataViewer` + `jobUser` to read the finished graph.
4. **`gcloud` and `bq`** — [install](https://cloud.google.com/sdk/docs/install).

   No BigQuery reservation is needed: GQL was verified working on on-demand pricing on
   2026-08-13. If you hit an edition or reservation error, see
   [`docs/PREVIEW_NOTES.md`](../../docs/PREVIEW_NOTES.md).

## Quick start

```bash
cp .env.example .env      # set GCP_PROJECT
../../gxr up ethereum-flows
```

Preflight (including a cost dry-run), setup, verify, then instructions for connecting.

## Or do it step by step

The same procedure, one command at a time.

**1. Check prerequisites, and see the cost before you spend it.** Creates nothing.

```bash
./scripts/preflight.sh
```

This dry-runs the day's partition scan and prints the estimate. It refuses to continue if
that day would exceed your `MAX_BYTES_BILLED` ceiling — the point being that you find out
before the bill, not after.

**2. Create the dataset.**

```bash
set -a; . .env; set +a
bq --project_id="$GCP_PROJECT" mk --dataset --location="$BQ_LOCATION" \
   "$GCP_PROJECT:$BQ_DATASET"
```

**3. Materialize one day of transfers.**

```bash
sed -e "s|\${PROJECT}|$GCP_PROJECT|g" -e "s|\${DATASET}|$BQ_DATASET|g" \
    -e "s|\${ETH_DATE}|$ETH_DATE|g" -e "s|\${TOP_N}|$TOP_N_ADDRESSES|g" \
    -e "s|\${MIN_ETH}|$MIN_ETH|g" sql/01_materialize.sql \
  | bq query --project_id="$GCP_PROJECT" --use_legacy_sql=false \
      --maximum_bytes_billed="$MAX_BYTES_BILLED"
```

[`sql/01_materialize.sql`](sql/01_materialize.sql) builds six tables: the day's non-dust
transfers, the top addresses by value moved, those addresses split into wallets and
contracts, and the aggregated edges between them.

Edges are **aggregated per address pair**, not one per transaction. A day holds over a
million transactions; one edge per pair with a count and a total is both cheaper and the
thing you actually want to look at.

**4. Create the property graph.**

```bash
sed -e "s|\${PROJECT}|$GCP_PROJECT|g" -e "s|\${DATASET}|$BQ_DATASET|g" \
    -e "s|\${GRAPH}|$BQ_GRAPH|g" sql/02_property_graph.sql \
  | bq query --project_id="$GCP_PROJECT" --use_legacy_sql=false
```

**5. Verify** — a real GQL query and a row count.

```bash
./scripts/verify.sh
```

## Connect Kineviz

The walkthrough with screenshots is in **[`connect/`](../../connect/)** — the same flow for
every demo here, so it's documented once.

Values for this demo:

| Field | Value |
|---|---|
| Database Type | `BigQuery Property Graph` |
| Upload Service Account | your service account JSON ([how to make one](../../connect/service-account.md)) |
| Select Database | `kineviz_eth_demo` |
| Select location (Optional) | your `BQ_LOCATION` (default `US`) |
| Select Graph Database | `EthGraph` |

## Explore

Four questions, in [`queries/`](queries/). **Start with `01`** — it gives you the addresses
to paste into `02`, and tells you which hubs are just exchanges so you don't over-read a path
running through one.

**1. Where does value concentrate?** — [`01-value-hubs.gql`](queries/01-value-hubs.gql)

```sql
GRAPH `PROJECT.kineviz_eth_demo.EthGraph`
MATCH (sender:Address)-[s:SENT]->(hub:Address)
RETURN hub.address AS hub, COUNT(DISTINCT sender.id) AS distinct_senders,
       SUM(s.total_eth) AS eth_received
GROUP BY hub
ORDER BY eth_received DESC
LIMIT 25
```

The top of this list is almost always exchanges, bridges, and mixers rather than
individuals. That's the baseline worth knowing before reading anything into a path.

**2. Follow the money, two hops out** —
[`02-follow-the-money.gql`](queries/02-follow-the-money.gql)

**Run this in Kineviz, not the CLI.** Whether value fans out to many recipients or funnels
into a few is obvious in the picture and invisible in a table.

**3. Which contracts pull the most ETH?** —
[`03-contract-magnets.gql`](queries/03-contract-magnets.gql)

High value from few wallets reads like treasury movement; modest value from thousands reads
like a product.

**4. Wallets that pass value straight through** —
[`04-pass-through.gql`](queries/04-pass-through.gql)

Wallets where nearly everything received goes straight out again. One is unremarkable. A
chain of them is the shape laundering typologies look for — also best seen in Kineviz.

## How the graph is modeled

| Node label | Source table | Key | Properties |
|---|---|---|---|
| `Address` | `nodes_address` | `id` (0x…) | `address`, `total_eth`, `transfer_count` |
| `Contract` | `nodes_contract` | `id` (0x…) | `address`, `is_erc20`, `is_erc721`, `total_eth`, `transfer_count` |

| Edge label | From → To | Source table | Properties |
|---|---|---|---|
| `SENT` | `Address` → `Address` | `edges_sent` | `transfer_count`, `total_eth`, `first_seen`, `last_seen` |
| `CALLED` | `Address` → `Contract` | `edges_called` | `call_count`, `total_eth`, `last_seen` |

The wallet/contract split comes from `crypto_ethereum.contracts`: an address that appears
there has code, so value sent to it is a call rather than a payment to a person.

## Troubleshooting

**Preflight refuses to continue, citing scan size**

Working as intended. That day would exceed your `MAX_BYTES_BILLED`. Pick a different
`ETH_DATE`, or raise the ceiling deliberately knowing it raises the bill.

**`Exceeded maximum_bytes_billed` during setup**

Same cause, caught later. Lower `TOP_N_ADDRESSES` or raise `MIN_ETH` in `.env` — don't raise
the cap.

**The graph is nearly empty**

`MIN_ETH` is filtering too hard for that day, or `TOP_N_ADDRESSES` is too low. Try
`MIN_ETH=0.001` and `TOP_N_ADDRESSES=3000`, then re-run setup.

**Query 02 returns nothing**

The default address in that file is the zero address, which is a placeholder. Replace it
with a real address from query 01.

**A reservation or edition error**

Uncommon — GQL was verified working on on-demand pricing. See
[`docs/PREVIEW_NOTES.md`](../../docs/PREVIEW_NOTES.md) if you hit it.

## Clean up

```bash
../../gxr down ethereum-flows
```

Or by hand:

```bash
bq --project_id="$GCP_PROJECT" rm -r -f --dataset "$GCP_PROJECT:$BQ_DATASET"
```

Your Kineviz project is separate — delete it in Kineviz Desktop if you no longer want it.

## What's next

- [`supply-chain-deps`](../supply-chain-deps/) — the cheaper first-run demo, on deps.dev
- [`cloud-audit-access`](../cloud-audit-access/) — privilege escalation paths in audit logs
- [`connect/`](../../connect/) — point Kineviz at your own BigQuery graph
