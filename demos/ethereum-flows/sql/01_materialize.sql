-- Materialize one day of Ethereum transfers into your own project.
--
-- Cost control, and the only thing that matters in this file: the transactions
-- table is partitioned by block_timestamp and is enormous. Every read below uses
-- an explicit half-open timestamp range so BigQuery prunes to a single day
-- partition. Do not replace it with DATE(block_timestamp) = '...' or a BETWEEN
-- across days.
--
-- Substituted by scripts/setup.sh:
--   ${PROJECT} ${DATASET} ${ETH_DATE} ${TOP_N} ${MIN_ETH}

-- Every non-dust transfer on the chosen day, in ETH rather than wei.
CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.day_transfers` AS
SELECT
  t.from_address,
  t.to_address,
  SAFE_DIVIDE(CAST(t.value AS BIGNUMERIC), 1e18) AS eth,
  t.block_timestamp
FROM `bigquery-public-data.crypto_ethereum.transactions` AS t
WHERE t.block_timestamp >= TIMESTAMP('${ETH_DATE} 00:00:00 UTC')
  AND t.block_timestamp <  TIMESTAMP_ADD(TIMESTAMP('${ETH_DATE} 00:00:00 UTC'), INTERVAL 1 DAY)
  AND t.receipt_status = 1              -- successful transactions only
  AND t.to_address IS NOT NULL          -- exclude contract *creations*
  AND SAFE_DIVIDE(CAST(t.value AS BIGNUMERIC), 1e18) >= ${MIN_ETH};

-- Which addresses to keep: the busiest by total value moved, either direction.
-- Bounding here is what keeps the graph readable and the later queries cheap.
CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.top_addresses` AS
WITH moved AS (
  SELECT from_address AS address, eth FROM `${PROJECT}.${DATASET}.day_transfers`
  UNION ALL
  SELECT to_address   AS address, eth FROM `${PROJECT}.${DATASET}.day_transfers`
)
SELECT address, SUM(eth) AS total_eth, COUNT(*) AS transfer_count
FROM moved
GROUP BY address
ORDER BY total_eth DESC
LIMIT ${TOP_N};

-- Which of those are contracts. crypto_ethereum.contracts is small relative to
-- transactions, but it is not partitioned, so we read it once and keep only the
-- addresses we care about.
CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.nodes_contract` AS
SELECT
  c.address     AS id,
  c.address     AS address,
  c.is_erc20    AS is_erc20,
  c.is_erc721   AS is_erc721,
  a.total_eth   AS total_eth,
  a.transfer_count AS transfer_count
FROM `bigquery-public-data.crypto_ethereum.contracts` AS c
JOIN `${PROJECT}.${DATASET}.top_addresses` AS a ON a.address = c.address;

-- Everything else is an externally owned account — a wallet, not code.
CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.nodes_address` AS
SELECT
  a.address        AS id,
  a.address        AS address,
  a.total_eth      AS total_eth,
  a.transfer_count AS transfer_count
FROM `${PROJECT}.${DATASET}.top_addresses` AS a
WHERE a.address NOT IN (SELECT id FROM `${PROJECT}.${DATASET}.nodes_contract`);

-- Wallet -> wallet value transfer, aggregated. One edge per pair rather than one
-- per transaction: a day holds over a million transactions, and the aggregate is
-- what you actually want to look at.
CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.edges_sent` AS
SELECT
  t.from_address       AS src_id,
  t.to_address         AS dst_id,
  COUNT(*)             AS transfer_count,
  SUM(t.eth)           AS total_eth,
  MIN(t.block_timestamp) AS first_seen,
  MAX(t.block_timestamp) AS last_seen
FROM `${PROJECT}.${DATASET}.day_transfers` AS t
WHERE t.from_address IN (SELECT id FROM `${PROJECT}.${DATASET}.nodes_address`)
  AND t.to_address   IN (SELECT id FROM `${PROJECT}.${DATASET}.nodes_address`)
GROUP BY src_id, dst_id;

-- Wallet -> contract. Same aggregation, but the destination is code, so this is
-- a call carrying value rather than a payment to a person.
CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.edges_called` AS
SELECT
  t.from_address       AS src_id,
  t.to_address         AS dst_id,
  COUNT(*)             AS call_count,
  SUM(t.eth)           AS total_eth,
  MAX(t.block_timestamp) AS last_seen
FROM `${PROJECT}.${DATASET}.day_transfers` AS t
WHERE t.from_address IN (SELECT id FROM `${PROJECT}.${DATASET}.nodes_address`)
  AND t.to_address   IN (SELECT id FROM `${PROJECT}.${DATASET}.nodes_contract`)
GROUP BY src_id, dst_id;
