# Queries

One question per file. Run them in Kineviz's query panel, or with `bq` — the
`${GCP_PROJECT}` / `${BQ_DATASET}` / `${BQ_GRAPH}` placeholders come from your `.env`.

| File | The question it answers |
|---|---|
| `01-fan-in.gql` | Which packages does the most of this ecosystem depend on? |
| `02-bus-factor.gql` | Which widely-used packages sit on an under-resourced repo? |
| `03-transitive-blast-radius.gql` | If one package were compromised, what is reachable within three hops? |
| `04-shared-project.gql` | Which seemingly-independent packages share one backing repo? |

Run one from the shell:

```bash
set -a; . ../.env; set +a
envsubst < 01-fan-in.gql | bq query --use_legacy_sql=false \
  --maximum_bytes_billed="$MAX_BYTES_BILLED"
```

`03` is the one worth running in Kineviz rather than the CLI — the shape of the
result is the finding.

## Why these use `${GCP_PROJECT}` and not `${PROJECT}`

The files in `sql/` are rendered by `scripts/setup.sh`, which supplies its own
placeholder names. These query files are rendered by **your shell**, via
`envsubst`, so their placeholders have to match the variable names in `.env`
exactly — otherwise `envsubst` substitutes empty strings and you get
``GRAPH `..` `` with no error.
