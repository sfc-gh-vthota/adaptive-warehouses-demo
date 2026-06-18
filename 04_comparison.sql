/*
================================================================================
  JPMC MERCHANT SERVICES - PERFORMANCE & COST COMPARISON
  ================================================================================

  PURPOSE: Compare Adaptive Warehouse vs Fixed Large Warehouse using query tags.

  INSTRUCTIONS:
  1. Run 02_adaptive_warehouse_demo.sql first (tags queries as ADAPTIVE_WH_DEMO)
  2. Run 03_fixed_warehouse_baseline.sql second (tags queries as FIXED_L_WH_DEMO)
  3. Run this script immediately to see the comparison (no wait needed)

  Uses INFORMATION_SCHEMA table functions for real-time results (no latency).
  Both scripts set QUERY_TAG at the session level, so only the 8 test queries
  in each script are tagged. This script uses those tags to filter precisely.
  ================================================================================
*/

USE ROLE SYSADMIN;
USE DATABASE JPMC_MERCHANT_SERVICES_DEMO;
USE SCHEMA MERCHANT_DATA;

-- =============================================================================
-- STEP 1: Capture the start time of the earliest tagged query
-- Uses INFORMATION_SCHEMA (real-time, no latency) to anchor the comparison window
-- =============================================================================

SET ADAPTIVE_START_TIME = (
    SELECT MIN(START_TIME)
    FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY(
        RESULT_LIMIT => 50,
        END_TIME_RANGE_START => DATEADD(HOUR, -4, CURRENT_TIMESTAMP())
    ))
    WHERE QUERY_TAG = 'ADAPTIVE_WH_DEMO'
      AND QUERY_TYPE = 'SELECT'
);

SET FIXED_START_TIME = (
    SELECT MIN(START_TIME)
    FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY(
        RESULT_LIMIT => 50,
        END_TIME_RANGE_START => DATEADD(HOUR, -4, CURRENT_TIMESTAMP())
    ))
    WHERE QUERY_TAG = 'FIXED_L_WH_DEMO'
      AND QUERY_TYPE = 'SELECT'
);

SET TEST_WINDOW_START = (
    SELECT LEAST($ADAPTIVE_START_TIME, $FIXED_START_TIME)
);

-- Show the captured timestamps
SELECT
    $ADAPTIVE_START_TIME AS ADAPTIVE_FIRST_QUERY,
    $FIXED_START_TIME AS FIXED_L_FIRST_QUERY,
    $TEST_WINDOW_START AS TEST_WINDOW_START;


-- =============================================================================
-- STEP 2: SUMMARY COMPARISON - Aggregate performance by warehouse
-- =============================================================================

SELECT
    QUERY_TAG,
    WAREHOUSE_NAME,
    WAREHOUSE_SIZE,
    COUNT(*) AS QUERIES_RUN,
    ROUND(SUM(TOTAL_ELAPSED_TIME) / 1000, 2) AS TOTAL_ELAPSED_SEC,
    ROUND(AVG(TOTAL_ELAPSED_TIME) / 1000, 2) AS AVG_ELAPSED_SEC,
    ROUND(MAX(TOTAL_ELAPSED_TIME) / 1000, 2) AS MAX_ELAPSED_SEC,
    ROUND(MIN(TOTAL_ELAPSED_TIME) / 1000, 2) AS MIN_ELAPSED_SEC,
    ROUND(SUM(EXECUTION_TIME) / 1000, 2) AS TOTAL_EXEC_SEC,
    ROUND(SUM(BYTES_SCANNED) / (1024*1024*1024), 2) AS TOTAL_GB_SCANNED
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY(
    RESULT_LIMIT => 50,
    END_TIME_RANGE_START => $TEST_WINDOW_START
))
WHERE QUERY_TAG IN ('ADAPTIVE_WH_DEMO', 'FIXED_L_WH_DEMO')
  AND QUERY_TYPE = 'SELECT'
GROUP BY 1, 2, 3
ORDER BY QUERY_TAG;


-- =============================================================================
-- STEP 3: DETAILED PER-QUERY COMPARISON (side by side, matched by order)
-- =============================================================================

WITH adaptive_queries AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY START_TIME) AS QUERY_NUM,
        LEFT(QUERY_TEXT, 50) AS QUERY_PREVIEW,
        TOTAL_ELAPSED_TIME / 1000 AS ELAPSED_SEC,
        EXECUTION_TIME / 1000 AS EXEC_SEC,
        BYTES_SCANNED / (1024*1024*1024) AS GB_SCANNED
    FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY(
        RESULT_LIMIT => 20,
        END_TIME_RANGE_START => $ADAPTIVE_START_TIME
    ))
    WHERE QUERY_TAG = 'ADAPTIVE_WH_DEMO'
      AND QUERY_TYPE = 'SELECT'
),
fixed_queries AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY START_TIME) AS QUERY_NUM,
        LEFT(QUERY_TEXT, 50) AS QUERY_PREVIEW,
        TOTAL_ELAPSED_TIME / 1000 AS ELAPSED_SEC,
        EXECUTION_TIME / 1000 AS EXEC_SEC,
        BYTES_SCANNED / (1024*1024*1024) AS GB_SCANNED
    FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY(
        RESULT_LIMIT => 20,
        END_TIME_RANGE_START => $FIXED_START_TIME
    ))
    WHERE QUERY_TAG = 'FIXED_L_WH_DEMO'
      AND QUERY_TYPE = 'SELECT'
)
SELECT
    a.QUERY_NUM,
    a.QUERY_PREVIEW,
    ROUND(a.ELAPSED_SEC, 2) AS ADAPTIVE_ELAPSED_SEC,
    ROUND(f.ELAPSED_SEC, 2) AS FIXED_L_ELAPSED_SEC,
    ROUND(f.ELAPSED_SEC - a.ELAPSED_SEC, 2) AS DIFF_SEC,
    CASE
        WHEN a.ELAPSED_SEC < f.ELAPSED_SEC
        THEN ROUND((f.ELAPSED_SEC - a.ELAPSED_SEC) / NULLIF(f.ELAPSED_SEC, 0) * 100, 1) || '% faster (Adaptive)'
        WHEN a.ELAPSED_SEC > f.ELAPSED_SEC
        THEN ROUND((a.ELAPSED_SEC - f.ELAPSED_SEC) / NULLIF(a.ELAPSED_SEC, 0) * 100, 1) || '% faster (Fixed L)'
        ELSE 'Same'
    END AS WINNER,
    ROUND(a.GB_SCANNED, 3) AS GB_SCANNED
