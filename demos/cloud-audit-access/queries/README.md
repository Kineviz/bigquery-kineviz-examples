# Queries

One question per file. Run them in Kineviz's query panel, or with `bq` — the
`${GCP_PROJECT}` / `${BQ_DATASET}` / `${BQ_GRAPH}` placeholders come from your `.env`.

| File | The question it answers |
|---|---|
| `01-escalation-paths.gql` | Who reaches sensitive data only by impersonating something else? |
| `02-blast-radius.gql` | Everything one principal can reach, directly or indirectly |
| `03-redundant-paths.gql` | Which sensitive resources are reachable by more than one route? |
| `04-denied-probing.gql` | Who is accumulating permission denials, and across how many resources? |

**Start with `01`.** It is the query this demo exists for, and it names the
principals worth pasting into `02`.

Run one from the shell:

```bash
set -a; . ../.env; set +a
envsubst < 01-escalation-paths.gql | bq query --use_legacy_sql=false \
  --maximum_bytes_billed="$MAX_BYTES_BILLED"
```

`02` is the one worth running in Kineviz rather than the CLI — reach is a shape.

## What you should find

The data is synthetic and seeded, so these are reproducible rather than lucky:

- **`dana@acme.example`** holds only viewer-tier roles, but impersonates
  `sa-etl-runner@` and through it reads `gs://acme-customer-pii`.
- **`sa-ci-deployer@` → `sa-secrets-reader@` → `secret://acme-prod/stripe-live-key`** —
  a service-account chain with no human in it, so it never appears in a user
  access review.
- **`contractor-priya@partner.example`** reaches `gs://acme-customer-pii` through
  *two* different service accounts. Revoking one changes nothing.

Only three principals touch sensitive resources directly, and all three are
service accounts. Every other route to that data is an escalation path.

## Why these use `${GCP_PROJECT}` and not `${PROJECT}`

The files in `sql/` are rendered by `scripts/setup.sh`, which supplies its own
placeholder names. These query files are rendered by **your shell**, via
`envsubst`, so their placeholders have to match the variable names in `.env`
exactly — otherwise `envsubst` substitutes empty strings and you get
``GRAPH `..` `` with no error.
