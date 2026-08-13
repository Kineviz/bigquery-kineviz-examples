# BigQuery Graph + Kineviz

> **Kineviz** (formerly **GraphXR**) is Kineviz's graph visualization and analytics
> platform. Some product surfaces — the Google Cloud Marketplace listing, the
> `graphxr.kineviz.com` portal, and screenshots in this repo — still show the former name.

Explore [BigQuery property graphs](https://docs.cloud.google.com/bigquery/docs/graph-overview)
visually in Kineviz. Two ways in — pick the one that matches why you're here.

---

### 🔌 I have my own BigQuery data

**→ [`connect/`](connect/)** — point Kineviz at an existing property graph. About ten
minutes, no demo data, nothing to clone beyond this repo.

### 📊 Show me what this looks like

**→ [`demos/`](demos/)** — worked examples on public datasets. Each one creates a graph in
your project, verifies it, and hands you questions to ask.

---

## Demos

<!-- BEGIN GENERATED DEMOS -->

| Demo | What it shows | Level | Time | Cost |
|---|---|---|---|---|
| [`supply-chain-deps`](demos/supply-chain-deps/) _(preview)_ | Build a property graph over Google's deps.dev public dataset and trace transitive dependency risk to single-maintainer packages. | beginner | 12 min | ~$0.05 |

<!-- END GENERATED DEMOS -->

Generated from each demo's `demo.yaml` — edit that, not this table.

## Quick start

```bash
git clone https://github.com/Kineviz/bigquery-kineviz-examples
cd bigquery-kineviz-examples
./gxr list
./gxr up supply-chain-deps
```

`./gxr up` runs preflight, creates the resources, verifies with a real query, then tells you
exactly what to do in Kineviz Desktop. Prefer to see each command? Every demo README has a
step-by-step section with the literal `bq` and `gcloud` calls.

## What you need

1. **A Kineviz account** — [sign up](https://www.kineviz.com/). Kineviz Desktop is **free
   for individual use, forever**; the app requires sign-in, so do this first.
2. **[Kineviz Desktop](https://github.com/Kineviz/kineviz-desktop/releases)** v0.17.1+ —
   Windows, macOS, or Linux. ~600 MB installed, 16 GB RAM.
3. **A Google Cloud project** with billing enabled, plus `gcloud` and `bq`.

> **BigQuery Graph is pre-GA.** GQL queries need an **Enterprise** or **Enterprise Plus**
> reservation; on on-demand pricing, `GRAPH_EXPAND` works but full GQL doesn't. This is the
> most common reason a first run fails. See [`docs/PREVIEW_NOTES.md`](docs/PREVIEW_NOTES.md).

### Other ways to run Kineviz

Same connection flow in all three:

- **[GraphXR Explorer for BigQuery](https://console.cloud.google.com/marketplace/product/kineviz-public/graphxr-explorer-for-bigquery)**
  — Google Cloud Marketplace, runs entirely inside your own GCP project. The answer for
  regulated environments.
- **[Hosted portal](https://graphxr.kineviz.com/)** — nothing to install.

## Cost

Every demo bounds its queries with `maximum_bytes_billed`, materializes a small table rather
than rescanning a public dataset, and ships a teardown that deletes what it created. Per-demo
estimates are in [`docs/COSTS.md`](docs/COSTS.md) and in each `demo.yaml`.

```bash
./gxr down <demo>    # deletes everything that demo created
```

## Using an agent

Point Claude Code, Codex, or Cursor at this repo — [`AGENTS.md`](AGENTS.md) tells it how to
stand a demo up. It will collect your project ID, run the steps, verify with a real query,
and hand back. Three things it won't do, by design: create your Kineviz account, install
Desktop, or sign in for you.

## Repo layout

| Path | |
|---|---|
| [`connect/`](connect/) | Connect Kineviz to your own graph — standalone |
| [`demos/`](demos/) | Worked examples |
| [`docs/`](docs/) | Costs, troubleshooting, pre-GA notes |
| [`AGENTS.md`](AGENTS.md) | Agent entry point |
| `gxr` | `list · preflight · up · verify · down · doctor` |

## Related

- [`spanner-kineviz-examples`](https://github.com/Kineviz/spanner-kineviz-examples) — Spanner Graph
- [`alloydb-kineviz-examples`](https://github.com/Kineviz/alloydb-kineviz-examples) — AlloyDB and PostgreSQL
- [`kineviz-desktop`](https://github.com/Kineviz/kineviz-desktop) — the app

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Demo suggestions welcome — the dataset must be public
or synthetic.

## License

[MIT](LICENSE)
