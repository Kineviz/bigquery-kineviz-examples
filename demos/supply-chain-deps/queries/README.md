# Queries

One question per file. Run them in Kineviz's query panel, or with `bq` — the
`${PROJECT}` / `${DATASET}` / `${GRAPH}` placeholders come from your `.env`.

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
