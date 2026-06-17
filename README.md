# Adaptive Warehouses

Snowflake Adaptive Warehouse demos and hands-on lab materials.

## Overview

Adaptive Warehouses are a new warehouse type (`WAREHOUSE_TYPE = 'ADAPTIVE'`) that automatically optimizes compute resources based on workload patterns. Unlike traditional Standard warehouses (Gen1/Gen2) that require manual sizing, Adaptive Warehouses dynamically adjust to deliver optimal price-performance.

## Project Structure

```
ADAPTIVE_WAREHOUSES/
├── README.md
├── 01_Getting_Started.ipynb          # Create and configure adaptive warehouses
├── 02_Workload_Comparison.ipynb      # Compare Gen1 vs Gen2 vs Adaptive performance
└── 03_Migration_Guide.ipynb          # Migrate existing warehouses to Adaptive
```

## Key Concepts

- **No sizing required** — no WAREHOUSE_SIZE parameter needed
- **Shared compute pool** — resources allocated dynamically
- **Automatic scaling** — adjusts to workload demands
- **Cost-efficient** — pay for actual compute used
