# Troubleshooting

> **Kineviz** (formerly **GraphXR**) is Kineviz's graph visualization and analytics
> platform. Some product surfaces still show the former name.

Problems that span demos. Demo-specific issues are in each demo's README.

## Start here

```bash
./gxr doctor                                # is the repo itself intact?
./connect/verify.sh --project P --dataset D --graph G   # is the graph reachable?
```

`connect/verify.sh` is the fastest way to tell which side is at fault. If it passes and
Kineviz still can't see your graph, the problem is the connection settings, not BigQuery.

## Kineviz Desktop

**Won't sign in.** An account is required. [Sign up](https://www.kineviz.com/) — free for
individual use, forever, no trial clock.

**Not detected by preflight.** We look in the standard install location. If you installed
somewhere unusual, preflight's check is advisory — the demo still works. Install path by
platform: `/Applications/Kineviz Desktop.app` on macOS, the `kineviz-desktop` binary on
Linux.

**Which download?** macOS: menu → About This Mac → Chip. Apple M-series takes `arm64`, Intel
takes `x64`. Windows is almost always `x64`.

## Connecting

**"Graph not found" but it exists.** The region must match the dataset's location exactly.
`US` is a multi-region; `us-central1` is not the same thing.

```bash
bq show --format=prettyjson "$GCP_PROJECT:$BQ_DATASET" | grep location
```

**Dataset list is empty after uploading a key.** Usually a missing
`roles/bigquery.jobUser` — listing datasets requires running a job.

**"Permission denied" with a valid key.** The service account needs its roles on the project
that *owns the dataset*, which isn't always the project the key was created in.

## Queries

**A reservation or edition error.** BigQuery Graph is pre-GA and GQL needs an Enterprise or
Enterprise Plus reservation. See [PREVIEW_NOTES.md](PREVIEW_NOTES.md).

**`Exceeded maximum_bytes_billed`.** Working as designed. Reduce the amount of data — lower
`TOP_N_PACKAGES` or similar in `.env` — rather than raising the cap. If a demo's default
exceeds its own bound, that is a bug worth an issue.

## Scripts

**"No .env found."** `cp .env.example .env` in the demo directory and fill it in.

**Setup failed partway.** Re-run it. Every setup script is idempotent and uses
`CREATE OR REPLACE`, so it converges rather than duplicating.

**A script isn't executable.** `chmod +x` it, and please open an issue — CI is supposed to
catch that.

## Getting help

[Open an issue](../../../issues/new?template=demo-bug.yml) with the demo name, the step, the
full error including its `REMEDIATION:` line, and your versions.

**Redact project IDs, and never paste a service account key.** If a key has been exposed,
delete it first: `gcloud iam service-accounts keys delete <KEY_ID> --iam-account=<SA>`.
