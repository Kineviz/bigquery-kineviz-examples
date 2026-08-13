# BigQuery Graph + Kineviz: SEC filings as a knowledge graph

> **Kineviz** (formerly **GraphXR**) is Kineviz's graph visualization and analytics
> platform. Some product surfaces — the Google Cloud Marketplace listing, the
> `graphxr.kineviz.com` portal, and screenshots in this repo — still show the former name.

## What you'll build

A knowledge graph extracted from SEC 10-K filings — the markets companies say they're
entering, the risks they disclose, and the competitors they name — using Gemini **inside
BigQuery** via `AI.GENERATE_TEXT`, with no data leaving your project. Then you explore it in
Kineviz: who's converging on the same market, which risks are sector-wide, and who names
whom.

This is the demo that shows what BigQuery Graph plus an LLM can do to unstructured text at
scale. It's also the most expensive one here, so read *At a glance* before running it.

<!-- TODO: hero screenshot of the SEC knowledge graph on the Kineviz canvas -> img/hero.png -->

## At a glance

| | |
|---|---|
| **Backend** | BigQuery Graph + Vertex AI (Gemini) |
| **Status** | ⚠️ Pre-GA — **GQL requires an Enterprise or Enterprise Plus reservation** |
| **Connection** | Kineviz Desktop → BigQuery Property Graph ([how](../../connect/)) |
| **Dataset** | SEC EDGAR 10-K/10-Q filings, fetched live |
| **Time** | ~45 minutes, mostly Gemini extraction |
| **Cost** | **~$3 for the default 3 companies** — roughly $1 each, and it scales linearly |
| **You need** | A Kineviz account (free for individual use, forever), a GCP project with billing, a GCS bucket, and a `vertex_ai_connection` |

> **The cost dial is `SEC_TICKERS`, not a byte limit.** Gemini extraction dominates the bill
> and scales linearly with company count. The default is three. The full Fortune 500 is
> roughly 170× that — change it deliberately. Preflight prints the count and warns above ten.

