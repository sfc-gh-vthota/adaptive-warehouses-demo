/*
================================================================================
  JPMC MERCHANT SERVICES - ADAPTIVE WAREHOUSE DEMO
  ================================================================================
  
  CUSTOMER PROBLEM:
  The Merchant Services LOB team is randomly using XL, L, M warehouses
  regardless of workload complexity. Simple lookups run on XL warehouses,
  wasting credits. Complex analytics run on undersized warehouses, causing
  slow performance. This leads to significant compute cost overruns.

  SOLUTION: ADAPTIVE WAREHOUSES
  Adaptive Compute automatically right-sizes resources PER QUERY from a shared
  account-level pool. No manual sizing decisions needed. Each query gets exactly
  the compute it requires — simple queries use minimal resources, complex queries
  scale up automatically.

  DEMO STRUCTURE:
  - 8 queries of varying complexity (simple lookup → heavy analytics)
  - Shows how adaptive handles each workload type optimally
  - Compares the "before" (team randomly picking sizes) vs "after" (adaptive)

  DATA: 500M+ transactions, 500K merchants, 5M chargebacks, 50M settlements, 
        10M fraud alerts
  ================================================================================
*/

-- =============================================================================
-- SETUP
-- =============================================================================
USE ROLE SYSADMIN;
USE DATABASE JPMC_MERCHANT_SERVICES_DEMO;
USE SCHEMA MERCHANT_DATA;

-- Disable result cache so every query hits compute (important for fair comparison)
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

USE WAREHOUSE JPMC_MERCHANT_ADAPTIVE_WH;

-- Tag all queries from this point for filtering in query history
ALTER SESSION SET QUERY_TAG = 'ADAPTIVE_WH_DEMO';

-- =============================================================================
-- QUERY 1: SIMPLE POINT LOOKUP (Adaptive uses minimal resources)
-- Equivalent to XS warehouse — team was running this on XL!
-- =============================================================================
/*
  SCENARIO: Support agent looks up a specific merchant's status.
  BEFORE (team uses XL): Costs 16 credits/hr for a 0.2 second query
  AFTER (adaptive): System allocates minimal resources automatically
*/

SELECT MERCHANT_ID, MERCHANT_NAME, MERCHANT_CATEGORY, STATUS, ONBOARDING_DATE
FROM MERCHANTS 
WHERE MERCHANT_NUMBER = 'MID-0000012345';

-- =============================================================================
-- QUERY 2: SIMPLE AGGREGATION (Adaptive uses small resources)
-- Equivalent to S warehouse — team was running this on L!
-- =============================================================================
/*
  SCENARIO: Daily operations dashboard - transaction count by card network.
  BEFORE (team uses L): 8 credits/hr for a simple GROUP BY
  AFTER (adaptive): System right-sizes to small resources
*/

SELECT 
    CARD_NETWORK,
    COUNT(*) AS TOTAL_TRANSACTIONS,
    SUM(CASE WHEN AUTHORIZATION_STATUS = 'APPROVED' THEN 1 ELSE 0 END) AS APPROVED,
    SUM(CASE WHEN AUTHORIZATION_STATUS = 'DECLINED' THEN 1 ELSE 0 END) AS DECLINED,
    ROUND(SUM(CASE WHEN AUTHORIZATION_STATUS = 'DECLINED' THEN 1 ELSE 0 END)::FLOAT / COUNT(*) * 100, 2) AS DECLINE_RATE_PCT
FROM TRANSACTIONS
WHERE TRANSACTION_TIMESTAMP >= '2023-10-01' AND TRANSACTION_TIMESTAMP < '2024-01-01'
GROUP BY CARD_NETWORK
ORDER BY TOTAL_TRANSACTIONS DESC;

-- =============================================================================
-- QUERY 3: MEDIUM SCAN WITH FILTER (Adaptive uses moderate resources)
-- Equivalent to M warehouse — matches what adaptive would choose
-- =============================================================================
/*
  SCENARIO: Risk team reviews high-value transactions for suspicious patterns.
  BEFORE (team sometimes uses XL "just in case"): Wasteful over-provisioning
  AFTER (adaptive): Allocates exactly what this scan needs
*/

