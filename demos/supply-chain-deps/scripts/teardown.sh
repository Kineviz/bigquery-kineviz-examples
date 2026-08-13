#!/usr/bin/env bash
# Delete exactly what setup.sh created — the one dataset named in demo.yaml's
# `creates:` list. Never widen this.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/lib/common.sh"
eval "$(parse_common_flags "$@")"
# shellcheck disable=SC2034  # read by the logging helpers in common.sh
GXR_STEP=teardown
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step "Teardown — removing what this demo created"

load_env "$DEMO_DIR"
require_env GCP_PROJECT BQ_DATASET

if bq --project_id="$GCP_PROJECT" show --dataset "$GCP_PROJECT:$BQ_DATASET" >/dev/null 2>&1; then
  bq --project_id="$GCP_PROJECT" rm -r -f --dataset "$GCP_PROJECT:$BQ_DATASET" \
    || die "Failed to delete dataset $BQ_DATASET." \
           "Delete it by hand: bq rm -r -f --dataset $GCP_PROJECT:$BQ_DATASET"
  ok "deleted dataset ${GCP_PROJECT}.${BQ_DATASET}"
else
  info "dataset ${BQ_DATASET} does not exist — nothing to delete"
fi

rm -f "$DEMO_DIR/.verified_rows"

info "Two things this did NOT touch, on purpose:"
dim "· your Kineviz project — delete it in Kineviz Desktop if you no longer want it"
dim "· your service account key — delete it if you created one just for this demo"
