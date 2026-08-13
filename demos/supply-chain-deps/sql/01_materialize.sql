-- Materialize a bounded slice of deps.dev into your own project.
--
-- COST NOTE — read before changing anything here.
--
-- deps_dev_v1.Dependencies is 105 TB across 1.19 trillion rows. It is
-- partitioned by SnapshotAt (DAY) and clustered by (System, Name, Version).
-- Every read below uses all three, because dropping any one of them is the
-- difference between cents and hundreds of dollars:
--
--   no filters                                    ~19.8 TB   ~$120
--   one snapshot + System='NPM'                    ~350 GB     ~$2.14
--   one snapshot + System + Name IN (seeds)          ~2 GB     ~$0.012
--
-- Two further traps, both of which produced silently wrong results here before:
--
--   * SnapshotAt is a TIMESTAMP, and the values are not at midnight. Exact
--     equality (SnapshotAt = TIMESTAMP('2026-08-10')) prunes to the right
--     partition and then matches ZERO rows. Use a half-open range.
--   * Computing "top N packages by dependent count" requires aggregating the
--     whole partition, which costs ~$2.50 no matter how small N is. Seeding
--     from a package list instead is what makes this demo cost pennies.
--
-- Substituted by scripts/setup.sh:
--   ${PROJECT} ${DATASET} ${SYSTEM} ${SNAPSHOT} ${SEEDS} ${MAX_DEPTH}

-- Direct and transitive dependencies of the seed packages.
CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.raw_deps` AS
SELECT
  d.Name            AS src_name,
  d.Dependency.Name AS dst_name,
  MIN(d.MinimumDepth) AS min_depth
FROM `bigquery-public-data.deps_dev_v1.Dependencies` AS d
WHERE d.SnapshotAt >= TIMESTAMP('${SNAPSHOT}')
  AND d.SnapshotAt <  TIMESTAMP_ADD(TIMESTAMP('${SNAPSHOT}'), INTERVAL 1 DAY)
  AND d.System = '${SYSTEM}'
  AND d.Name IN (${SEEDS})
  AND d.MinimumDepth BETWEEN 1 AND ${MAX_DEPTH}
GROUP BY src_name, dst_name;

-- Every package in the slice: the seeds plus everything they pull in.
CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.nodes_package` AS
WITH all_names AS (
  SELECT src_name AS name FROM `${PROJECT}.${DATASET}.raw_deps`
  UNION DISTINCT
  SELECT dst_name AS name FROM `${PROJECT}.${DATASET}.raw_deps`
),
fan_in AS (
  SELECT dst_name AS name, COUNT(DISTINCT src_name) AS dependents_in_graph
  FROM `${PROJECT}.${DATASET}.raw_deps`
  GROUP BY name
)
SELECT
  a.name                                AS id,
  a.name                                AS name,
  '${SYSTEM}'                           AS system,
  COALESCE(f.dependents_in_graph, 0)    AS dependents_in_graph,
  a.name IN (${SEEDS})                  AS is_seed
FROM all_names AS a
LEFT JOIN fan_in AS f USING (name);

CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.edges_depends_on` AS
SELECT
  r.src_name  AS src_id,
  r.dst_name  AS dst_id,
  r.min_depth AS minimum_depth
FROM `${PROJECT}.${DATASET}.raw_deps` AS r;
