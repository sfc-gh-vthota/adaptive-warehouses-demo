# Adaptive Warehouse Demo — JPMC Merchant Services

Demonstrates how Snowflake **Adaptive Warehouses** eliminate compute waste by automatically right-sizing resources per query, replacing the need for teams to manually pick warehouse sizes.

## Customer Problem

The Merchant Services LOB team randomly uses XL, L, and M warehouses regardless of workload complexity:
- Simple lookups run on XL warehouses → **credits wasted**
- Complex analytics run on M warehouses → **SLAs missed**
- XL warehouse kept running all day "just in case" → **160 credits/day burned**

## Solution: Adaptive Compute

Adaptive Warehouses route each query to optimal resources from a shared account-level pool. No manual sizing decisions needed.

| Query Complexity | Adaptive Allocates | Before (Manual) | Waste Eliminated |
|---|---|---|---|
| Point lookup | Minimal (XS-equiv) | XL | 16x |
| Simple aggregation | Small (S-equiv) | L | 4x |
| Medium scan | Medium (M-equiv) | XL | 4x |
| Multi-table join | Large (L-equiv) | M (too slow!) | Right-sized + faster |
| Complex analytics | XL-equivalent | M (crashes!) | Right-sized + faster |

## Scripts

| File | Purpose | Run Time |
|------|---------|----------|
| `01_data_generation.sql` | Creates database, tables (500M+ rows), and warehouses | ~10-15 min |
| `02_adaptive_warehouse_demo.sql` | 8 demo queries showing adaptive right-sizing | ~5 min |

## Data Model

```
JPMC_MERCHANT_SERVICES_DEMO.MERCHANT_DATA
├── TRANSACTIONS      (500M rows) — Card payment transactions
├── MERCHANTS         (500K rows) — Merchant dimension
├── DAILY_SETTLEMENTS  (50M rows) — Settlement batches
├── FRAUD_ALERTS       (10M rows) — Fraud detection events
└── CHARGEBACKS         (5M rows) — Dispute records
```

## Prerequisites

- Snowflake account in **AWS us-west-2** (or other supported adaptive region)
- **Enterprise edition** or above
- SYSADMIN role for object creation
- ACCOUNTADMIN if failover group modification is needed

## Quick Start

```sql
-- 1. Run data generation (uses XL warehouse for speed)
-- Execute: 01_data_generation.sql

-- 2. Run the demo queries on the adaptive warehouse
-- Execute: 02_adaptive_warehouse_demo.sql

-- 3. Check query history to see adaptive in action
SELECT QUERY_TEXT, WAREHOUSE_SIZE, TOTAL_ELAPSED_TIME/1000 AS SECONDS
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY(RESULT_LIMIT => 20))
WHERE WAREHOUSE_NAME = 'JPMC_MERCHANT_ADAPTIVE_WH'
ORDER BY START_TIME DESC;
```

## Key Adaptive Warehouse Parameters

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `MAX_QUERY_PERFORMANCE_LEVEL` | XLARGE | Caps maximum per-query resources |
| `QUERY_THROUGHPUT_MULTIPLIER` | 4 | Controls concurrent throughput capacity |

## Cleanup

```sql
DROP WAREHOUSE IF EXISTS JPMC_MERCHANT_ADAPTIVE_WH;
DROP WAREHOUSE IF EXISTS JPMC_MERCHANT_XL_WH;
DROP WAREHOUSE IF EXISTS JPMC_MERCHANT_L_WH;
DROP WAREHOUSE IF EXISTS JPMC_MERCHANT_M_WH;
DROP WAREHOUSE IF EXISTS DEMO_DATA_LOAD_WH;
DROP DATABASE IF EXISTS JPMC_MERCHANT_SERVICES_DEMO;
```