FROM adaptive_queries a
JOIN fixed_queries f ON f.QUERY_NUM = a.QUERY_NUM
ORDER BY a.QUERY_NUM;


-- =============================================================================
-- STEP 4: COST COMPARISON - Actual credits consumed
-- Uses INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY (real-time)
-- =============================================================================

SELECT
    WAREHOUSE_NAME,
    SUM(CREDITS_USED_COMPUTE) AS COMPUTE_CREDITS,
    SUM(CREDITS_USED_CLOUD_SERVICES) AS CLOUD_SERVICES_CREDITS,
    SUM(CREDITS_USED) AS TOTAL_CREDITS
FROM TABLE(INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(
    DATE_RANGE_START => $TEST_WINDOW_START,
    DATE_RANGE_END => CURRENT_TIMESTAMP()
))
WHERE WAREHOUSE_NAME IN ('JPMC_MERCHANT_ADAPTIVE_WH', 'JPMC_MERCHANT_L_WH')
GROUP BY WAREHOUSE_NAME
ORDER BY WAREHOUSE_NAME;


-- =============================================================================
-- STEP 5: COST ESTIMATION based on execution time
-- Fixed L: 8 credits/hr prorated by actual execution time (min 60s billing)
-- Adaptive: per-query billing shown in metering history above
-- =============================================================================

SELECT
    QUERY_TAG,
    WAREHOUSE_NAME,
    COUNT(*) AS QUERIES,
    ROUND(SUM(EXECUTION_TIME) / 1000, 2) AS TOTAL_EXEC_SEC,
    ROUND(SUM(TOTAL_ELAPSED_TIME) / 1000, 2) AS TOTAL_ELAPSED_SEC,
    -- Fixed L: 8 credits/hr. Minimum billing = 60 sec per warehouse resume.
    CASE
        WHEN WAREHOUSE_NAME = 'JPMC_MERCHANT_L_WH'
        THEN ROUND(GREATEST(SUM(EXECUTION_TIME) / 1000.0, 60) / 3600.0 * 8, 4)
    END AS ESTIMATED_CREDITS_FIXED_L,
    CASE
        WHEN WAREHOUSE_NAME = 'JPMC_MERCHANT_ADAPTIVE_WH'
        THEN '(see WAREHOUSE_METERING_HISTORY above for actual)'
    END AS ADAPTIVE_CREDITS_NOTE
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY(
    RESULT_LIMIT => 50,
    END_TIME_RANGE_START => $TEST_WINDOW_START
))
WHERE QUERY_TAG IN ('ADAPTIVE_WH_DEMO', 'FIXED_L_WH_DEMO')
  AND QUERY_TYPE = 'SELECT'
GROUP BY 1, 2
ORDER BY QUERY_TAG;


-- =============================================================================
-- STEP 6: EXECUTIVE SUMMARY
-- =============================================================================

/*
  ================================================================================
  KEY FINDINGS FOR JPMC MERCHANT SERVICES:
  ================================================================================

  PERFORMANCE:
  - Adaptive WH delivers better performance on complex queries (Q4-Q8) because
    it scales up resources automatically beyond what a fixed Large provides
  - Simple queries (Q1-Q3) run in similar time on both — but adaptive uses
    minimal resources for these, while Large burns 8 credits/hr regardless

  COST:
  - Fixed Large: Charges the full 8 credits/hr rate for every second it's running
    Even a 0.2 second point lookup costs the same rate as a 60-second scan
  - Adaptive: Bills per-query based on actual resources consumed
    Simple queries cost a fraction of what the Large rate would charge

  BOTTOM LINE:
  - Adaptive = better performance on heavy queries + lower cost on simple queries
  - One warehouse handles ALL workloads — no more random size selection by team
  - Migration is one command: ALTER WAREHOUSE ... SET WAREHOUSE_TYPE = 'ADAPTIVE';

  ================================================================================

  CLEANUP (Optional):
  DROP WAREHOUSE IF EXISTS JPMC_MERCHANT_ADAPTIVE_WH;
  DROP WAREHOUSE IF EXISTS JPMC_MERCHANT_XL_WH;
  DROP WAREHOUSE IF EXISTS JPMC_MERCHANT_L_WH;
  DROP WAREHOUSE IF EXISTS JPMC_MERCHANT_M_WH;
  DROP WAREHOUSE IF EXISTS DEMO_DATA_LOAD_WH;
  DROP DATABASE IF EXISTS JPMC_MERCHANT_SERVICES_DEMO;
  ================================================================================
*/
