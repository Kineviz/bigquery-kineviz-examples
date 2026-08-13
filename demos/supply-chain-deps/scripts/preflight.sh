#!/usr/bin/env bash
# Check everything before creating anything.
#
# Failing here is cheap and deliberate: no BigQuery resource exists yet, so the
# person can fix and re-run with nothing to clean up and nothing billed.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/lib/common.sh"
eval "$(parse_common_flags "$@")"
GXR_STEP=preflight
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step "Preflight — checking prerequisites (nothing will be created)"

[ -f "$DEMO_DIR/.env" ] || die "No .env found." \
  "cp .env.example .env, set GCP_PROJECT, then re-run. Nothing has been created yet."
load_env "$DEMO_DIR"
require_env GCP_PROJECT BQ_DATASET BQ_GRAPH BQ_LOCATION DEPS_SYSTEM TOP_N_PACKAGES MAX_BYTES_BILLED

[ "$GCP_PROJECT" != "your-project-id" ] || die "GCP_PROJECT is still the placeholder." \
  "Set a real project ID in .env. Nothing has been created yet."

require_cli gcloud bq

gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | grep -q . \
  || die "No active gcloud credentials." \
         "Run 'gcloud auth login' then 'gcloud auth application-default login', and re-run."
ok "gcloud authenticated"

gcloud projects describe "$GCP_PROJECT" --format='value(projectId)' >/dev/null 2>&1 \
  || die "Cannot access project '$GCP_PROJECT'." \
         "Check the ID in .env and that your account has access. Nothing has been created yet."
ok "project $GCP_PROJECT reachable"

gcloud services list --enabled --project="$GCP_PROJECT" \
  --filter='config.name:bigquery.googleapis.com' --format='value(config.name)' 2>/dev/null \
  | grep -q bigquery \
  || die "The BigQuery API is not enabled on '$GCP_PROJECT'." \
         "Run: gcloud services enable bigquery.googleapis.com --project=$GCP_PROJECT"
ok "BigQuery API enabled"

# Can we actually run a job? Cheaper to find out now than mid-setup.
bq --project_id="$GCP_PROJECT" query --use_legacy_sql=false --format=none --quiet \
   --maximum_bytes_billed=10000000 'SELECT 1' >/dev/null 2>&1 \
  || die "Cannot run BigQuery jobs in '$GCP_PROJECT'." \
         "You need roles/bigquery.jobUser and roles/bigquery.dataEditor. See connect/service-account.md."
ok "BigQuery jobs runnable"

# BigQuery Graph is pre-GA: GQL needs an Enterprise reservation. This is the
# single most common cause of a first run failing, so warn loudly and early —
# but do not block, since GRAPH_EXPAND still works on on-demand pricing.
if ! bq --project_id="$GCP_PROJECT" ls --reservation --location="$BQ_LOCATION" 2>/dev/null | grep -qi 'ENTERPRISE'; then
  warn "No Enterprise/Enterprise Plus reservation found in $BQ_LOCATION."
  dim "GQL queries need one while BigQuery Graph is pre-GA. Setup will still run,"
  dim "but the verify step may fail. See docs/PREVIEW_NOTES.md."
else
  ok "Enterprise reservation found in $BQ_LOCATION"
fi

if bq --project_id="$GCP_PROJECT" show --dataset "$GCP_PROJECT:$BQ_DATASET" >/dev/null 2>&1; then
  warn "Dataset $BQ_DATASET already exists — setup will replace its tables (it is idempotent)."
fi

# Account, install, sign-in: three things only the person can do.
require_kineviz_desktop "0.17.1"

ok "preflight passed — nothing has been created yet"
info "Next: ./scripts/setup.sh (creates ${GCP_PROJECT}.${BQ_DATASET}, ~\$0.05)"
