// ============================================================================
// SAMPLE POWER QUERY (M) — SANITIZED & PARAMETERIZED
// Four independent queries. Paste each into Power Query’s Advanced Editor as needed.
// Replace parameter defaults or bind them to Dataflow/PBIX Parameters.
// ============================================================================


/*-----------------------------------------------------------------------------
SECTION 1 — PAYMENTS / PROFITABILITY (EXCEL FROM SHAREPOINT)
    - Loads a worksheet from SharePoint (parameterized URL/path)
    - Neutral column names and constants
    - Optional join to a generic DimCustomer table
-----------------------------------------------------------------------------*/

// Parameters (define these as PBIX/Dataflow parameters where possible)
SiteUrl   = try SiteUrl   otherwise "https://your-tenant.sharepoint.com/sites/analytics",
FilePath  = try FilePath  otherwise "Shared Documents/Data/PayFac/Profitability_Summary.xlsx",
SheetName = try SheetName otherwise "Updated Variance by MID",

let
    Source = Excel.Workbook(
        Web.Contents(SiteUrl, [RelativePath = FilePath]),
        null,
        true
    ),
    RawSheet  = Source{[Item = SheetName, Kind = "Sheet"]}[Data],
    Promoted  = Table.PromoteHeaders(RawSheet, [PromoteAllScalars = true]),

    // Neutral constants
    AddDivision     = Table.AddColumn(Promoted, "Division", each "Division A"),
    RenameMonth     = Table.RenameColumns(AddDivision, {{"Month", "Date"}}),
    AddBusinessUnit = Table.AddColumn(RenameMonth, "Business Unit", each "Business Unit A"),

    ReorderCols = Table.ReorderColumns(
        AddBusinessUnit,
        {"Division","Business Unit","Account ID","Account Name","BusinessKey","Payment Type",
         "Gross Txn Volume","Txn Count","Gross Commission","Interchange","Other Fees","Net Commission","Date"}
    ),

    // Neutralized names
    RenamedCols = Table.RenameColumns(ReorderCols, {
        {"Account Name","Business"},
        {"Txn Count","Net Txn Count"},
        {"ODIN_ID","BusinessKey"}
    }),

    TypedDate     = Table.TransformColumnTypes(RenamedCols, {{"Date", type date}}),
    AddBusinessGp = Table.AddColumn(TypedDate, "Business Group", each [Business]),
    AddPayMethod  = Table.AddColumn(AddBusinessGp, "Payment Method", each "DEBIT"),
    AddTxnType    = Table.AddColumn(AddPayMethod, "Transaction Type", each "SALE"),
    AddTxnCount   = Table.AddColumn(AddTxnType, "Txn Count", each [Net Txn Count]),
    AddCurrency   = Table.AddColumn(AddTxnCount, "Currency", each "USD"),

    ReplaceNulls  = Table.ReplaceValue(
        AddCurrency, null, 0, Replacer.ReplaceValue,
        {"Payment Method","Gross Txn Volume","Txn Count","Net Txn Count","Gross Commission","Interchange","Other Fees","Net Commission"}
    ),

    // Join to a neutral DimCustomer table (rename or remove if not needed)
    // Expect an in-model query/table named DimCustomer with key [BusinessKey]
    Merged   = Table.NestedJoin(ReplaceNulls, {"BusinessKey"}, DimCustomer, {"BusinessKey"}, "DimCustomer", JoinKind.LeftOuter),
    Expanded = Table.ExpandTableColumn(Merged, "DimCustomer", {"ParentName"}, {"ParentName"}),

    // Generic product id, no brand code
    AddProductId = Table.AddColumn(Expanded, "ProductID", each [Business Unit] & "-" & "ProductA", type text),

    // Drop columns you don’t want to ship
    Removed = Table.RemoveColumns(AddProductId, {"Division","Business Unit","Account ID"}),

    FinalTypes = Table.TransformColumnTypes(
        Removed,
        {
            {"Business", type text},
            {"BusinessKey", type text},
            {"Payment Type", type text},
            {"Gross Txn Volume", type number},
            {"Net Txn Count", type number},
            {"Gross Commission", type number},
            {"Interchange", type number},
            {"Other Fees", type number},
            {"Net Commission", type number},
            {"Business Group", type text},
            {"Payment Method", type text},
            {"Transaction Type", type text},
            {"Txn Count", Int64.Type},
            {"Currency", type text},
            {"ParentName", type text},
            {"ProductID", type text},
            {"Date", type date}
        }
    )
