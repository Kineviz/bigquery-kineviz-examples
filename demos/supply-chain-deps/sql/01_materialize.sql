-- Materialize a bounded slice of deps.dev into your own project.
--
-- Why this exists: bigquery-public-data.deps_dev_v1 is very large. Querying it
-- directly from a demo would be slow and expensive, and a public dataset makes
-- an unbounded scan easy to trigger by accident. So we copy one ecosystem's
-- most-depended-on packages once, and everything downstream reads that.
--
-- Parameters are substituted by scripts/setup.sh:
--   ${PROJECT} ${DATASET} ${SYSTEM} ${TOP_N}

-- Packages: the top N in one ecosystem, ranked by how many things depend on them.
CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.nodes_package` AS
WITH latest AS (
  SELECT
    Name AS name,
    System AS system,
    VersionInfo.Ordinal AS ordinal,
    Version AS version,
    ROW_NUMBER() OVER (PARTITION BY Name ORDER BY VersionInfo.Ordinal DESC) AS rn
  FROM `bigquery-public-data.deps_dev_v1.PackageVersions`
  WHERE System = '${SYSTEM}'
    AND VersionInfo.IsRelease
    AND SnapshotAt = (SELECT MAX(SnapshotAt) FROM `bigquery-public-data.deps_dev_v1.PackageVersions`)
),
ranked AS (
  SELECT
    d.Dependency.Name AS name,
    COUNT(DISTINCT d.Name) AS dependent_count
  FROM `bigquery-public-data.deps_dev_v1.Dependencies` d
  WHERE d.System = '${SYSTEM}'
    AND d.SnapshotAt = (SELECT MAX(SnapshotAt) FROM `bigquery-public-data.deps_dev_v1.Dependencies`)
  GROUP BY name
  ORDER BY dependent_count DESC
  LIMIT ${TOP_N}
)
SELECT
  r.name              AS id,
  r.name              AS name,
  '${SYSTEM}'         AS system,
  l.version           AS latest_version,
  r.dependent_count   AS dependent_count
FROM ranked r
LEFT JOIN latest l ON l.name = r.name AND l.rn = 1;

-- Dependency edges, restricted to packages already in the node table so the
-- graph is closed and every edge resolves.
CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.edges_depends_on` AS
SELECT DISTINCT
  d.Name                  AS src_id,
  d.Dependency.Name       AS dst_id,
  d.MinimumDepth          AS minimum_depth
FROM `bigquery-public-data.deps_dev_v1.Dependencies` d
WHERE d.System = '${SYSTEM}'
  AND d.SnapshotAt = (SELECT MAX(SnapshotAt) FROM `bigquery-public-data.deps_dev_v1.Dependencies`)
  AND d.Name             IN (SELECT id FROM `${PROJECT}.${DATASET}.nodes_package`)
  AND d.Dependency.Name  IN (SELECT id FROM `${PROJECT}.${DATASET}.nodes_package`);

-- Projects (repos) backing those packages, and the link between them. This is
-- what turns "which package" into "who actually maintains it".
CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.nodes_project` AS
SELECT
  p.Name          AS id,
  p.Name          AS name,
  p.Type          AS host,
  p.StarsCount    AS stars,
  p.ForksCount    AS forks,
  p.OpenIssuesCount AS open_issues,
  p.License       AS license
FROM `bigquery-public-data.deps_dev_v1.Projects` p
WHERE p.SnapshotAt = (SELECT MAX(SnapshotAt) FROM `bigquery-public-data.deps_dev_v1.Projects`)
  AND p.Name IN (
    SELECT DISTINCT pp.ProjectName
    FROM `bigquery-public-data.deps_dev_v1.PackageVersionToProject` pp
    WHERE pp.System = '${SYSTEM}'
      AND pp.SnapshotAt = (SELECT MAX(SnapshotAt) FROM `bigquery-public-data.deps_dev_v1.PackageVersionToProject`)
      AND pp.Name IN (SELECT id FROM `${PROJECT}.${DATASET}.nodes_package`)
  );

CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.edges_maintained_in` AS
SELECT DISTINCT
  pp.Name        AS src_id,
  pp.ProjectName AS dst_id
FROM `bigquery-public-data.deps_dev_v1.PackageVersionToProject` pp
WHERE pp.System = '${SYSTEM}'
  AND pp.SnapshotAt = (SELECT MAX(SnapshotAt) FROM `bigquery-public-data.deps_dev_v1.PackageVersionToProject`)
  AND pp.Name        IN (SELECT id FROM `${PROJECT}.${DATASET}.nodes_package`)
  AND pp.ProjectName IN (SELECT id FROM `${PROJECT}.${DATASET}.nodes_project`);
