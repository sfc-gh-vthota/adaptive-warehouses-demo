/*
================================================================================
  JPMC MERCHANT SERVICES - DATA GENERATION SCRIPT
  ================================================================================

  PURPOSE: Creates the demo database, schema, warehouses, and populates tables
  with realistic Merchant Services data for the Adaptive Warehouse demo.

  PREREQUISITES:
  - SYSADMIN role (or equivalent) for database/schema/warehouse creation
  - ACCOUNTADMIN role for failover group modification (if needed)
  - Account in AWS us-west-2 region (for adaptive warehouse support)
  - Enterprise edition or above

  ESTIMATED RUN TIME: ~10-15 minutes (depends on warehouse size used)
  ESTIMATED STORAGE: ~15-20 GB compressed

  DATA VOLUMES:
  - TRANSACTIONS:      500,000,000 rows (main fact table)
  - DAILY_SETTLEMENTS:  50,000,000 rows
  - FRAUD_ALERTS:       10,000,000 rows
  - CHARGEBACKS:         5,000,000 rows
  - MERCHANTS:             500,000 rows (dimension)

  DATA DATE RANGE: 2021-01-01 to 2023-12-31
  ================================================================================
*/

-- =============================================================================
-- STEP 1: ENVIRONMENT SETUP
-- =============================================================================

USE ROLE SYSADMIN;

-- Create a temporary XL warehouse for fast data generation
CREATE WAREHOUSE IF NOT EXISTS DEMO_DATA_LOAD_WH
  WAREHOUSE_SIZE = 'XLARGE'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;

USE WAREHOUSE DEMO_DATA_LOAD_WH;

-- Create database and schema
CREATE DATABASE IF NOT EXISTS JPMC_MERCHANT_SERVICES_DEMO;
CREATE SCHEMA IF NOT EXISTS JPMC_MERCHANT_SERVICES_DEMO.MERCHANT_DATA;
USE SCHEMA JPMC_MERCHANT_SERVICES_DEMO.MERCHANT_DATA;

-- =============================================================================
-- STEP 2: CREATE MERCHANTS DIMENSION TABLE (500K rows)
-- =============================================================================

CREATE OR REPLACE TABLE MERCHANTS AS
SELECT
    ROW_NUMBER() OVER (ORDER BY SEQ4()) AS MERCHANT_ID,
    'MID-' || LPAD(ROW_NUMBER() OVER (ORDER BY SEQ4())::VARCHAR, 10, '0') AS MERCHANT_NUMBER,
    CASE MOD(SEQ4(), 20)
        WHEN 0 THEN 'Walmart' WHEN 1 THEN 'Target' WHEN 2 THEN 'Costco'
        WHEN 3 THEN 'Home Depot' WHEN 4 THEN 'Kroger' WHEN 5 THEN 'Amazon'
        WHEN 6 THEN 'Starbucks' WHEN 7 THEN 'McDonalds' WHEN 8 THEN 'CVS Pharmacy'
        WHEN 9 THEN 'Walgreens' WHEN 10 THEN 'Shell Gas' WHEN 11 THEN 'Chevron'
        WHEN 12 THEN 'Uber' WHEN 13 THEN 'DoorDash' WHEN 14 THEN 'Netflix'
        WHEN 15 THEN 'Spotify' WHEN 16 THEN 'Apple Store' WHEN 17 THEN 'Best Buy'
        WHEN 18 THEN 'Whole Foods' WHEN 19 THEN 'Trader Joes'
    END || ' #' || MOD(SEQ4(), 5000)::VARCHAR AS MERCHANT_NAME,
    CASE MOD(SEQ4(), 8)
        WHEN 0 THEN 'Retail' WHEN 1 THEN 'Grocery' WHEN 2 THEN 'Restaurant'
        WHEN 3 THEN 'Gas Station' WHEN 4 THEN 'E-Commerce' WHEN 5 THEN 'Healthcare'
        WHEN 6 THEN 'Travel' WHEN 7 THEN 'Entertainment'
    END AS MERCHANT_CATEGORY,
    CASE MOD(SEQ4(), 5)
        WHEN 0 THEN 'Small' WHEN 1 THEN 'Medium' WHEN 2 THEN 'Large'
        WHEN 3 THEN 'Enterprise' WHEN 4 THEN 'Micro'
    END AS MERCHANT_TIER,
    CASE MOD(SEQ4(), 10)
        WHEN 0 THEN 'New York' WHEN 1 THEN 'Los Angeles' WHEN 2 THEN 'Chicago'
        WHEN 3 THEN 'Houston' WHEN 4 THEN 'Phoenix' WHEN 5 THEN 'Philadelphia'
        WHEN 6 THEN 'San Antonio' WHEN 7 THEN 'San Diego' WHEN 8 THEN 'Dallas'
        WHEN 9 THEN 'San Jose'
    END AS CITY,
    CASE MOD(SEQ4(), 5)
        WHEN 0 THEN 'NY' WHEN 1 THEN 'CA' WHEN 2 THEN 'TX' WHEN 3 THEN 'IL' WHEN 4 THEN 'FL'
    END AS STATE,
    DATEADD(DAY, -MOD(SEQ4(), 3650), CURRENT_DATE()) AS ONBOARDING_DATE,
    CASE MOD(SEQ4(), 3)
        WHEN 0 THEN 'Active' WHEN 1 THEN 'Active' WHEN 2 THEN 'Suspended'
    END AS STATUS,
    ROUND(UNIFORM(0.015, 0.035, RANDOM())::NUMERIC(5,4), 4) AS PROCESSING_FEE_RATE