> **This demo wraps [`Kineviz/fortune500`](https://github.com/Kineviz/fortune500)** rather
> than forking it. That repo already does the scraping, parsing, and extraction; duplicating
> it here would mean two copies drifting apart. What this repo adds is what fortune500
> lacks: preflight checks, a cost bound, verification, and a teardown that actually deletes
> what was created. The upstream commit is pinned in [`demo.yaml`](demo.yaml).

## Architecture

```
        Kineviz Desktop
              │
              │  BigQuery Property Graph
              ▼
   SecGraph  (CREATE PROPERTY GRAPH)
              │
              ▼
   nodes_company · nodes_market · nodes_risk · nodes_competitor · …
              │
              │  AI.GENERATE_TEXT — Gemini, inside BigQuery
              ▼
   extracted sections in BigQuery
              │
              │  staged via gs://<your-bucket>/kineviz-sec-demo/
              ▼
   SEC EDGAR 10-K / 10-Q filings      ← fetched by the upstream pipeline
```

The extraction runs *inside* BigQuery through a Cloud Resource connection, so filing text
never leaves your project.

## Prerequisites

More setup than the other demos here. Preflight checks every item and refuses to start until
they pass — each one, if missed, otherwise fails deep into a paid run.

1. **A Kineviz account** — [sign up](https://www.kineviz.com/). Free for individual use,
   forever; the app requires sign-in.
2. **Kineviz Desktop v0.17.1+** —
   [releases](https://github.com/Kineviz/kineviz-desktop/releases). ~600 MB installed,
   16 GB RAM.
3. **A Google Cloud project** with **billing enabled** and these roles:
   - `roles/bigquery.jobUser`, `roles/bigquery.dataEditor`
   - `roles/aiplatform.user` — Gemini calls
   - `roles/storage.objectAdmin` — staging extracted JSON
4. **Three APIs enabled**: `bigquery.googleapis.com`, `aiplatform.googleapis.com`,
   `storage.googleapis.com`.
5. **A GCS bucket** you can write to. The demo stages under `kineviz-sec-demo/` and teardown
   removes only that prefix.
6. **A BigQuery connection named `vertex_ai_connection`** in your location, whose service
   account holds `roles/aiplatform.user`:

   ```bash
   bq mk --connection --location="$BQ_LOCATION" --project_id="$GCP_PROJECT" \
     --connection_type=CLOUD_RESOURCE vertex_ai_connection
   bq show --connection "$GCP_PROJECT.$BQ_LOCATION.vertex_ai_connection"   # note serviceAccountId
   gcloud projects add-iam-policy-binding "$GCP_PROJECT" \
     --member="serviceAccount:<THAT_SERVICE_ACCOUNT>" --role=roles/aiplatform.user
   ```

7. **An Enterprise or Enterprise Plus reservation**, while BigQuery Graph is pre-GA.
8. **`gcloud`, `bq`, `gsutil`, `git`, Python 3.9+.**

## Quick start

```bash
cp .env.example .env      # set GCP_PROJECT and GCS_BUCKET
../../gxr up sec-filings
```

Preflight is strict here by design — it's cheaper to fail in ten seconds than forty minutes
into a paid extraction run.

## Or do it step by step

**1. Check prerequisites.** Creates nothing, bills nothing.

```bash
./scripts/preflight.sh
```

Verifies auth, all three APIs, the bucket, BigQuery jobs, the `vertex_ai_connection`, the
reservation, and your ticker count — printing the number of companies before you spend.

**2. Clone the upstream pipeline at its pinned commit.**

```bash
set -a; . .env; set +a
git clone https://github.com/Kineviz/fortune500 .upstream
git -C .upstream checkout "$(sed -n 's/^  commit: *//p' demo.yaml | tr -d '\"')"
```

**3. Run the pipeline.** This is the step that calls Gemini and bills.

```bash
cd .upstream
python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt
GCP_PROJECT="$GCP_PROJECT" BQ_DATASET="$BQ_DATASET" GCS_BUCKET="$GCS_BUCKET" \
  GEMINI_MODEL="$GEMINI_MODEL" ./00_run_full_pipeline.sh "$SEC_TICKERS"
cd ..
```

Scrape → parse → extract sections → GCS → BigQuery → Gemini extraction → node and edge
tables → `CREATE PROPERTY GRAPH`. The pipeline is documented in
[the upstream README](https://github.com/Kineviz/fortune500).

**4. Verify.**

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
| Select Database | `kineviz_sec_demo` |
| Select location (Optional) | your `BQ_LOCATION` (default `US`) |
| Select Graph Database | `SecGraph` |

## Explore

Four questions, in [`queries/`](queries/).

**1. Which markets is each company entering?** —
[`01-markets-entered.gql`](queries/01-markets-entered.gql)

What companies tell *regulators* they're doing — a different, often earlier signal than what
they tell the press.

**2. Who names whom as a competitor?** —
[`02-competitor-network.gql`](queries/02-competitor-network.gql)

Competitor claims are directional and often asymmetric: A names B, B never mentions A. That
asymmetry is the interesting part, and it's immediately visible in Kineviz.

**3. Risks more than one company shares** — [`03-shared-risks.gql`](queries/03-shared-risks.gql)

A risk one company names is that company's problem. A risk everyone names is a sector
condition. The ones in between are where the questions are.

**4. Companies converging on the same market** —
[`04-market-collisions.gql`](queries/04-market-collisions.gql)

Where competition is about to happen but hasn't yet shown up in the competitor disclosures.

> **Every node here was extracted from prose by a language model.** That makes it a useful
> index into thousands of pages nobody reads, and it means individual claims can be wrong.
> The `evidence` property carries the source passage — check it before acting on anything.
> That's the intended workflow: find the claim in the graph, then read the source.

## How the graph is modeled

The schema is defined by the upstream pipeline's
[`06_create_property_graph_ddl.sql`](https://github.com/Kineviz/fortune500/blob/main/06_create_property_graph_ddl.sql),
which builds eleven node labels. The ones the queries here use:

| Node label | Source table | What it is |
|---|---|---|
| `Company` | `nodes_company` | A filer, keyed by ticker |
| `Market` | `nodes_market` | A market named in a filing, with `evidence` |
| `Risk` | `nodes_risk` | A disclosed risk factor |
| `NormalizedCompetitor` | `nodes_normalized_competitor` | A competitor name after LLM normalization |

| Edge label | From → To |
|---|---|
| `ENTERING` | `Company` → `Market` |
| `FACING` | `Company` → `Risk` |
| `COMPETES_WITH` | `Company` → `NormalizedCompetitor` |

Because the schema lives upstream, it can change when the pin is updated. If a query returns
nothing, check the labels that pipeline produces at the pinned commit.

## Troubleshooting

**Preflight: no `vertex_ai_connection`**

The most common failure, and the reason preflight checks it. The remediation it prints
includes the exact `bq mk --connection` and IAM commands.

**The pipeline fails partway through extraction**

Re-run `./scripts/setup.sh` — it's safe to repeat, and the upstream pipeline checkpoints
already-processed filings rather than redoing them.

**`verify.sh` returns no rows**

The graph exists but has no `Company → Market` edges. Gemini may have extracted nothing for
those tickers. Try different `SEC_TICKERS`.

**The pinned commit no longer exists**

Upstream force-pushed. That's a bug here — open an issue so the pin can be updated and
re-verified rather than silently moved.

**It cost more than $3**

Check how many tickers you ran. Cost scales linearly, roughly $1 per company. If you ran the
default three and it cost much more, that's worth an issue.

## Clean up

**Worth actually running on this one** — it's the only demo here that leaves objects in a
bucket as well as a dataset.

```bash
../../gxr down sec-filings
```

Or by hand:

```bash
bq --project_id="$GCP_PROJECT" rm -r -f --dataset "$GCP_PROJECT:$BQ_DATASET"
gsutil -m rm -r "gs://$GCS_BUCKET/kineviz-sec-demo/"
rm -rf .upstream
```

Teardown is scoped to the `kineviz-sec-demo/` prefix and never touches the rest of your
bucket. Your Kineviz project is separate — delete it in Kineviz Desktop if you no longer
want it.

## What's next

- [`cloud-audit-access`](../cloud-audit-access/) — the cheapest demo here, synthetic data
- [`supply-chain-deps`](../supply-chain-deps/) — dependency risk on deps.dev
- [`Kineviz/fortune500`](https://github.com/Kineviz/fortune500) — the pipeline this wraps