SELECT 
    DATE_TRUNC('DAY', TRANSACTION_TIMESTAMP) AS TXN_DATE,
    ENTRY_MODE,
    COUNT(*) AS HIGH_VALUE_COUNT,
    SUM(AMOUNT) AS TOTAL_AMOUNT,
    AVG(AMOUNT) AS AVG_AMOUNT,
    MAX(AMOUNT) AS MAX_AMOUNT
FROM TRANSACTIONS
WHERE AMOUNT > 5000
  AND TRANSACTION_TIMESTAMP >= '2023-07-01' AND TRANSACTION_TIMESTAMP < '2024-01-01'
GROUP BY 1, 2
ORDER BY TXN_DATE DESC, HIGH_VALUE_COUNT DESC
LIMIT 100;

-- =============================================================================
-- QUERY 4: MULTI-TABLE JOIN (Adaptive scales up resources)
-- Equivalent to L warehouse — team was running this on M (too slow!)
-- =============================================================================
/*
  SCENARIO: Merchant risk scoring - joining transactions with fraud alerts.
  BEFORE (team uses M): Takes 5+ minutes, times out during peak hours
  AFTER (adaptive): Scales up to handle the join efficiently
*/

SELECT 
    m.MERCHANT_NAME,
    m.MERCHANT_CATEGORY,
    m.MERCHANT_TIER,
    COUNT(DISTINCT t.TRANSACTION_ID) AS TOTAL_TRANSACTIONS,
    COUNT(DISTINCT f.ALERT_ID) AS FRAUD_ALERTS,
    ROUND(COUNT(DISTINCT f.ALERT_ID)::FLOAT / NULLIF(COUNT(DISTINCT t.TRANSACTION_ID), 0) * 10000, 2) AS ALERTS_PER_10K_TXN,
    SUM(t.AMOUNT) AS TOTAL_VOLUME,
    AVG(f.FRAUD_SCORE) AS AVG_FRAUD_SCORE
FROM MERCHANTS m
JOIN TRANSACTIONS t ON t.MERCHANT_ID = m.MERCHANT_ID
LEFT JOIN FRAUD_ALERTS f ON f.MERCHANT_ID = m.MERCHANT_ID
WHERE t.TRANSACTION_TIMESTAMP >= '2023-07-01'
  AND m.STATUS = 'Active'
GROUP BY 1, 2, 3
HAVING COUNT(DISTINCT f.ALERT_ID) > 5
ORDER BY ALERTS_PER_10K_TXN DESC
LIMIT 50;

-- =============================================================================
-- QUERY 5: COMPLEX WINDOW FUNCTIONS (Adaptive allocates significant resources)
-- Equivalent to L/XL warehouse — team used M and it took 10 minutes
-- =============================================================================
/*
  SCENARIO: Merchant chargeback trending with rolling averages.
  BEFORE (team uses M): Extremely slow with window functions over large data
  AFTER (adaptive): System recognizes complexity and scales up automatically
*/