FROM TABLE(GENERATOR(ROWCOUNT => 500000));

-- Verify
SELECT 'MERCHANTS' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM MERCHANTS;

-- =============================================================================
-- STEP 3: CREATE TRANSACTIONS FACT TABLE (500M rows)
-- This is the largest table and takes the most time (~5-8 min on XL)
-- =============================================================================

CREATE OR REPLACE TABLE TRANSACTIONS AS
SELECT
    ROW_NUMBER() OVER (ORDER BY SEQ8()) AS TRANSACTION_ID,
    'TXN-' || LPAD(ROW_NUMBER() OVER (ORDER BY SEQ8())::VARCHAR, 12, '0') AS TRANSACTION_REF,
    MOD(SEQ8(), 500000) + 1 AS MERCHANT_ID,
    MOD(SEQ8(), 50000000) + 1 AS CARD_HOLDER_ID,
    DATEADD(SECOND,
        MOD(SEQ8(), 94608000),  -- ~3 years of seconds (2021-01-01 to 2023-12-31)
        '2021-01-01'::TIMESTAMP) AS TRANSACTION_TIMESTAMP,
    ROUND(
        CASE MOD(SEQ8(), 100)
            WHEN 0 THEN UNIFORM(5000, 50000, RANDOM())  -- high value (1%)
            ELSE UNIFORM(1, 500, RANDOM())               -- normal range (99%)
        END::NUMERIC(12,2), 2) AS AMOUNT,
    CASE MOD(SEQ8(), 4)
        WHEN 0 THEN 'USD' WHEN 1 THEN 'USD' WHEN 2 THEN 'USD' WHEN 3 THEN 'EUR'
    END AS CURRENCY,
    CASE MOD(SEQ8(), 5)
        WHEN 0 THEN 'CHIP' WHEN 1 THEN 'SWIPE' WHEN 2 THEN 'CONTACTLESS'
        WHEN 3 THEN 'ONLINE' WHEN 4 THEN 'MOBILE_WALLET'
    END AS ENTRY_MODE,
    CASE MOD(SEQ8(), 20)
        WHEN 0 THEN 'DECLINED' WHEN 1 THEN 'DECLINED'
        ELSE 'APPROVED'
    END AS AUTHORIZATION_STATUS,
    CASE MOD(SEQ8(), 50)
        WHEN 0 THEN 'FRAUD_SUSPECTED'
        WHEN 1 THEN 'CHARGEBACK'
        ELSE 'CLEAN'
    END AS RISK_FLAG,
    CASE MOD(SEQ8(), 3)
        WHEN 0 THEN 'VISA' WHEN 1 THEN 'MASTERCARD' WHEN 2 THEN 'AMEX'
    END AS CARD_NETWORK,
    MOD(SEQ8(), 200) + 1 AS TERMINAL_ID,
    CASE MOD(SEQ8(), 6)
        WHEN 0 THEN 'PURCHASE' WHEN 1 THEN 'PURCHASE' WHEN 2 THEN 'PURCHASE'
        WHEN 3 THEN 'REFUND' WHEN 4 THEN 'AUTH_ONLY' WHEN 5 THEN 'VOID'
    END AS TRANSACTION_TYPE
