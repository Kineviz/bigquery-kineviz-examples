-- Shape the loaded audit records into node and edge tables.
--
-- The raw events land in `raw_events`; this file derives the graph from them.
-- Nothing here reads a public dataset — the data is synthetic and local — so the
-- cost is effectively zero. Substituted by scripts/setup.sh: ${PROJECT} ${DATASET}

-- Principals: users and service accounts, with how much they actually did.
CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.nodes_principal` AS
SELECT
  p.principal                        AS id,
  p.principal                        AS name,
  p.principal_type                   AS principal_type,
  ARRAY_TO_STRING(p.roles, ', ')     AS roles,
  COUNTIF(e.status = 'OK')           AS successful_calls,
  COUNTIF(e.status != 'OK')          AS denied_calls
FROM `${PROJECT}.${DATASET}.raw_principals` AS p
LEFT JOIN `${PROJECT}.${DATASET}.raw_events` AS e
  ON e.principal = p.principal
GROUP BY id, name, principal_type, roles;

-- Resources, carrying the sensitivity label that makes the queries meaningful.
CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.nodes_resource` AS
SELECT
  e.resource_name  AS id,
  e.resource_name  AS name,
  ANY_VALUE(e.resource_type) AS resource_type,
  ANY_VALUE(e.sensitivity)   AS sensitivity,
  COUNT(*)         AS access_count
FROM `${PROJECT}.${DATASET}.raw_events` AS e
GROUP BY id, name;

-- Who accessed what, aggregated. One edge per principal/resource pair rather
-- than one per log line — 6,000 events collapse to a graph you can read.
CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.edges_accessed` AS
SELECT
  e.principal              AS src_id,
  e.resource_name          AS dst_id,
  COUNT(*)                 AS call_count,
  COUNTIF(e.status != 'OK') AS denied_count,
  STRING_AGG(DISTINCT e.method_name ORDER BY e.method_name LIMIT 5) AS methods,
  MAX(e.severity_tier)     AS max_severity_tier,
  MIN(e.timestamp)         AS first_seen,
  MAX(e.timestamp)         AS last_seen
FROM `${PROJECT}.${DATASET}.raw_events` AS e
WHERE e.status = 'OK'
GROUP BY src_id, dst_id;

-- Who can impersonate whom. This is the edge that turns a list of grants into a
-- graph, and the one that makes escalation paths visible.
CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.edges_can_impersonate` AS
SELECT
  i.src_id AS src_id,
  i.dst_id AS dst_id,
  i.grant  AS grant_type
FROM `${PROJECT}.${DATASET}.raw_impersonations` AS i
WHERE i.src_id IN (SELECT id FROM `${PROJECT}.${DATASET}.nodes_principal`)
  AND i.dst_id IN (SELECT id FROM `${PROJECT}.${DATASET}.nodes_principal`);
