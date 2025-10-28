# Purpose: Land raw JSON from Lakehouse Files into bronze Delta tables.
# Notes:
# - No secrets or account names are referenced.
# - Assumes you drop JSON files under Lakehouse: Files/landing/{initial|daily|corrections}/<area>/*.json
# - Adjust AREAS to match your sources (e.g., "transaction", "merchant_fee", "entity").

from pyspark.sql import functions as F

AREAS = ["transaction", "merchant_fee", "entity"]  # adjust if needed
LANDING_ROOT = "Files/landing"  # generic Files path in your Lakehouse
BRONZE_DB = "bronze"            # logical schema name for bronze tables

spark.sql(f"CREATE SCHEMA IF NOT EXISTS {BRONZE_DB}")

def load_area(area: str):
    paths = [
        f"{LANDING_ROOT}/initial/{area}/*.json",
        f"{LANDING_ROOT}/daily/{area}/*.json",
        f"{LANDING_ROOT}/corrections/{area}/*.json",
    ]
    df = None
    for p in paths:
        # read permissively; some folders may be empty
        _df = spark.read.option("multiline", "true").json(p)
        if df is None:
            df = _df
        else:
            df = df.unionByName(_df, allowMissingColumns=True)

    if df is None:
        return

    # Add ingestion metadata
    df = (
        df.withColumn("_ingestion_ts", F.current_timestamp())
          .withColumn("_ingestion_date", F.to_date(F.current_timestamp()))
          .withColumn("_source_area", F.lit(area))
    )

    # Write to Delta (partition on ingestion_date for manageability)
    table_name = f"{BRONZE_DB}.{area}_raw"
    (
        df.write
          .format("delta")
          .mode("append")
          .partitionBy("_ingestion_date")
          .saveAsTable(table_name)
    )

for a in AREAS:
    load_area(a)
