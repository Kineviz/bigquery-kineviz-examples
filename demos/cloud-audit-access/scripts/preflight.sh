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
require_env GCP_PROJECT BQ_DATASET BQ_GRAPH BQ_LOCATION AUDIT_EVENTS AUDIT_SEED MAX_BYTES_BILLED

[ "$GCP_PROJECT" != "your-project-id" ] || die "GCP_PROJECT is still the placeholder." \
  "Set a real project ID in .env. Nothing has been created yet."

require_cli gcloud bq python3

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

ok "data is synthetic — no public dataset is read, so setup costs a fraction of a cent"

if ! bq --project_id="$GCP_PROJECT" ls --reservation --location="$BQ_LOCATION" 2>/dev/null | grep -qi 'ENTERPRISE'; then
  warn "No Enterprise/Enterprise Plus reservation found in $BQ_LOCATION."
  dim "GQL queries need one while BigQuery Graph is pre-GA. Setup will still run,"
  dim "but the verify step may fail. See docs/PREVIEW_NOTES.md."
else
  ok "Enterprise reservation found in $BQ_LOCATION"
fi

require_kineviz_desktop "0.17.1"
ok "preflight passed — nothing has been created yet"