FROM TABLE(GENERATOR(ROWCOUNT => 500000000));

-- Verify
SELECT 'TRANSACTIONS' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM TRANSACTIONS;

-- =============================================================================
-- STEP 4: CREATE DAILY SETTLEMENTS TABLE (50M rows)
-- =============================================================================

CREATE OR REPLACE TABLE DAILY_SETTLEMENTS AS
SELECT
    ROW_NUMBER() OVER (ORDER BY SEQ4()) AS SETTLEMENT_ID,
    MOD(SEQ4(), 500000) + 1 AS MERCHANT_ID,
    DATEADD(DAY, MOD(SEQ4(), 1095), '2021-01-01'::DATE) AS SETTLEMENT_DATE,
    ROUND(UNIFORM(100, 500000, RANDOM())::NUMERIC(14,2), 2) AS GROSS_AMOUNT,
    ROUND(UNIFORM(1, 5000, RANDOM())::NUMERIC(14,2), 2) AS FEES_DEDUCTED,
    ROUND(UNIFORM(0, 10000, RANDOM())::NUMERIC(14,2), 2) AS CHARGEBACKS_DEDUCTED,
    ROUND(UNIFORM(90, 495000, RANDOM())::NUMERIC(14,2), 2) AS NET_SETTLEMENT_AMOUNT,
    UNIFORM(500, 50000, RANDOM()) AS TRANSACTION_COUNT,
    CASE MOD(SEQ4(), 3)
        WHEN 0 THEN 'COMPLETED' WHEN 1 THEN 'COMPLETED' WHEN 2 THEN 'PENDING'
    END AS SETTLEMENT_STATUS,
    'ACH' AS SETTLEMENT_METHOD
FROM TABLE(GENERATOR(ROWCOUNT => 50000000));

-- Verify
SELECT 'DAILY_SETTLEMENTS' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM DAILY_SETTLEMENTS;

-- =============================================================================
-- STEP 5: CREATE FRAUD ALERTS TABLE (10M rows)
-- =============================================================================

CREATE OR REPLACE TABLE FRAUD_ALERTS AS
SELECT
    ROW_NUMBER() OVER (ORDER BY SEQ4()) AS ALERT_ID,
    MOD(SEQ4(), 500000000) + 1 AS TRANSACTION_ID,
    MOD(SEQ4(), 500000) + 1 AS MERCHANT_ID,
    MOD(SEQ4(), 50000000) + 1 AS CARD_HOLDER_ID,
    DATEADD(SECOND, MOD(SEQ4(), 94608000), '2021-01-01'::TIMESTAMP) AS ALERT_TIMESTAMP,
    ROUND(UNIFORM(0.50, 0.99, RANDOM())::NUMERIC(4,2), 2) AS FRAUD_SCORE,
    CASE MOD(SEQ4(), 5)
        WHEN 0 THEN 'VELOCITY_CHECK' WHEN 1 THEN 'GEO_ANOMALY'
        WHEN 2 THEN 'AMOUNT_ANOMALY' WHEN 3 THEN 'CARD_NOT_PRESENT'
        WHEN 4 THEN 'DEVICE_FINGERPRINT'
    END AS ALERT_TYPE,
    CASE MOD(SEQ4(), 4)
        WHEN 0 THEN 'CONFIRMED_FRAUD' WHEN 1 THEN 'FALSE_POSITIVE'
        WHEN 2 THEN 'UNDER_REVIEW' WHEN 3 THEN 'ESCALATED'
    END AS DISPOSITION,
    CASE MOD(SEQ4(), 3)
        WHEN 0 THEN 'HIGH' WHEN 1 THEN 'MEDIUM' WHEN 2 THEN 'CRITICAL'
    END AS SEVERITY
FROM TABLE(GENERATOR(ROWCOUNT => 10000000));

-- Verify
SELECT 'FRAUD_ALERTS' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM FRAUD_ALERTS;

-- =============================================================================
-- STEP 6: CREATE CHARGEBACKS TABLE (5M rows)
-- =============================================================================

