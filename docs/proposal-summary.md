# Data Pipeline Modernization Proposal

**Author:** John Rodriguez  
**Role:** Business Intelligence Engineer  

---

## Overview

The current reporting process for generating Power BI visuals from large datasets (transactions, fees, and entity metadata) involves querying a legacy SQL database, exporting CSVs, and manually uploading data to Power BI. Each daily refresh takes roughly one hour due to manual steps and full-table scans.

To modernize this workflow, data will be exported as JSON files to **Azure Blob Storage**, ingested into a **Microsoft Fabric Lakehouse**, transformed using **Spark**, and made available to **Power BI**. This new approach reduces refresh time to approximately 5–10 minutes, automates ingestion, and ensures long-term data retention and scalability. A Blob Storage lifecycle policy will optimize storage costs while Fabric handles computation and persistence.

---

## Objectives

- Reduce daily refresh times from ~1 hour to **under 10 minutes**
- Eliminate manual CSV export/import workflows
- Support **late-arriving data**, **corrections via overwrite**, and **steady data growth** (approx. 3–6% monthly)
- Preserve existing **business logic** for aggregations, joins, and case statements
- Ensure **historical data retention**
- Keep infrastructure costs minimal while scaling with data volume

---

## Proposed Solution

1. The source system exports transactional and fee data as **JSON files** to **Azure Blob Storage**.
2. **Microsoft Fabric Data Factory** ingests these JSON files into the Lakehouse as **Delta/Parquet tables** (e.g., `raw_transaction`, `raw_fee`, `raw_entity`), using **merge/upsert** on unique IDs for correction handling.
3. A **Spark transformation job** aggregates and joins the raw tables into a **summary table** (`payments_summary`) optimized for Power BI consumption.
4. A **daily incremental pipeline** loads new or corrected JSON files, maintaining data freshness.
5. **Power BI** connects to the summarized dataset for fast, reliable reporting.

---

## Implementation Steps

### 1. Set Up Azure Blob Storage
- Create a storage account and container (e.g., `data-pipeline-storage`).
- Define folders:
  - `/initial/` — full data exports
  - `/daily/` — incremental loads
  - `/corrections/` — late-arriving or fixed records
- Apply a **lifecycle policy** to archive older files for cost efficiency.

### 2. Initial Data Export
- Export full datasets as JSON into `/initial/`.
- Include primary keys (`id`) for merge operations.

### 3. Ingest and Transform Data in Fabric
- Use **Data Factory** to load data from Blob into Lakehouse tables.
- Apply **merge/upsert** logic to handle overwrites for transaction and fee data, and overwrite logic for small entity tables.
- Create a **Spark job** to transform and summarize data for analytics.
- Output: `payments_summary` in Parquet format, optimized for Power BI queries.

### 4. Schedule Daily Incremental Loads
- Configure Data Factory to load JSONs from `/daily/`.
- Merge incremental changes and apply corrections automatically.
- Validate record counts between Blob and Lakehouse to ensure sync integrity.

### 5. Monitoring and Validation
- Set alerts for missing uploads or failed ingestions.
- Track data volume and job duration metrics.
- Optimize Spark performance as data grows.

---

## Benefits

| Area | Legacy Process | New Pipeline |
|------|----------------|--------------|
| Refresh Time | ~60 minutes | **5–10 minutes** |
| Automation | Manual CSV upload | **Fully automated ingestion** |
| Scalability | Limited | **Supports growth and corrections** |
| Data Retention | Partial (archived) | **Full historical storage** |
| Cost | Moderate | **Optimized via lifecycle policies** |
| Flexibility | Manual query logic | **Spark SQL & Fabric transformations** |

---

## Risks and Mitigation

| Risk | Description | Mitigation |
|------|--------------|-------------|
| Data Growth | Volume may exceed estimates | Monitor monthly usage and scale compute resources |
| Source Reliability | Source system may skip uploads | Add pipeline monitoring and alerts |
| Schema Drift | JSON structure may change | Use schema evolution and validation in Data Factory |

---

## Next Steps

1. Set up Azure Blob Storage and access credentials  
2. Build and test the Data Factory pipeline with sample JSON files  
3. Deploy and validate the Spark transformation logic  
4. Connect the Power BI Dataflow or dataset to Fabric’s output table  
5. Monitor daily syncs and refine lifecycle policy after the first month

---

## Recommendation

Adopting this **Azure + Fabric data pipeline** streamlines reporting, minimizes manual work, and ensures durable, scalable, and cost-effective analytics infrastructure. Daily ingestion pipelines with merge/upsert logic maintain clean, accurate datasets while enabling near real-time Power BI reporting.

---