in
    FinalTypes



/*-----------------------------------------------------------------------------
SECTION 2 — DATE DIMENSION (GENERATED CALENDAR)
    - Pure M calendar (no external files)
    - Adds Year, Quarter, Month Short, Month_Year, EndOfMonth
-----------------------------------------------------------------------------*/

// Parameters for calendar bounds
StartDate = try StartDate otherwise #date(2021, 1, 1),
EndDate   = try EndDate   otherwise #date(2026, 12, 31),

let
    DayCount     = Duration.Days(EndDate - StartDate) + 1,
    Dates        = List.Dates(StartDate, DayCount, #duration(1,0,0,0)),
    ToTable      = Table.FromList(Dates, Splitter.SplitByNothing(), {"Date"}, null, ExtraValues.Error),

    AddYear      = Table.AddColumn(ToTable, "Year", each Date.Year([Date]), Int64.Type),
    AddMonth     = Table.AddColumn(AddYear, "Month", each Date.Month([Date]), Int64.Type),
    AddMonthName = Table.AddColumn(AddMonth, "Month Name", each Date.ToText([Date], "MMMM"), type text),
    AddMonthShort= Table.AddColumn(AddMonthName, "Month (Short)", each Date.ToText([Date], "MMM"), type text),
    AddQuarter   = Table.AddColumn(AddMonthShort, "Quarter", each "Q" & Number.ToText(Date.QuarterOfYear([Date])), type text),
    AddYearQtr   = Table.AddColumn(AddQuarter, "Year & Quarter", each Text.From([Year]) & " " & [Quarter], type text),
    AddMonthYear = Table.AddColumn(AddYearQtr, "Month_Year", each [#"Month (Short)"] & Text.End(Text.From([Year]), 2), type text),
    AddEOM       = Table.AddColumn(AddMonthYear, "EndOfMonth", each Date.EndOfMonth([Date]), type date)
in
    AddEOM



/*-----------------------------------------------------------------------------
SECTION 3 — FX RATES (EXCEL FROM SHAREPOINT, DYNAMIC UNPIVOT)
    - Parameterized SharePoint path
    - Dynamically unpivots date-like columns to Month / RateToUSD
-----------------------------------------------------------------------------*/

// Parameters
FX_SiteUrl  = try FX_SiteUrl  otherwise "https://your-tenant.sharepoint.com/sites/analytics",
FX_FilePath = try FX_FilePath otherwise "Shared Documents/Data/Reference/FX_Rates.xlsx",
FX_Sheet    = try FX_Sheet    otherwise "FXTable",

let
    Source = Excel.Workbook(
        Web.Contents(FX_SiteUrl, [RelativePath = FX_FilePath]),
        null,
        true
    ),
    Raw       = Source{[Item = FX_Sheet, Kind = "Sheet"]}[Data],
    Promoted  = Table.PromoteHeaders(Raw, [PromoteAllScalars=true]),

    // Coerce types defensively first
    TypeCoerce = Table.TransformColumnTypes(Promoted, {}, "en-US"),

    // Identify columns whose names parse as dates (these will be unpivoted)
    ColumnsToUnpivot =
        List.Select(
            Table.ColumnNames(TypeCoerce),
            (c) => Value.Is(try Date.FromText(c) otherwise null, type date)
        ),

    Unpivoted =
        if List.Count(ColumnsToUnpivot) > 0 then
            Table.Unpivot(TypeCoerce, ColumnsToUnpivot, "Month", "RateToUSD")
        else
            TypeCoerce,

    MonthTyped = Table.TransformColumnTypes(Unpivoted, {{"Month", type date}}, "en-US"),

    // Normalize Currency/Rate column names
    Normalize =
        let
            WithCurrency =
                if List.Contains(Table.ColumnNames(MonthTyped), "Curr") then
                    Table.RenameColumns(MonthTyped, {{"Curr","Currency"}})
                else if List.Contains(Table.ColumnNames(MonthTyped), "Currency") then
                    MonthTyped
                else
                    Table.AddColumn(MonthTyped, "Currency", each "USD"),
            WithRate =
                if List.Contains(Table.ColumnNames(WithCurrency), "CCRate(USD)") then
                    Table.RenameColumns(WithCurrency, {{"CCRate(USD)","RateToUSD"}})
                else if not List.Contains(Table.ColumnNames(WithCurrency), "RateToUSD") then
                    Table.AddColumn(WithCurrency, "RateToUSD", each null)
                else
                    WithCurrency
        in
            WithRate,

    FilterRecent = Table.SelectRows(Normalize, each [Month] >= #date(2021, 12, 31)),
    FinalTypes   = Table.TransformColumnTypes(
        FilterRecent,
        {{"RateToUSD", type number}, {"Currency", type text}, {"Month", type date}}
    )
in
    FinalTypes



/*-----------------------------------------------------------------------------
SECTION 4 — SUBSCRIPTIONS (EXCEL FROM SHAREPOINT, DYNAMIC UNPIVOT)
    - Parameterized SharePoint path
    - Unpivots month columns to Date/MRR_Normalized_Local
    - Neutral metadata fields
-----------------------------------------------------------------------------*/

// Parameters
Subs_SiteUrl  = try Subs_SiteUrl  otherwise "https://your-tenant.sharepoint.com/sites/analytics",
Subs_FilePath = try Subs_FilePath otherwise "Shared Documents/Data/Subscriptions/Subscriptions_Accrual.xlsx",
Subs_Sheet    = try Subs_Sheet    otherwise "Summary Subscriptions",

let
    Source = Excel.Workbook(
        Web.Contents(Subs_SiteUrl, [RelativePath = Subs_FilePath]),
        null,
        true
    ),
    RawSheet = Source{[Item = Subs_Sheet, Kind = "Sheet"]}[Data],
    Promoted = Table.PromoteHeaders(RawSheet, [PromoteAllScalars=true]),

    // Basic typing; add/modify as your sheet requires
    Typed = Table.TransformColumnTypes(
        Promoted,
        {{"Account", type text}, {"ERP_ID", type text}, {"Product", type text}}
    ),

    // Remove totals/blank rows
    Filtered = Table.SelectRows(Typed, each [Account] <> null and [Account] <> "Total" and [Product] <> null),

    // Use ERP_ID if present; else fallback to Account
    AddCustomerKey = Table.AddColumn(Filtered, "CustomerKey", each if [ERP_ID] = null then [Account] else [ERP_ID], type text),
    RemoveERP      = Table.RemoveColumns(AddCustomerKey, {"ERP_ID"}),

    // Dynamically detect month columns (header text that parses to date)
    DateCols =
        List.Select(
            Table.ColumnNames(RemoveERP),
            (c) => (try Date.FromText(c) otherwise null) <> null
        ),

    Unpivoted    = Table.Unpivot(RemoveERP, DateCols, "Date", "Amount"),
    ReplaceNulls = Table.ReplaceValue(Unpivoted, null, 0, Replacer.ReplaceValue, {"Amount"}),
    Typed2       = Table.TransformColumnTypes(ReplaceNulls, {{"Date", type date}, {"Amount", type number}, {"CustomerKey", type text}, {"Product", type text}, {"Account", type text}}),

    // Normalize to EOM and neutral names
    WithEOM   = Table.TransformColumns(Typed2, {{"Date", Date.EndOfMonth, type date}}),
    Renamed   = Table.RenameColumns(WithEOM, {{"Account","CustomerName"}, {"Amount","MRR_Normalized_Local"}}),

    // Neutral metadata fields
    AddBrand   = Table.AddColumn(Renamed, "Brand", each "Brand A", type text),
    AddCur     = Table.AddColumn(AddBrand, "Currency", each "USD", type text),
    AddRevType = Table.AddColumn(AddCur, "RevenueType", each "Subscription", type text),
    AddSource  = Table.AddColumn(AddRevType, "Source", each "Excel", type text),
    AddProdId  = Table.AddColumn(AddSource, "ProductID", each "ProductA-" & [Product], type text),
    AddUnique  = Table.AddColumn(AddProdId, "UniqueID", each [CustomerKey], type text),

    FinalTypes = Table.TransformColumnTypes(
        AddUnique,
        {
            {"Brand", type text},
            {"Currency", type text},
            {"RevenueType", type text},
            {"Source", type text},
            {"ProductID", type text},
            {"UniqueID", type text},
            {"CustomerName", type text},
            {"Product", type text}
        }
    )
in
    FinalTypes
