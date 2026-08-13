#!/usr/bin/env bash
# Check everything before creating anything.
#
# Failing here is cheap and deliberate: no BigQuery resource exists yet, so the
# person can fix and re-run with nothing to clean up and nothing billed.
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
require_env GCP_PROJECT BQ_DATASET BQ_GRAPH BQ_LOCATION DEPS_SYSTEM DEPS_SNAPSHOT DEPS_SEEDS DEPS_MAX_DEPTH DEPS_PROJECT_LOOKUP_LIMIT MAX_BYTES_BILLED

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

# Google's docs mention an Enterprise reservation requirement for GQL while
# BigQuery Graph is pre-GA. We verified GQL working on on-demand pricing with no
# reservation (see docs/PREVIEW_NOTES.md), so absence of one is reported as
# information, not a warning — and never blocks.
if ! bq --project_id="$GCP_PROJECT" ls --reservation --location="$BQ_LOCATION" 2>/dev/null | grep -qi 'ENTERPRISE'; then
  dim "no BigQuery reservation in $BQ_LOCATION — that is fine"
  dim "GQL was verified working on on-demand pricing; see docs/PREVIEW_NOTES.md"
else
  ok "Enterprise reservation found in $BQ_LOCATION"
fi

# deps.dev snapshots land weekly. A date that is not a real snapshot prunes to
# an empty partition and yields an empty graph with no error at all, so check it
# before spending anything.
if bq --project_id="$GCP_PROJECT" query --use_legacy_sql=false --format=csv --quiet \
     --maximum_bytes_billed=2000000000 \
     "SELECT 1 FROM \`bigquery-public-data.deps_dev_v1.INFORMATION_SCHEMA.PARTITIONS\`
      WHERE table_name='Dependencies'
        AND partition_id = FORMAT_DATE('%Y%m%d', DATE '$DEPS_SNAPSHOT')" 2>/dev/null \
   | tail -n +2 | grep -q 1; then
  ok "deps.dev snapshot $DEPS_SNAPSHOT exists"
else
  die "No deps.dev snapshot on $DEPS_SNAPSHOT." \
      "Snapshots are weekly. List recent ones: bq query --use_legacy_sql=false \"SELECT partition_id FROM \\\`bigquery-public-data.deps_dev_v1.INFORMATION_SCHEMA.PARTITIONS\\\` WHERE table_name='Dependencies' ORDER BY partition_id DESC LIMIT 5\""
fi

if bq --project_id="$GCP_PROJECT" show --dataset "$GCP_PROJECT:$BQ_DATASET" >/dev/null 2>&1; then
  warn "Dataset $BQ_DATASET already exists — setup will replace its tables (it is idempotent)."
fi

# Account, install, sign-in: three things only the person can do.
require_kineviz_desktop "0.17.1"

ok "preflight passed — nothing has been created yet"
info "Next: ./scripts/setup.sh (creates ${GCP_PROJECT}.${BQ_DATASET}, ~\$0.05)"
