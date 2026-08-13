# Queries

One question per file. Run them in Kineviz's query panel, or with `bq` — the
`${PROJECT}` / `${DATASET}` / `${GRAPH}` placeholders come from your `.env`.

| File | The question it answers |
|---|---|
| `01-markets-entered.gql` | Which markets does each company say it is entering? |
| `02-competitor-network.gql` | Who names whom as a competitor? |
| `03-shared-risks.gql` | Which risks does more than one company disclose? |
| `04-market-collisions.gql` | Which companies are converging on the same market? |

Run one from the shell:

```bash
set -a; . ../.env; set +a
envsubst < 01-markets-entered.gql | bq query --use_legacy_sql=false \
  --maximum_bytes_billed="$MAX_BYTES_BILLED"
```

`02` and `04` are the ones worth running in Kineviz rather than the CLI.

## A caveat worth keeping in mind

Every node and edge here was extracted from prose by a language model. That makes
it a genuinely useful index into thousands of pages nobody reads — and it means
individual claims can be wrong. The `evidence` property carries the passage each
extraction came from. **Check it before you act on anything**, which is exactly
the workflow the graph is meant to support: find the claim, then read the source.

The label set is defined by the upstream pipeline in
[Kineviz/fortune500](https://github.com/Kineviz/fortune500). If a query above
returns nothing, check the labels that pipeline actually produced at the pinned
commit — they may have changed.
