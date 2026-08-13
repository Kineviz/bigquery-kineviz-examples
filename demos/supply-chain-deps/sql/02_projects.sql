-- Backing repos for a bounded, LITERAL list of packages.
--
-- Rendered separately by scripts/setup.sh, after 01_materialize.sql has run,
-- because the package names have to be baked in as literals.
--
-- PackageVersionToProject is 2.4 TB clustered by (System, Name).
-- `Name IN ('react','vue',...)`        -> pruned, ~1 GB
-- `Name IN (SELECT id FROM t LIMIT n)` -> NOT pruned, ~6.6 GB, regardless of n
--
-- That distinction is the whole reason this is a separate file.
--
-- Substituted by scripts/setup.sh:
--   ${PROJECT} ${DATASET} ${SYSTEM} ${SNAPSHOT} ${FOCUS}

CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.raw_pkg_project` AS
SELECT DISTINCT
  p.Name        AS pkg_name,
  p.ProjectName AS project_name
FROM `bigquery-public-data.deps_dev_v1.PackageVersionToProject` AS p
WHERE p.SnapshotAt >= TIMESTAMP('${SNAPSHOT}')
  AND p.SnapshotAt <  TIMESTAMP_ADD(TIMESTAMP('${SNAPSHOT}'), INTERVAL 1 DAY)
  AND p.System = '${SYSTEM}'
  AND p.Name IN (${FOCUS})
  AND p.ProjectName IS NOT NULL;

CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.nodes_project` AS
SELECT
  pr.Name            AS id,
  pr.Name            AS name,
  pr.Type            AS host,
  pr.StarsCount      AS stars,
  pr.ForksCount      AS forks,
  pr.OpenIssuesCount AS open_issues,
  pr.Licenses        AS licenses,
  pr.Description     AS description
FROM `bigquery-public-data.deps_dev_v1.Projects` AS pr
WHERE pr.SnapshotAt >= TIMESTAMP('${SNAPSHOT}')
  AND pr.SnapshotAt <  TIMESTAMP_ADD(TIMESTAMP('${SNAPSHOT}'), INTERVAL 1 DAY)
  AND pr.Name IN (SELECT project_name FROM `${PROJECT}.${DATASET}.raw_pkg_project`);

CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.edges_maintained_in` AS
SELECT
  pp.pkg_name     AS src_id,
  pp.project_name AS dst_id
FROM `${PROJECT}.${DATASET}.raw_pkg_project` AS pp
WHERE pp.project_name IN (SELECT id FROM `${PROJECT}.${DATASET}.nodes_project`);
