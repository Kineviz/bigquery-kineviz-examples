# Queries

One question per file. Run them in Kineviz's query panel, or with `bq` — the
`${GCP_PROJECT}` / `${BQ_DATASET}` / `${BQ_GRAPH}` placeholders come from your `.env`.

| File | The question it answers |
|---|---|
| `01-value-hubs.gql` | Where does value concentrate in a single day? |
| `02-follow-the-money.gql` | Where does value go, two hops out from one address? |
| `03-contract-magnets.gql` | Which contracts pull in the most ETH, and from how many wallets? |
| `04-pass-through.gql` | Which wallets forward almost everything they receive? |

Run one from the shell:

```bash
set -a; . ../.env; set +a
envsubst < 01-value-hubs.gql | bq query --use_legacy_sql=false \
  --maximum_bytes_billed="$MAX_BYTES_BILLED"
```

`02` and `04` are the ones worth running in Kineviz rather than the CLI — the
shape of the result is the finding.

**Start with `01`.** It gives you the addresses to paste into `02`, and it tells
you which hubs are just exchanges so you do not over-read a path that runs
through one.

## Why these use `${GCP_PROJECT}` and not `${PROJECT}`

The files in `sql/` are rendered by `scripts/setup.sh`, which supplies its own
placeholder names. These query files are rendered by **your shell**, via
`envsubst`, so their placeholders have to match the variable names in `.env`
exactly — otherwise `envsubst` substitutes empty strings and you get
``GRAPH `..` `` with no error.
