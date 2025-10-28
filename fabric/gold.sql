-- Purpose: Build curated, BI-ready tables from silver.
-- Notes:
-- - Keep business logic minimal here; compute only stable, widely used measures.

CREATE SCHEMA IF NOT EXISTS gold;

-- Fact table (example)
CREATE OR REPLACE TABLE gold.fact_transactions
USING DELTA
AS
SELECT
  t.transaction_id,
  t.merchant_id,
  t.activity_date,
  t.settlement_amount,
  t.interchange_amount,
  CASE
    WHEN t.settlement_amount > 0 THEN t.interchange_amount / t.settlement_amount
    ELSE CAST(0 AS DECIMAL(18,6))
  END AS tcm -- transaction cost margin
FROM silver.transactions t;

-- Merchant dimension (lightweight example)
CREATE OR REPLACE TABLE gold.dim_merchant
USING DELTA
AS
SELECT DISTINCT
  merchant_id
FROM silver.transactions
WHERE merchant_id IS NOT NULL;

-- Optional: Daily summary for faster dashboards
CREATE OR REPLACE TABLE gold.payments_summary_daily
USING DELTA
AS
SELECT
  merchant_id,
  activity_date,
  SUM(settlement_amount)  AS settlement_total,
  SUM(interchange_amount) AS interchange_total,
  CASE
    WHEN SUM(settlement_amount) > 0
         THEN SUM(interchange_amount) / SUM(settlement_amount)
    ELSE CAST(0 AS DECIMAL(18,6))
  END AS tcm
FROM silver.transactions
GROUP BY merchant_id, activity_date;
