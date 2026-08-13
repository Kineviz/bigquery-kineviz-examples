-- The property graph Kineviz connects to: two node labels, two edge labels.
-- Substituted by scripts/setup.sh: ${PROJECT} ${DATASET} ${GRAPH}

CREATE OR REPLACE PROPERTY GRAPH `${PROJECT}.${DATASET}.${GRAPH}`
  NODE TABLES (
    `${PROJECT}.${DATASET}.nodes_principal`
      KEY (id)
      LABEL Principal
      PROPERTIES (id, name, principal_type, roles, successful_calls, denied_calls),

    `${PROJECT}.${DATASET}.nodes_resource`
      KEY (id)
      LABEL Resource
      PROPERTIES (id, name, resource_type, sensitivity, access_count)
  )
  EDGE TABLES (
    `${PROJECT}.${DATASET}.edges_accessed`
      KEY (src_id, dst_id)
      SOURCE KEY (src_id) REFERENCES `${PROJECT}.${DATASET}.nodes_principal` (id)
      DESTINATION KEY (dst_id) REFERENCES `${PROJECT}.${DATASET}.nodes_resource` (id)
      LABEL ACCESSED
      PROPERTIES (call_count, success_count, denied_count, methods, max_severity_tier, first_seen, last_seen),

    `${PROJECT}.${DATASET}.edges_can_impersonate`
      KEY (src_id, dst_id)
      SOURCE KEY (src_id) REFERENCES `${PROJECT}.${DATASET}.nodes_principal` (id)
      DESTINATION KEY (dst_id) REFERENCES `${PROJECT}.${DATASET}.nodes_principal` (id)
      LABEL CAN_IMPERSONATE
      PROPERTIES (grant_type)
  );
