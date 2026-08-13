#!/usr/bin/env bash
# Check everything before creating anything. Creates nothing, bills nothing.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/lib/common.sh"
eval "$(parse_common_flags "$@")"
# shellcheck disable=SC2034  # read by the logging helpers in common.sh
GXR_STEP=preflight
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step "Preflight — checking prerequisites (nothing will be created)"

[ -f "$DEMO_DIR/.env" ] || die "No .env found." \
  "cp .env.example .env, set GCP_PROJECT, then re-run. Nothing has been created yet."
load_env "$DEMO_DIR"
require_env GCP_PROJECT BQ_DATASET BQ_GRAPH BQ_LOCATION ETH_DATE TOP_N_ADDRESSES MIN_ETH MAX_BYTES_BILLED

[ "$GCP_PROJECT" != "your-project-id" ] || die "GCP_PROJECT is still the placeholder." \
  "Set a real project ID in .env. Nothing has been created yet."

case "$ETH_DATE" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  *) die "ETH_DATE '$ETH_DATE' is not YYYY-MM-DD." \
         "Set a single date, e.g. ETH_DATE=2024-01-15. A malformed date would break partition pruning and scan far more than one day." ;;
esac
ok "ETH_DATE $ETH_DATE is well formed"

require_cli gcloud bq

gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | grep -q . \
  || die "No active gcloud credentials." \
         "Run 'gcloud auth login' then 'gcloud auth application-default login', and re-run."
ok "gcloud authenticated"

gcloud projects describe "$GCP_PROJECT" --format='value(projectId)' >/dev/null 2>&1 \
  || die "Cannot access project '$GCP_PROJECT'." \
         "Check the ID in .env and that your account has access. Nothing has been created yet."
ok "project $GCP_PROJECT reachable"

bq --project_id="$GCP_PROJECT" query --use_legacy_sql=false --format=none --quiet \
   --maximum_bytes_billed=10000000 'SELECT 1' >/dev/null 2>&1 \
  || die "Cannot run BigQuery jobs in '$GCP_PROJECT'." \
         "You need roles/bigquery.jobUser and roles/bigquery.dataEditor. See connect/service-account.md."
ok "BigQuery jobs runnable"

# Dry-run the real materialization query so the person sees the bill before it
# happens. This is the difference between a $0.20 demo and a surprise.
info "estimating scan size for $ETH_DATE (dry run, bills nothing)"
bytes=$(bq --project_id="$GCP_PROJECT" query --use_legacy_sql=false --dry_run --format=json \
  "SELECT COUNT(*) FROM \`bigquery-public-data.crypto_ethereum.transactions\`
   WHERE block_timestamp >= TIMESTAMP('$ETH_DATE 00:00:00 UTC')
     AND block_timestamp <  TIMESTAMP_ADD(TIMESTAMP('$ETH_DATE 00:00:00 UTC'), INTERVAL 1 DAY)" \
  2>/dev/null | sed -n 's/.*"totalBytesProcessed": *"\([0-9]*\)".*/\1/p' | head -1)

if [ -n "${bytes:-}" ] && [ "$bytes" -gt 0 ] 2>/dev/null; then
  gb=$(( bytes / 1073741824 ))
  ok "one-day partition scans ~${gb} GB (~\$$(awk -v b="$bytes" 'BEGIN{printf "%.2f", b/1099511627776*6.25}') at on-demand rates)"
  if [ "$bytes" -gt "$MAX_BYTES_BILLED" ]; then
    die "That day scans ${gb} GB, above your MAX_BYTES_BILLED ceiling." \
        "Pick a different ETH_DATE, or raise MAX_BYTES_BILLED in .env deliberately — knowing it raises the bill."
  fi
else
  warn "could not estimate scan size — continuing, but watch the first query"
fi

if ! bq --project_id="$GCP_PROJECT" ls --reservation --location="$BQ_LOCATION" 2>/dev/null | grep -qi 'ENTERPRISE'; then
  warn "No Enterprise/Enterprise Plus reservation found in $BQ_LOCATION."
  dim "GQL queries need one while BigQuery Graph is pre-GA. Setup will still run,"
  dim "but the verify step may fail. See docs/PREVIEW_NOTES.md."
else
  ok "Enterprise reservation found in $BQ_LOCATION"
fi

require_kineviz_desktop "0.17.1"
ok "preflight passed — nothing has been created yet"