CREATE OR REPLACE TABLE CHARGEBACKS AS
SELECT
    ROW_NUMBER() OVER (ORDER BY SEQ4()) AS CHARGEBACK_ID,
    MOD(SEQ4(), 500000000) + 1 AS TRANSACTION_ID,
    MOD(SEQ4(), 500000) + 1 AS MERCHANT_ID,
    DATEADD(DAY, UNIFORM(1, 90, RANDOM()), '2021-01-01'::DATE + MOD(SEQ4(), 1095)) AS CHARGEBACK_DATE,
    ROUND(UNIFORM(10, 5000, RANDOM())::NUMERIC(12,2), 2) AS CHARGEBACK_AMOUNT,
    CASE MOD(SEQ4(), 6)
        WHEN 0 THEN 'FRAUD' WHEN 1 THEN 'PRODUCT_NOT_RECEIVED'
        WHEN 2 THEN 'DUPLICATE_CHARGE' WHEN 3 THEN 'UNAUTHORIZED'
        WHEN 4 THEN 'PRODUCT_DEFECTIVE' WHEN 5 THEN 'SERVICE_NOT_PROVIDED'
    END AS REASON_CODE,
    CASE MOD(SEQ4(), 4)
        WHEN 0 THEN 'OPEN' WHEN 1 THEN 'MERCHANT_WON'
        WHEN 2 THEN 'CARDHOLDER_WON' WHEN 3 THEN 'PENDING_REVIEW'
    END AS RESOLUTION_STATUS,
    UNIFORM(1, 180, RANDOM()) AS DAYS_TO_RESOLVE
FROM TABLE(GENERATOR(ROWCOUNT => 5000000));

-- Verify
SELECT 'CHARGEBACKS' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM CHARGEBACKS;

-- =============================================================================
-- STEP 7: CREATE WAREHOUSES FOR THE DEMO
-- =============================================================================

-- Standard warehouses (represent the "before" - team's random choices)
CREATE WAREHOUSE IF NOT EXISTS JPMC_MERCHANT_XL_WH
  WAREHOUSE_SIZE = 'XLARGE'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;

CREATE WAREHOUSE IF NOT EXISTS JPMC_MERCHANT_L_WH
  WAREHOUSE_SIZE = 'LARGE'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;

CREATE WAREHOUSE IF NOT EXISTS JPMC_MERCHANT_M_WH
  WAREHOUSE_SIZE = 'MEDIUM'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;

-- =============================================================================
-- STEP 8: CREATE ADAPTIVE WAREHOUSE
-- =============================================================================

/*
  NOTE: If your account has a failover group replicating WAREHOUSES to a region
  that doesn't support adaptive (e.g., Azure), you'll need to remove WAREHOUSES
  from the failover group first:

  USE ROLE ACCOUNTADMIN;
  ALTER FAILOVER GROUP <group_name> SET
    OBJECT_TYPES = DATABASES, ROLES, USERS, RESOURCE MONITORS;
*/

CREATE ADAPTIVE WAREHOUSE IF NOT EXISTS JPMC_MERCHANT_ADAPTIVE_WH
  WITH MAX_QUERY_PERFORMANCE_LEVEL = XLARGE
       QUERY_THROUGHPUT_MULTIPLIER = 4;

-- =============================================================================
-- STEP 9: VERIFY EVERYTHING
-- =============================================================================

-- Check all tables
SELECT 'TRANSACTIONS' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM TRANSACTIONS
UNION ALL SELECT 'MERCHANTS', COUNT(*) FROM MERCHANTS
UNION ALL SELECT 'CHARGEBACKS', COUNT(*) FROM CHARGEBACKS
UNION ALL SELECT 'DAILY_SETTLEMENTS', COUNT(*) FROM DAILY_SETTLEMENTS
UNION ALL SELECT 'FRAUD_ALERTS', COUNT(*) FROM FRAUD_ALERTS;

-- Check all warehouses
SHOW WAREHOUSES LIKE 'JPMC_MERCHANT_%';

-- Check adaptive warehouse details
SHOW WAREHOUSES LIKE 'JPMC_MERCHANT_ADAPTIVE_WH';

-- Suspend the data load warehouse (no longer needed)
ALTER WAREHOUSE DEMO_DATA_LOAD_WH SUSPEND;

/*
  ================================================================================
  DATA GENERATION COMPLETE!
  
  Next steps:
  1. Run the demo script: 02_adaptive_warehouse_demo.sql
  2. All queries use JPMC_MERCHANT_ADAPTIVE_WH
  3. Check query history after running to see adaptive right-sizing in action
  ================================================================================
*/
