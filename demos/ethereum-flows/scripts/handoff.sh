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

✅ Demo ready: ethereum-flows
   Kineviz (formerly GraphXR)

   Dataset:   ${GCP_PROJECT}.${BQ_DATASET}   (${ETH_DATE}, top ${TOP_N_ADDRESSES} addresses)
   Graph:     ${BQ_GRAPH} — Address, Contract / SENT, CALLED
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
     1. Where does value concentrate?          queries/01-value-hubs.gql
     2. Two hops out from the biggest sender   queries/02-follow-the-money.gql
     3. Which contracts pull the most ETH?     queries/03-contract-magnets.gql
     4. Wallets that pass value straight on    queries/04-pass-through.gql

     Run 2 and 4 in Kineviz rather than the CLI — the shape is the finding.

   Cost so far: ~\$0.20.  Tear down with:  ./gxr down ethereum-flows

EOF
