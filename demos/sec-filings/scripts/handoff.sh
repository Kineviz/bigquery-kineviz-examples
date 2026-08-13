#!/usr/bin/env bash
# Everything above was automatable. Everything below is the person's.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../../shared/lib/common.sh"
eval "$(parse_common_flags "$@")"
# shellcheck disable=SC2034  # read by the logging helpers in common.sh
GXR_STEP=handoff
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_env "$DEMO_DIR"
rows=$(cat "$DEMO_DIR/.verified_rows" 2>/dev/null || echo "?")
desktop="not detected"; kineviz_desktop_installed && desktop="detected"

cat <<EOF

✅ Demo ready: sec-filings
   Kineviz (formerly GraphXR)

   Dataset:   ${GCP_PROJECT}.${BQ_DATASET}   (${SEC_TICKERS})
   Graph:     ${BQ_GRAPH} — Company, Market, Risk, Competitor and more
   Verified:  GQL query returned ${rows} row(s)
   Desktop:   ${desktop}

   Last step — connect Kineviz (about 60 seconds):
     Open Kineviz Desktop → Create New Project
       → Database Type:             BigQuery Property Graph
       → Upload Service Account:    your service account JSON
       → Select Database:           ${BQ_DATASET}
       → Select location (Optional):${BQ_LOCATION}
       → Select Graph Database:     ${BQ_GRAPH}
     Walkthrough + screenshots: ../../connect/README.md

   Then try:
     1. Which markets is each company entering?     queries/01-markets-entered.gql
     2. Who names whom as a competitor?             queries/02-competitor-network.gql
     3. Risks more than one company shares          queries/03-shared-risks.gql
     4. Companies converging on the same market     queries/04-market-collisions.gql

     Run 2 and 4 in Kineviz rather than the CLI — the shape is the finding.

   Cost so far: ~\$3 for ${SEC_TICKERS}.  Tear down with:  ./gxr down sec-filings
   Teardown removes the dataset AND the staged GCS objects — worth running.

EOF
