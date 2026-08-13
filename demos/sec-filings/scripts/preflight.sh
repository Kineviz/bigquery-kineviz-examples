#!/usr/bin/env bash
# Check everything before creating anything. Creates nothing, bills nothing.
#
# This demo has more moving parts than the others — Vertex AI, a GCS bucket, and
# an upstream repo — so preflight is correspondingly stricter. Every one of these
# checks exists because failing it halfway through costs real money.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/lib/common.sh"
eval "$(parse_common_flags "$@")"
# shellcheck disable=SC2034  # read by the logging helpers in common.sh
GXR_STEP=preflight
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step "Preflight — checking prerequisites (nothing will be created)"

[ -f "$DEMO_DIR/.env" ] || die "No .env found." \
  "cp .env.example .env, set GCP_PROJECT and GCS_BUCKET, then re-run. Nothing has been created yet."
load_env "$DEMO_DIR"
require_env GCP_PROJECT GCS_BUCKET BQ_DATASET BQ_GRAPH BQ_LOCATION SEC_TICKERS GEMINI_MODEL

[ "$GCP_PROJECT" != "your-project-id" ] || die "GCP_PROJECT is still the placeholder." \
  "Set a real project ID in .env. Nothing has been created yet."
[ "$GCS_BUCKET" != "your-bucket-name" ] || die "GCS_BUCKET is still the placeholder." \
  "Set a real bucket in .env. Nothing has been created yet."

require_cli gcloud bq git python3 gsutil

gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | grep -q . \
  || die "No active gcloud credentials." \
         "Run 'gcloud auth login' then 'gcloud auth application-default login', and re-run."
ok "gcloud authenticated"

gcloud projects describe "$GCP_PROJECT" --format='value(projectId)' >/dev/null 2>&1 \
  || die "Cannot access project '$GCP_PROJECT'." "Check the ID in .env."
ok "project $GCP_PROJECT reachable"

for api in bigquery.googleapis.com aiplatform.googleapis.com storage.googleapis.com; do
  gcloud services list --enabled --project="$GCP_PROJECT" \
    --filter="config.name:$api" --format='value(config.name)' 2>/dev/null | grep -q . \
    || die "The API '$api' is not enabled on '$GCP_PROJECT'." \
           "Run: gcloud services enable $api --project=$GCP_PROJECT"
done
ok "BigQuery, Vertex AI, and Cloud Storage APIs enabled"

gsutil ls -b "gs://$GCS_BUCKET" >/dev/null 2>&1 \
  || die "Bucket 'gs://$GCS_BUCKET' does not exist or you cannot read it." \
         "Create it: gsutil mb -p $GCP_PROJECT -l $BQ_LOCATION gs://$GCS_BUCKET"
ok "bucket gs://$GCS_BUCKET reachable"

bq --project_id="$GCP_PROJECT" query --use_legacy_sql=false --format=none --quiet \
   --maximum_bytes_billed=10000000 'SELECT 1' >/dev/null 2>&1 \
  || die "Cannot run BigQuery jobs in '$GCP_PROJECT'." \
         "You need roles/bigquery.jobUser and roles/bigquery.dataEditor."
ok "BigQuery jobs runnable"

# The upstream pipeline needs a BigQuery -> Vertex AI connection to call Gemini.
# Missing this is the single most common failure, and it fails deep into the run.
if bq --project_id="$GCP_PROJECT" ls --connection --location="$BQ_LOCATION" 2>/dev/null \
     | grep -q 'vertex_ai_connection'; then
  ok "BigQuery connection 'vertex_ai_connection' found"
else
  die "No BigQuery connection named 'vertex_ai_connection' in $BQ_LOCATION." \
      "$(cat <<EOF
create it, then grant its service account roles/aiplatform.user:
      bq mk --connection --location=$BQ_LOCATION --project_id=$GCP_PROJECT \\
        --connection_type=CLOUD_RESOURCE vertex_ai_connection
      bq show --connection $GCP_PROJECT.$BQ_LOCATION.vertex_ai_connection   # note the serviceAccountId
      gcloud projects add-iam-policy-binding $GCP_PROJECT \\
        --member=serviceAccount:<THAT_SERVICE_ACCOUNT> --role=roles/aiplatform.user
EOF
)"
fi

if ! bq --project_id="$GCP_PROJECT" ls --reservation --location="$BQ_LOCATION" 2>/dev/null | grep -qi 'ENTERPRISE'; then
  dim "no BigQuery reservation in $BQ_LOCATION — that is fine"
  dim "GQL was verified working on on-demand pricing; see docs/PREVIEW_NOTES.md"
else
  ok "Enterprise reservation found in $BQ_LOCATION"
fi

# Cost is driven by ticker count, so say the number out loud before spending it.
n=$(printf '%s' "$SEC_TICKERS" | tr ',' '\n' | grep -c . || echo 0)
ok "SEC_TICKERS lists $n compan$([ "$n" = 1 ] && echo y || echo ies): $SEC_TICKERS"
if [ "$n" -gt 10 ]; then
  warn "$n companies is well beyond the ~\$3 estimate — Gemini cost scales linearly."
  dim "Roughly \$1 per company. Reduce SEC_TICKERS in .env if that was not deliberate."
fi

require_kineviz_desktop "0.17.1"
ok "preflight passed — nothing has been created yet"