SELECT 
    MERCHANT_ID,
    CHARGEBACK_MONTH,
    MONTHLY_CHARGEBACKS,
    MONTHLY_AMOUNT,
    AVG(MONTHLY_CHARGEBACKS) OVER (PARTITION BY MERCHANT_ID ORDER BY CHARGEBACK_MONTH ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS ROLLING_3M_AVG_COUNT,
    SUM(MONTHLY_AMOUNT) OVER (PARTITION BY MERCHANT_ID ORDER BY CHARGEBACK_MONTH ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS ROLLING_12M_AMOUNT,
    MONTHLY_CHARGEBACKS - LAG(MONTHLY_CHARGEBACKS) OVER (PARTITION BY MERCHANT_ID ORDER BY CHARGEBACK_MONTH) AS MOM_CHANGE
FROM (
    SELECT 
        MERCHANT_ID,
        DATE_TRUNC('MONTH', CHARGEBACK_DATE) AS CHARGEBACK_MONTH,
        COUNT(*) AS MONTHLY_CHARGEBACKS,
        SUM(CHARGEBACK_AMOUNT) AS MONTHLY_AMOUNT
    FROM CHARGEBACKS
    GROUP BY 1, 2
)
QUALIFY ROLLING_3M_AVG_COUNT > 1
ORDER BY ROLLING_12M_AMOUNT DESC
LIMIT 100;

-- =============================================================================
-- QUERY 6: HEAVY FULL-TABLE ANALYTICS (Adaptive uses large resources)
-- Equivalent to XL warehouse — appropriate scaling by adaptive
-- =============================================================================
/*
  SCENARIO: Monthly P&L analysis across all merchants and settlements.
  BEFORE (team uses random sizes): Unpredictable performance 
  AFTER (adaptive): Automatically allocates XL-equivalent resources for this scan
*/

SELECT 
    m.MERCHANT_CATEGORY,
    m.MERCHANT_TIER,
    m.STATE,
    DATE_TRUNC('MONTH', s.SETTLEMENT_DATE) AS SETTLEMENT_MONTH,
    COUNT(DISTINCT s.MERCHANT_ID) AS ACTIVE_MERCHANTS,
    SUM(s.GROSS_AMOUNT) AS TOTAL_GROSS,
    SUM(s.FEES_DEDUCTED) AS TOTAL_FEES,
    SUM(s.CHARGEBACKS_DEDUCTED) AS TOTAL_CHARGEBACKS,
    SUM(s.NET_SETTLEMENT_AMOUNT) AS TOTAL_NET,
    SUM(s.TRANSACTION_COUNT) AS TOTAL_TXN_COUNT,
    ROUND(SUM(s.FEES_DEDUCTED) / NULLIF(SUM(s.GROSS_AMOUNT), 0) * 100, 3) AS FEE_RATE_PCT,
    ROUND(SUM(s.CHARGEBACKS_DEDUCTED) / NULLIF(SUM(s.GROSS_AMOUNT), 0) * 100, 3) AS CHARGEBACK_RATE_PCT
FROM DAILY_SETTLEMENTS s
JOIN MERCHANTS m ON m.MERCHANT_ID = s.MERCHANT_ID
GROUP BY 1, 2, 3, 4
ORDER BY SETTLEMENT_MONTH DESC, TOTAL_GROSS DESC;

-- =============================================================================
-- QUERY 7: COMPLEX MULTI-JOIN WITH SUBQUERIES (Adaptive uses XL resources)
-- Equivalent to XL warehouse — team sometimes runs on M and waits 15 min
-- =============================================================================
/*
  SCENARIO: Comprehensive merchant risk dashboard combining transactions,
  chargebacks, fraud alerts, and settlements for executive reporting.
  BEFORE (team uses M or L): Inconsistent, sometimes crashes
  AFTER (adaptive): Scales to handle this complex analytical workload
*/

WITH merchant_txn_summary AS (
    SELECT 
        MERCHANT_ID,
        COUNT(*) AS TOTAL_TXNS,
        SUM(AMOUNT) AS TOTAL_VOLUME,
        SUM(CASE WHEN RISK_FLAG = 'FRAUD_SUSPECTED' THEN 1 ELSE 0 END) AS FRAUD_FLAGGED,
        SUM(CASE WHEN AUTHORIZATION_STATUS = 'DECLINED' THEN 1 ELSE 0 END) AS DECLINED_TXNS,
        COUNT(DISTINCT CARD_HOLDER_ID) AS UNIQUE_CARDHOLDERS
    FROM TRANSACTIONS
    WHERE TRANSACTION_TIMESTAMP >= '2023-01-01'
    GROUP BY MERCHANT_ID
),
merchant_chargeback_summary AS (
    SELECT 
        MERCHANT_ID,
        COUNT(*) AS TOTAL_CHARGEBACKS,
        SUM(CHARGEBACK_AMOUNT) AS TOTAL_CB_AMOUNT,
        AVG(DAYS_TO_RESOLVE) AS AVG_RESOLUTION_DAYS,
        SUM(CASE WHEN RESOLUTION_STATUS = 'CARDHOLDER_WON' THEN 1 ELSE 0 END) AS LOST_DISPUTES
    FROM CHARGEBACKS
    WHERE CHARGEBACK_DATE >= '2023-01-01'
    GROUP BY MERCHANT_ID
),
merchant_fraud_summary AS (
    SELECT 
        MERCHANT_ID,
        COUNT(*) AS TOTAL_ALERTS,
        AVG(FRAUD_SCORE) AS AVG_FRAUD_SCORE,
        SUM(CASE WHEN DISPOSITION = 'CONFIRMED_FRAUD' THEN 1 ELSE 0 END) AS CONFIRMED_FRAUD_COUNT
    FROM FRAUD_ALERTS
    WHERE ALERT_TIMESTAMP >= '2023-01-01'
    GROUP BY MERCHANT_ID
)
SELECT 
    m.MERCHANT_NAME,
    m.MERCHANT_CATEGORY,
    m.MERCHANT_TIER,
    m.CITY,
    m.STATE,
    t.TOTAL_TXNS,
    t.TOTAL_VOLUME,
    t.UNIQUE_CARDHOLDERS,
    ROUND(t.DECLINED_TXNS::FLOAT / NULLIF(t.TOTAL_TXNS, 0) * 100, 2) AS DECLINE_RATE,
    c.TOTAL_CHARGEBACKS,
    c.TOTAL_CB_AMOUNT,
    ROUND(c.TOTAL_CHARGEBACKS::FLOAT / NULLIF(t.TOTAL_TXNS, 0) * 10000, 2) AS CB_PER_10K_TXN,
    c.AVG_RESOLUTION_DAYS,
    f.TOTAL_ALERTS AS FRAUD_ALERTS,
    f.AVG_FRAUD_SCORE,
    f.CONFIRMED_FRAUD_COUNT,
    -- Risk Score: composite metric
    ROUND(
        (COALESCE(c.TOTAL_CHARGEBACKS, 0)::FLOAT / NULLIF(t.TOTAL_TXNS, 0) * 5000) +
        (COALESCE(f.CONFIRMED_FRAUD_COUNT, 0)::FLOAT / NULLIF(t.TOTAL_TXNS, 0) * 3000) +
        (t.DECLINED_TXNS::FLOAT / NULLIF(t.TOTAL_TXNS, 0) * 2000)
    , 2) AS COMPOSITE_RISK_SCORE
FROM MERCHANTS m
JOIN merchant_txn_summary t ON t.MERCHANT_ID = m.MERCHANT_ID
LEFT JOIN merchant_chargeback_summary c ON c.MERCHANT_ID = m.MERCHANT_ID
LEFT JOIN merchant_fraud_summary f ON f.MERCHANT_ID = m.MERCHANT_ID
WHERE m.STATUS = 'Active'
  AND t.TOTAL_TXNS > 100
ORDER BY COMPOSITE_RISK_SCORE DESC
LIMIT 100;

-- =============================================================================
-- QUERY 8: MASSIVE CROSS-TABLE AGGREGATION (Adaptive uses maximum resources)
-- Equivalent to XL+ — the heaviest workload, fully leveraging adaptive scaling
-- =============================================================================
/*
  SCENARIO: End-of-quarter regulatory compliance report requiring full scan
  of all tables with complex calculations across the entire dataset.
  BEFORE (team uses XL always "to be safe"): Wastes credits on simple queries
  AFTER (adaptive): Only uses maximum resources when truly needed (like now)
*/

WITH quarterly_metrics AS (
    SELECT 
        DATE_TRUNC('QUARTER', t.TRANSACTION_TIMESTAMP) AS QUARTER,
        m.MERCHANT_CATEGORY,
        m.STATE,
        m.MERCHANT_TIER,
        COUNT(*) AS TXN_COUNT,
        COUNT(DISTINCT t.MERCHANT_ID) AS ACTIVE_MERCHANTS,
        COUNT(DISTINCT t.CARD_HOLDER_ID) AS UNIQUE_CARDHOLDERS,
        SUM(t.AMOUNT) AS TOTAL_VOLUME,
        AVG(t.AMOUNT) AS AVG_TXN_SIZE,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY t.AMOUNT) AS P95_TXN_AMOUNT,
        SUM(CASE WHEN t.RISK_FLAG != 'CLEAN' THEN 1 ELSE 0 END) AS FLAGGED_TXNS,
        SUM(CASE WHEN t.AUTHORIZATION_STATUS = 'DECLINED' THEN 1 ELSE 0 END) AS DECLINED_TXNS,
        SUM(CASE WHEN t.ENTRY_MODE = 'ONLINE' THEN t.AMOUNT ELSE 0 END) AS ONLINE_VOLUME,
        SUM(CASE WHEN t.ENTRY_MODE IN ('CHIP', 'CONTACTLESS') THEN t.AMOUNT ELSE 0 END) AS IN_STORE_VOLUME
    FROM TRANSACTIONS t
    JOIN MERCHANTS m ON m.MERCHANT_ID = t.MERCHANT_ID
    GROUP BY 1, 2, 3, 4
),
quarterly_chargebacks AS (
    SELECT 
        DATE_TRUNC('QUARTER', c.CHARGEBACK_DATE) AS QUARTER,
        m.MERCHANT_CATEGORY,
        m.STATE,
        COUNT(*) AS CB_COUNT,
        SUM(c.CHARGEBACK_AMOUNT) AS CB_VOLUME,
        AVG(c.DAYS_TO_RESOLVE) AS AVG_RESOLUTION
    FROM CHARGEBACKS c
    JOIN MERCHANTS m ON m.MERCHANT_ID = c.MERCHANT_ID
    GROUP BY 1, 2, 3
)
SELECT 
    qm.QUARTER,
    qm.MERCHANT_CATEGORY,
    qm.STATE,
    qm.ACTIVE_MERCHANTS,
    qm.TXN_COUNT,
    qm.TOTAL_VOLUME,
    qm.AVG_TXN_SIZE,
    qm.P95_TXN_AMOUNT,
    qm.UNIQUE_CARDHOLDERS,
    ROUND(qm.FLAGGED_TXNS::FLOAT / qm.TXN_COUNT * 100, 3) AS FLAG_RATE_PCT,
    ROUND(qm.DECLINED_TXNS::FLOAT / qm.TXN_COUNT * 100, 3) AS DECLINE_RATE_PCT,
    ROUND(qm.ONLINE_VOLUME / NULLIF(qm.TOTAL_VOLUME, 0) * 100, 2) AS ONLINE_SHARE_PCT,
    qc.CB_COUNT AS CHARGEBACKS,
    qc.CB_VOLUME AS CHARGEBACK_VOLUME,
    ROUND(qc.CB_COUNT::FLOAT / qm.TXN_COUNT * 10000, 2) AS CB_PER_10K_TXN,
    ROUND(qc.CB_VOLUME / NULLIF(qm.TOTAL_VOLUME, 0) * 10000, 2) AS CB_BPS,
    qc.AVG_RESOLUTION AS AVG_CB_RESOLUTION_DAYS,
    -- QoQ growth
    LAG(qm.TOTAL_VOLUME) OVER (PARTITION BY qm.MERCHANT_CATEGORY, qm.STATE ORDER BY qm.QUARTER) AS PREV_QUARTER_VOLUME,
    ROUND((qm.TOTAL_VOLUME - LAG(qm.TOTAL_VOLUME) OVER (PARTITION BY qm.MERCHANT_CATEGORY, qm.STATE ORDER BY qm.QUARTER)) 
        / NULLIF(LAG(qm.TOTAL_VOLUME) OVER (PARTITION BY qm.MERCHANT_CATEGORY, qm.STATE ORDER BY qm.QUARTER), 0) * 100, 2) AS QOQ_VOLUME_GROWTH_PCT
FROM quarterly_metrics qm
LEFT JOIN quarterly_chargebacks qc 
    ON qc.QUARTER = qm.QUARTER 
    AND qc.MERCHANT_CATEGORY = qm.MERCHANT_CATEGORY
    AND qc.STATE = qm.STATE
ORDER BY qm.QUARTER DESC, qm.TOTAL_VOLUME DESC;

-- End of test queries. Run 04_comparison.sql to analyze results.
