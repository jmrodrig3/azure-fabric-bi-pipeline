-- Purpose: Materialize warehouse-level summary tables for reporting and analytics.
-- Layer: Warehouse (Computation)
-- Dependencies: gold.fact_transactions, gold.dim_merchant, gold.dim_fee_profile

CREATE SCHEMA IF NOT EXISTS warehouse;

-- ==========================
-- DAILY PAYMENT SUMMARY
-- ==========================
CREATE OR REPLACE TABLE warehouse.summary_payments_daily
USING DELTA
AS
SELECT
    t.merchant_id,
    m.merchant_name,
    t.activity_date,
    m.division_name,
    m.industry_category,
    COUNT(DISTINCT t.transaction_id) AS transaction_count,

    -- Financial aggregates
    SUM(t.gross_amount)            AS gross_amount_total,
    SUM(t.settlement_amount)       AS settlement_total,
    SUM(t.interchange_amount)      AS interchange_total,
    SUM(t.processor_fee)           AS processor_fee_total,
    SUM(t.network_fee)             AS network_fee_total,
    SUM(t.merchant_fee)            AS merchant_fee_total,

    -- Derived metrics
    CASE WHEN SUM(t.gross_amount) > 0
         THEN SUM(t.settlement_amount) / SUM(t.gross_amount)
         ELSE 0 END AS settlement_rate,

    CASE WHEN SUM(t.settlement_amount) > 0
         THEN SUM(t.interchange_amount) / SUM(t.settlement_amount)
         ELSE 0 END AS interchange_rate,

    CASE WHEN SUM(t.settlement_amount) > 0
         THEN (SUM(t.settlement_amount) - SUM(t.interchange_amount) - SUM(t.processor_fee)) / SUM(t.settlement_amount)
         ELSE 0 END AS transaction_margin,

    CURRENT_TIMESTAMP() AS created_at

FROM gold.fact_transactions AS t
LEFT JOIN gold.dim_merchant AS m
  ON t.merchant_id = m.merchant_id

GROUP BY
    t.merchant_id,
    m.merchant_name,
    m.division_name,
    m.industry_category,
    t.activity_date;

-- ==========================
-- MONTHLY PAYMENT SUMMARY
-- ==========================
CREATE OR REPLACE TABLE warehouse.summary_payments_monthly
USING DELTA
AS
SELECT
    merchant_id,
    merchant_name,
    DATE_TRUNC('month', activity_date) AS activity_month,
    division_name,
    industry_category,
    SUM(transaction_count)        AS transaction_count,
    SUM(gross_amount_total)       AS gross_amount_total,
    SUM(settlement_total)         AS settlement_total,
    SUM(interchange_total)        AS interchange_total,
    SUM(processor_fee_total)      AS processor_fee_total,
    SUM(network_fee_total)        AS network_fee_total,
    SUM(merchant_fee_total)       AS merchant_fee_total,

    CASE WHEN SUM(gross_amount_total) > 0
         THEN SUM(settlement_total) / SUM(gross_amount_total)
         ELSE 0 END AS settlement_rate,

    CASE WHEN SUM(settlement_total) > 0
         THEN SUM(interchange_total) / SUM(settlement_total)
         ELSE 0 END AS interchange_rate,

    CASE WHEN SUM(settlement_total) > 0
         THEN (SUM(settlement_total) - SUM(interchange_total) - SUM(processor_fee_total)) / SUM(settlement_total)
         ELSE 0 END AS transaction_margin,

    MAX(created_at) AS last_updated

FROM warehouse.summary_payments_daily
GROUP BY
    merchant_id,
    merchant_name,
    DATE_TRUNC('month', activity_date),
    division_name,
    industry_category;
