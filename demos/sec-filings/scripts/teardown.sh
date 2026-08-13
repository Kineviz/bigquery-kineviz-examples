#!/usr/bin/env bash
# Delete exactly what this demo created — the BigQuery dataset, the GCS staging
# prefix, and the local upstream clone. Nothing else in the bucket is touched.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/lib/common.sh"
eval "$(parse_common_flags "$@")"
# shellcheck disable=SC2034  # read by the logging helpers in common.sh
GXR_STEP=teardown
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step "Teardown — removing what this demo created"
load_env "$DEMO_DIR"
require_env GCP_PROJECT BQ_DATASET GCS_BUCKET

if bq --project_id="$GCP_PROJECT" show --dataset "$GCP_PROJECT:$BQ_DATASET" >/dev/null 2>&1; then
  bq --project_id="$GCP_PROJECT" rm -r -f --dataset "$GCP_PROJECT:$BQ_DATASET" \
    || die "Failed to delete dataset $BQ_DATASET." \
           "Delete it by hand: bq rm -r -f --dataset $GCP_PROJECT:$BQ_DATASET"
  ok "deleted dataset ${GCP_PROJECT}.${BQ_DATASET}"
else
  info "dataset ${BQ_DATASET} does not exist — nothing to delete"
fi

# Scoped to our own prefix. Never `gsutil rm -r gs://$GCS_BUCKET` — the bucket
# is the person's and may hold anything.
if gsutil ls "gs://$GCS_BUCKET/kineviz-sec-demo/" >/dev/null 2>&1; then
  gsutil -q -m rm -r "gs://$GCS_BUCKET/kineviz-sec-demo/" \
    && ok "removed gs://$GCS_BUCKET/kineviz-sec-demo/"
else
  info "no staged objects under gs://$GCS_BUCKET/kineviz-sec-demo/"
  dim "if the upstream pipeline staged elsewhere in this bucket, remove those by hand"
fi

rm -rf "$DEMO_DIR/.upstream" "$DEMO_DIR/.verified_rows"
ok "removed the local upstream clone"
info "Your Kineviz project and your GCS bucket still exist — this only removed what the demo added."
