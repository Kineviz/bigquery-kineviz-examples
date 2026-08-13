-- Define the property graph over the materialized tables.
--
-- This is the piece Kineviz connects to: two node labels, two edge labels.
-- Substituted by scripts/setup.sh: ${PROJECT} ${DATASET} ${GRAPH}

CREATE OR REPLACE PROPERTY GRAPH `${PROJECT}.${DATASET}.${GRAPH}`
  NODE TABLES (
    `${PROJECT}.${DATASET}.nodes_package`
      KEY (id)
      LABEL Package
      PROPERTIES (id, name, system, dependents_in_graph, is_seed),

    `${PROJECT}.${DATASET}.nodes_project`
      KEY (id)
      LABEL Project
      PROPERTIES (id, name, host, stars, forks, open_issues, licenses, description)
  )
  EDGE TABLES (
    `${PROJECT}.${DATASET}.edges_depends_on`
      KEY (src_id, dst_id)
      SOURCE KEY (src_id) REFERENCES `${PROJECT}.${DATASET}.nodes_package` (id)
      DESTINATION KEY (dst_id) REFERENCES `${PROJECT}.${DATASET}.nodes_package` (id)
      LABEL DEPENDS_ON
      PROPERTIES (minimum_depth),

    `${PROJECT}.${DATASET}.edges_maintained_in`
      KEY (src_id, dst_id)
      SOURCE KEY (src_id) REFERENCES `${PROJECT}.${DATASET}.nodes_package` (id)
      DESTINATION KEY (dst_id) REFERENCES `${PROJECT}.${DATASET}.nodes_project` (id)
      LABEL MAINTAINED_IN
  );
