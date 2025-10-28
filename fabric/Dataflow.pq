// Purpose: Load enriched payment summaries from Fabric Warehouse into Power BI
// Layer: Visualization (Dataflow Gen2)

let
    // ------------------------------
    // Connection Settings
    // ------------------------------
    Server   = "your-fabric-sql-endpoint.windows.net",
    Database = "YourWarehouseName",
    Source   = Sql.Database(Server, Database, [CreateNavigationProperties=false]),

    // ------------------------------
    // Table Selection
    // ------------------------------
    PaymentsDaily = Source{[Schema="warehouse", Item="summary_payments_daily"]}[Data],

    // ------------------------------
    // Data Type Enforcement
    // ------------------------------
    Typed = Table.TransformColumnTypes(
        PaymentsDaily,
        {
            {"merchant_id", type text},
            {"merchant_name", type text},
            {"division_name", type text},
            {"industry_category", type text},
            {"activity_date", type date},
            {"transaction_count", Int64.Type},
            {"gross_amount_total", type number},
            {"settlement_total", type number},
            {"interchange_total", type number},
            {"processor_fee_total", type number},
            {"network_fee_total", type number},
            {"merchant_fee_total", type number},
            {"settlement_rate", type number},
            {"interchange_rate", type number},
            {"transaction_margin", type number},
            {"created_at", type datetime}
        }
    ),

    // ------------------------------
    // Optional Incremental Refresh Parameters
    // ------------------------------
    RangeStart = try RangeStart otherwise #datetime(2024, 1, 1, 0, 0, 0),
    RangeEnd   = try RangeEnd   otherwise DateTime.LocalNow(),
    Filtered   = Table.SelectRows(
        Typed,
        each Date.From([activity_date]) >= Date.From(RangeStart)
          and Date.From([activity_date]) <  Date.From(RangeEnd)
    ),

    // ------------------------------
    // Enrich and Add Metadata
    // ------------------------------
    WithYearMonth = Table.AddColumn(
        Filtered,
        "year_month",
        each Date.ToText([activity_date], "yyyy-MM"),
        type text
    ),

    WithDisplayName = Table.AddColumn(
        WithYearMonth,
        "merchant_display",
        each Text.Combine({[merchant_name], " (", [merchant_id], ")"}, ""),
        type text
    )

in
    WithDisplayName
