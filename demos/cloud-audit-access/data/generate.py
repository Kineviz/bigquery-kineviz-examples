#!/usr/bin/env python3
"""Generate synthetic Cloud Audit Log records shaped like the real thing.

Why synthetic: real audit logs are the most sensitive data most organizations
have, so a public example repo cannot ship them and should not ask you to point
a demo at yours on the first run. The schema here mirrors the fields that matter
for access analysis in `cloudaudit_googleapis_com_activity` — principal, method,
resource, and the impersonation chain — so the graph and the queries transfer
directly to real logs.

Deterministic: same seed, same graph, including the escalation paths the demo's
queries are meant to find. Planted findings are documented in FINDINGS below
rather than left for the reader to trip over.

Writes newline-delimited JSON, which `bq load` reads natively.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import random

# Roles, ordered by how much damage they permit. Used to decide which
# escalation paths are worth planting and which are noise.
ROLE_TIERS = {
    "roles/viewer": 1,
    "roles/bigquery.dataViewer": 1,
    "roles/logging.viewer": 1,
    "roles/storage.objectViewer": 1,
    "roles/bigquery.dataEditor": 2,
    "roles/storage.objectAdmin": 2,
    "roles/compute.instanceAdmin": 3,
    "roles/iam.serviceAccountTokenCreator": 3,
    "roles/owner": 4,
}

METHODS = [
    ("storage.objects.get", "storage.googleapis.com", 1),
    ("storage.objects.list", "storage.googleapis.com", 1),
    ("bigquery.jobs.create", "bigquery.googleapis.com", 1),
    ("bigquery.tables.getData", "bigquery.googleapis.com", 2),
    ("storage.objects.create", "storage.googleapis.com", 2),
    ("compute.instances.start", "compute.googleapis.com", 3),
    ("iam.serviceAccounts.getAccessToken", "iamcredentials.googleapis.com", 3),
    ("secretmanager.versions.access", "secretmanager.googleapis.com", 4),
]

RESOURCES = [
    ("gs://acme-public-assets", "storage.bucket", "low"),
    ("gs://acme-analytics-export", "storage.bucket", "low"),
    ("gs://acme-customer-pii", "storage.bucket", "high"),
    ("gs://acme-backups", "storage.bucket", "high"),
    ("bq://acme-prod.telemetry", "bigquery.dataset", "low"),
    ("bq://acme-prod.billing", "bigquery.dataset", "medium"),
    ("bq://acme-prod.customer_records", "bigquery.dataset", "high"),
    ("secret://acme-prod/stripe-live-key", "secret", "critical"),
    ("secret://acme-prod/db-root-password", "secret", "critical"),
    ("compute://acme-prod/bastion-01", "compute.instance", "medium"),
]

# What the demo's queries are supposed to surface. Planted deliberately so the
# demo has a real answer rather than whatever randomness produced.
FINDINGS = """
Planted findings — what the demo's queries should surface:

  1. dana@acme.example holds only viewer-tier roles and touches nothing
     sensitive directly, but can impersonate sa-etl-runner@, which reads
     gs://acme-customer-pii. Two hops to high-sensitivity data, invisible to a
     review that only looks at direct grants.

  2. sa-ci-deployer@ can impersonate sa-secrets-reader@, which accesses
     secret://acme-prod/stripe-live-key. A service-account chain with no human
     in it, so it never appears in a user access review at all.

  3. contractor-priya@ reaches gs://acme-customer-pii through TWO different
     service accounts (sa-etl-runner@ and sa-backup-agent@). Revoking one
     leaves the path open — exactly the mistake graph analysis catches and a
     list of grants does not.

