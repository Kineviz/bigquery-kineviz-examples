-- The property graph Kineviz connects to: two node labels, two edge labels.
-- Substituted by scripts/setup.sh: ${PROJECT} ${DATASET} ${GRAPH}

CREATE OR REPLACE PROPERTY GRAPH `${PROJECT}.${DATASET}.${GRAPH}`
  NODE TABLES (
    `${PROJECT}.${DATASET}.nodes_address`
      KEY (id)
      LABEL Address
      PROPERTIES (id, address, total_eth, transfer_count),

    `${PROJECT}.${DATASET}.nodes_contract`
      KEY (id)
      LABEL Contract
      PROPERTIES (id, address, is_erc20, is_erc721, total_eth, transfer_count)
  )
  EDGE TABLES (
    `${PROJECT}.${DATASET}.edges_sent`
      KEY (src_id, dst_id)
      SOURCE KEY (src_id) REFERENCES `${PROJECT}.${DATASET}.nodes_address` (id)
      DESTINATION KEY (dst_id) REFERENCES `${PROJECT}.${DATASET}.nodes_address` (id)
      LABEL SENT
      PROPERTIES (transfer_count, total_eth, first_seen, last_seen),

    `${PROJECT}.${DATASET}.edges_called`
      KEY (src_id, dst_id)
      SOURCE KEY (src_id) REFERENCES `${PROJECT}.${DATASET}.nodes_address` (id)
      DESTINATION KEY (dst_id) REFERENCES `${PROJECT}.${DATASET}.nodes_contract` (id)
      LABEL CALLED
      PROPERTIES (call_count, total_eth, last_seen)
  );
