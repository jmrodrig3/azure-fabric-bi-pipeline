// -----------------------------
// Fact & Dim naming (generic)
// 'FactSubscription'  : subscription events (MRR, churn, dates, customer)
// 'FactPayments'      : payment/commission facts (gross commissions, currency)
// 'DimCustomer'       : customer dimension (name, attributes)
// 'DimFXRate'         : FX rates with [Month], [Currency], [RateToUSD]
// -----------------------------
// Columns used (rename to match your model):
// FactSubscription[CustomerName], [Date], [MRR_Normalized_Local], [ChurnFlag]
// FactPayments[GrossCommission], [Currency], [Date]
// DimFXRate[Month], [Currency], [RateToUSD]
// -----------------------------


// Helper measure (current ARR from normalized local MRR)
Current ARR :=
SUM ( 'FactSubscription'[MRR_Normalized_Local] ) * 12


// 1) Cohort acquisition month per customer (first billable month > threshold)
Cohort Acquisition Month :=
VAR _Customer = SELECTEDVALUE ( 'FactSubscription'[CustomerName] )
RETURN
CALCULATE (
    MIN ( 'FactSubscription'[Date] ),
    'FactSubscription'[CustomerName] = _Customer,
    'FactSubscription'[MRR_Normalized_Local] > 0.5,      // threshold is illustrative
    ALL ( 'FactSubscription' )
)


// 2) Last ARR for churned customers (negative ARR applied on last billed period)
Last ARR :=
IF (
    MAX ( 'FactSubscription'[ChurnFlag] ) = 1,
    CALCULATE ( SUM ( 'FactSubscription'[MRR_Normalized_Local] ) ) * -12,
    0
)


// 3) Month of last revenue for the customer (end-of-month date)
Last Revenue Month :=
VAR _Customer = SELECTEDVALUE ( 'FactSubscription'[CustomerName] )
VAR _LastEOM =
    CALCULATE (
        EOMONTH ( MAX ( 'FactSubscription'[Date] ), 0 ),
        'FactSubscription'[CustomerName] = _Customer,
        'FactSubscription'[MRR_Normalized_Local] > 0
    )
RETURN
_LastEOM


// 4) Top-N value by Current ARR (uses a slicer/parameter table 'TopN'[TopNNum])
TopN Value :=
VAR _N = SELECTEDVALUE ( 'TopN'[TopNNum], 10 )
RETURN
CALCULATE (
    [Current ARR],
    TOPN (
        _N,
        ALLSELECTED ( 'FactSubscription'[CustomerName] ),
        [Current ARR], DESC
    )
)


// 5) Count of churned customers with prior positive MRR
Churned Customers :=
CALCULATE (
    DISTINCTCOUNT ( 'FactSubscription'[CustomerName] ),
    'FactSubscription'[MRR_Normalized_Local] > 0,
    'FactSubscription'[ChurnFlag] = 1
)


// 6) Commission MRR converted using FX rate (generic lookup, no vendor terms)
Commission MRR (Converted) :=
SUMX (
    'FactPayments',
    'FactPayments'[GrossCommission]
        * LOOKUPVALUE (
            'DimFXRate'[RateToUSD],
            'DimFXRate'[Month],     EOMONTH ( 'FactPayments'[Date], 0 ),
            'DimFXRate'[Currency],  'FactPayments'[Currency]
        )
)
