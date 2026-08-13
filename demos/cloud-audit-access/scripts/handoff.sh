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

✅ Demo ready: cloud-audit-access
   Kineviz (formerly GraphXR)

   Dataset:   ${GCP_PROJECT}.${BQ_DATASET}   (synthetic, ${AUDIT_EVENTS} events, seed ${AUDIT_SEED})
   Graph:     ${BQ_GRAPH} — Principal, Resource / ACCESSED, CAN_IMPERSONATE
   Verified:  ${rows} escalation path(s) found
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
     1. Who reaches sensitive data only by impersonation?  queries/01-escalation-paths.gql
     2. One principal's full blast radius                  queries/02-blast-radius.gql
     3. Resources reachable by more than one route         queries/03-redundant-paths.gql
     4. Who is accumulating permission denials?            queries/04-denied-probing.gql

     Run 2 in Kineviz rather than the CLI — reach is a shape.

   Cost so far: ~\$0.01.  Tear down with:  ./gxr down cloud-audit-access

EOF