Only three principals touch sensitive resources directly, and all three are
service accounts. Every other route to that data is an escalation path.
"""

HUMANS = [
    "dana", "marcus", "priya", "wei", "sofia", "james", "aisha", "tom",
    "lena", "omar", "grace", "hugo",
]
SERVICE_ACCOUNTS = [
    "sa-etl-runner", "sa-ci-deployer", "sa-secrets-reader", "sa-backup-agent",
    "sa-metrics-collector", "sa-report-builder",
]


def build(rng: random.Random, n_principals: int, n_events: int, days: int, start: dt.datetime):
    """Build principals, impersonation grants, and access events.

    The critical property: **most principals cannot reach sensitive resources.**
    An earlier version drew events uniformly over all principals and resources,
    which meant everyone touched everything and the planted escalation paths were
    indistinguishable from background — 55 "findings" in a 19-principal org.
    Real access is scoped, so each principal here gets an explicit resource scope
    and events are drawn only from it.
    """
    def sa_email(short: str) -> str:
        return f"{short}@acme-prod.iam.gserviceaccount.com"

    by_sens = {s: [r for r in RESOURCES if r[2] == s]
               for s in ("low", "medium", "high", "critical")}

    principals = []

    # Humans: routine, low-sensitivity work. None of them reach high or critical
    # data directly — that is the whole point of the demo.
    for name in HUMANS[: max(6, n_principals // 4)]:
        principals.append({
            "principal": f"{name}@acme.example",
            "principal_type": "user",
            "roles": rng.sample([r for r, t in ROLE_TIERS.items() if t <= 2],
                                rng.randint(1, 2)),
            "_scope": rng.sample(by_sens["low"], 2) + rng.sample(by_sens["medium"], 1),
        })

    principals.append({
        "principal": "contractor-priya@partner.example",
        "principal_type": "user",
        "roles": ["roles/viewer"],
        "_scope": rng.sample(by_sens["low"], 1),
    })

    # Service accounts. Only these three touch anything sensitive, and each one
    # is the far end of a planted chain.
    sa_scopes = {
        "sa-etl-runner":        [by_sens["high"][0], by_sens["low"][1]],
        "sa-secrets-reader":    [by_sens["critical"][0]],
        "sa-backup-agent":      [by_sens["high"][0], by_sens["high"][1]],
        "sa-ci-deployer":       rng.sample(by_sens["low"], 2),
        "sa-metrics-collector": rng.sample(by_sens["low"], 2),
        "sa-report-builder":    rng.sample(by_sens["low"], 1) + rng.sample(by_sens["medium"], 1),
    }
    for sa, scope in sa_scopes.items():
        principals.append({
            "principal": sa_email(sa),
            "principal_type": "serviceAccount",
            "roles": rng.sample(list(ROLE_TIERS), rng.randint(1, 2)),
            "_scope": scope,
        })

    sensitive_sas = {sa_email(s) for s in
                     ("sa-etl-runner", "sa-secrets-reader", "sa-backup-agent")}

    # The three planted chains — the only routes to sensitive data.
    impersonations = [
        {"src_id": "dana@acme.example",
         "dst_id": sa_email("sa-etl-runner"), "grant": "explicit"},
        {"src_id": sa_email("sa-ci-deployer"),
         "dst_id": sa_email("sa-secrets-reader"), "grant": "explicit"},
        {"src_id": "contractor-priya@partner.example",
         "dst_id": sa_email("sa-etl-runner"), "grant": "explicit"},
        {"src_id": "contractor-priya@partner.example",
         "dst_id": sa_email("sa-backup-agent"), "grant": "inherited"},
    ]

    # Background impersonation noise, deliberately never pointing at a sensitive
    # service account — otherwise the noise manufactures findings of its own.
    harmless = [p["principal"] for p in principals
                if p["principal"] not in sensitive_sas]
    existing = {(i["src_id"], i["dst_id"]) for i in impersonations}
    for _ in range(max(3, n_principals // 10)):
        a, b = rng.sample(harmless, 2)
        if a != b and (a, b) not in existing:
            impersonations.append({"src_id": a, "dst_id": b, "grant": "inherited"})
            existing.add((a, b))

    # Events, drawn only from each principal's own scope.
    events = []
    for _ in range(n_events):
        p = rng.choice(principals)
        resource, res_type, sensitivity = rng.choice(p["_scope"])
        # Pick a method whose severity suits the resource, so the pair reads true.
        candidates = [m for m in METHODS if m[2] <= max(2, len(sensitivity) % 4 + 1)] or METHODS
        method, service, tier = rng.choice(candidates)
        ts = start + dt.timedelta(days=rng.randint(0, max(0, days - 1)),
                                  seconds=rng.randint(0, 86399))
        events.append({
            "timestamp": ts.replace(microsecond=0).isoformat() + "Z",
            "principal": p["principal"],
            "principal_type": p["principal_type"],
            "method_name": method,
            "service_name": service,
            "resource_name": resource,
            "resource_type": res_type,
            "sensitivity": sensitivity,
            "severity_tier": tier,
            # Most calls succeed; denials are the interesting minority.
            "status": "OK" if rng.random() > 0.06 else "PERMISSION_DENIED",
        })

    events.sort(key=lambda e: e["timestamp"])
    for p in principals:
        p.pop("_scope", None)
    return principals, impersonations, events


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default="generated", help="output directory")
    ap.add_argument("--principals", type=int, default=60)
    ap.add_argument("--events", type=int, default=6000)
    ap.add_argument("--days", type=int, default=14)
    ap.add_argument("--seed", type=int, default=20260813)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    # Fixed start date, not "today" — a demo that produces different data each
    # run cannot have a last_verified date that means anything.
    start = dt.datetime(2026, 7, 1)

    principals, impersonations, events = build(
        rng, args.principals, args.events, args.days, start
    )

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    def write(name: str, rows: list[dict]) -> None:
        p = out / name
        with p.open("w") as fh:
            for r in rows:
                fh.write(json.dumps(r) + "\n")
        print(f"  {p}  ({len(rows)} rows)")

    write("principals.ndjson", principals)
    write("impersonations.ndjson", impersonations)
    write("events.ndjson", events)

    print(FINDINGS)


if __name__ == "__main__":
    main()
