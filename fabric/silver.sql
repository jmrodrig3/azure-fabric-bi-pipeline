-- Purpose: Enforce schema, deduplicate, and upsert bronze -> silver.
-- Notes:
-- - Adjust field names to your JSON structure if they differ.
-- - Uses transaction_id as the primary key example; replicate patterns for fee/entity.

CREATE SCHEMA IF NOT EXISTS silver;

-- Transactions (example)
CREATE TABLE IF NOT EXISTS silver.transactions (
  transaction_id       STRING NOT NULL,
  merchant_id          STRING,
  activity_date        DATE,
  settlement_amount    DECIMAL(18,2),
  interchange_amount   DECIMAL(18,2),
  _ingestion_ts        TIMESTAMP,
  CONSTRAINT PK_silver_transactions PRIMARY KEY (transaction_id)
);

-- Stage view to normalize from bronze
CREATE OR REPLACE TEMP VIEW v_bronze_transactions AS
SELECT
  CAST(b.value:id             AS STRING)         AS transaction_id,
  CAST(b.value:merchant_id    AS STRING)         AS merchant_id,
  TRY_TO_DATE(CAST(b.value:activity_date AS STRING)) AS activity_date,
  TRY_CAST(b.value:settlement_amount AS DECIMAL(18,2)) AS settlement_amount,
  TRY_CAST(b.value:interchange_amount AS DECIMAL(18,2)) AS interchange_amount,
  _ingestion_ts
FROM bronze.transaction_raw
LATERAL VIEW POSEXPLODE(CASE WHEN typeof(*) = 'array' THEN * ELSE array(*) END) t AS pos, value AS b;
-- If your JSON is already object-per-row in bronze, replace the above with a direct SELECT of columns.

-- Deduplicate latest records by transaction_id using _ingestion_ts
WITH ranked AS (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY _ingestion_ts DESC) AS rn
  FROM v_bronze_transactions
)
MERGE INTO silver.transactions AS tgt
USING (SELECT * FROM ranked WHERE rn = 1 AND transaction_id IS NOT NULL) AS src
ON tgt.transaction_id = src.transaction_id
WHEN MATCHED THEN UPDATE SET
  tgt.merchant_id        = src.merchant_id,
  tgt.activity_date      = src.activity_date,
  tgt.settlement_amount  = src.settlement_amount,
  tgt.interchange_amount = src.interchange_amount,
  tgt._ingestion_ts      = src._ingestion_ts
WHEN NOT MATCHED THEN INSERT (
  transaction_id, merchant_id, activity_date, settlement_amount, interchange_amount, _ingestion_ts
) VALUES (
  src.transaction_id, src.merchant_id, src.activity_date, src.settlement_amount, src.interchange_amount, src._ingestion_ts
);

-- Repeat similar patterns for fees/entities if needed:
-- CREATE TABLE IF NOT EXISTS silver.merchant_fee (...);
-- MERGE INTO silver.merchant_fee AS tgt USING (...) AS src ON tgt.fee_id = src.fee_id WHEN MATCHED ...;
-- CREATE TABLE IF NOT EXISTS silver.entity (...);
-- MERGE INTO silver.entity AS tgt USING (...) AS src ON tgt.entity_id = src.entity_id WHEN MATCHED ...;
