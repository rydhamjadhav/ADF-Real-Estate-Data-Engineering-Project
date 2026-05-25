# 🏢 Real Estate Analytics Platform
### End-to-End Cloud Data Warehouse on Microsoft Azure

> An enterprise-grade ETL pipeline ingesting, validating, and warehousing real estate data across 6 global regions — built with Azure Data Factory, Azure SQL Database, and Azure Blob Storage.

---

## 📌 Project Overview

This project delivers a fully automated cloud data warehouse for a global real estate firm operating across **APAC, Middle East, Europe, Africa, LATAM, and North America**. Raw CSV data is ingested from Azure Blob Storage, validated and transformed through ADF pipelines, and loaded into a star schema data warehouse optimised for analytical reporting.

| Metric | Value |
|--------|-------|
| Total fact rows loaded | 83,456 |
| Pipeline success rate | 5/5 (0 failures) |
| Invalid rows detected | 0 |
| NULL FK violations | 0 |
| Peak agent revenue (APAC) | $1.48B |
| Best marketing channel ROI | 5,753% (Social Ads) |
| Listings tracked end-to-end | 12,000 |

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-----------|
| Orchestration | Azure Data Factory V2 |
| Storage (Landing Zone) | Azure Blob Storage |
| Data Warehouse | Azure SQL Database |
| Data Modelling | Star Schema (Medallion Architecture) |
| Reporting | Pre-aggregated RPT schema views (Power BI ready) |

---

## 🏗️ Architecture

The platform follows a **classic medallion architecture** adapted for Azure:

```
CSV Files (Blob Storage)
        ↓
  [pl_IngestRawToStaging]
  8 parallel Copy activities
        ↓
  Staging Schema (stg)
  8 NVARCHAR staging tables
        ↓
  [df_Validate_Transaction]
  ADF Mapping Data Flow
  Valid → stg.Transactions | Invalid → error-logs (Blob)
        ↓
  [pl_Transform_StagingToDW]
  5 Dimension SPs → 4 Fact SPs
        ↓
  Data Warehouse Schema (dwh)
  Star schema: 5 dims + 4 facts
        ↓
  Reporting Schema (rpt)
  Pre-aggregated views → Power BI
```

All three pipelines are orchestrated by a master pipeline: **`pl_Master_RealEstate_ETL`**.

---

## 📂 Source Data

| Source File | Rows | Staging Table |
|-------------|------|---------------|
| Agents.csv | 500 | stg.Agents |
| Properties.csv | 8,000 | stg.Properties |
| Listings.csv | 12,000 | stg.Listings |
| Campaigns.csv | 1,500 | stg.Campaigns |
| Leads.csv | 50,000 | stg.Leads |
| Offers.csv | 25,000 | stg.Offers |
| Viewings.csv | 40,000 | stg.Viewings |
| Transactions.csv | 8,456 | stg.Transactions |

---

## 🗃️ Data Model (Star Schema)

### Dimension Tables

| Table | Primary Key | Rows | SCD Note |
|-------|-------------|------|----------|
| dwh.dim_Agent | AgentSK (INT) | 500 | IsCurrent flag ready |
| dwh.dim_Property | PropertySK (INT) | 8,000 | IsCurrent flag ready |
| dwh.dim_Listing | ListingSK (INT) | 12,000 | EndDate = 9999-12-31 for active |
| dwh.dim_Campaign | CampaignSK (INT) | 1,500 | IsCurrent flag ready |
| dwh.dim_Date | DateKey (INT yyyyMMdd) | Populated | Covers all transactional dates |

### Fact Tables

| Table | Primary Key | Rows | Key Measures |
|-------|-------------|------|-------------|
| dwh.fact_Sales | SalesSK | 8,456 | SalePrice, DaysToClose, DiscountPct |
| dwh.fact_Leads | LeadSK | 50,000 | LeadScore, IsConverted |
| dwh.fact_Offers | OfferSK | 25,000 | OfferPrice, IsAccepted, CounterPrice |
| dwh.fact_Viewings | ViewingSK | 0 ⚠️ | ViewingType, AttendeeCount |

> ⚠️ `dwh.fact_Viewings` contains 0 rows due to a known JOIN column mismatch — see [Known Issues](#-known-issues).

---

## ⚙️ Pipeline Design

### Pipeline 1 — `pl_IngestRawToStaging`
- Captures pipeline start time via `@utcNow()`
- Runs **8 parallel Copy Data activities** (one per CSV file)
- Each Copy activity uses `TRUNCATE TABLE` pre-copy script for full refresh
- Dual-path logging: `SP_LogSuccess` / `SP_LogFailure` → `stg.PipelineLog`

### Pipeline 2 — `pl_Transform_StagingToDW`
- `sp_LoadDimDate` runs first (prerequisite for all fact DateKey FKs)
- 4 dimension SPs run in **parallel** (DimAgent, DimProperty, DimListing, DimCampaign)
- Fact SPs execute **sequentially**: `fact_Sales → fact_Offers → fact_Leads`
- Post-load row count check via Lookup + If Condition; Fail activity fires if empty

### Pipeline 3 — `pl_Master_RealEstate_ETL`
- Single ETL entry point: `Run_Ingest → Run_Transform` (sequential, Wait on Completion = YES)
- `sp_MasterLogFailure` captures any child pipeline failure
- Daily schedule trigger (`TRG_Daily_RealEstate`, 2:00 AM UTC) — currently **Inactive** pending production sign-off

---

## ✅ Data Validation Strategy

A four-layer validation approach ensures end-to-end data quality:

1. **ADF Mapping Data Flow** (`df_Validate_Transaction`) — flags rows with NULL TransactionID, NULL/non-positive SalePrice, NULL OfferDate, or NULL ClosingDate; routes invalid rows to `error-logs` Blob container
2. **SQL NULL checks** on all critical fact FK columns — 5/5 checks returned `FailCount = 0`
3. **Row count reconciliation** — 7 of 8 entities match perfectly across source → staging → DWH
4. **Automated pipeline logging** — every run recorded in `stg.PipelineLog` with 11 fields

**Result: 0 invalid rows across all 144,456 combined source rows.**

---

## 📊 Business Insights

| Analysis | Key Finding |
|----------|-------------|
| Agent Productivity | Agent AG0378 (Hong Kong, APAC) generated $1.48B in revenue across 26 sales |
| Regional Performance | APAC and Middle East dominate top 10 agents by revenue |
| Property Market | Cape Town Medium Apartments achieved 52% listing conversion rate — highest in dataset |
| Campaign ROI | Social Ads: 5,753% ROI ($16K CPL); Search Ads: lowest ROI (~$103K CPL) |
| Listing Funnel | LS006523 (Middle East Apartment) achieved 100% offer-to-sale conversion |

**Recommendation:** Reallocate Search Ads budget to Social Ads and Portal Featured channels — potential $300M+ additional revenue per cycle.

---

## 🔧 Stored Procedures

| Procedure | Purpose |
|-----------|---------|
| `usp_Load_dim_Agent` | Loads/upserts agent records with type casting |
| `usp_Load_dim_Property` | Loads property records with type casting |
| `usp_Load_dim_Listing` | Applies 9999-12-31 sentinel for active listings |
| `usp_Load_dim_Campaign` | Loads campaign records |
| `usp_Load_dim_Date` | Generates/refreshes date dimension |
| `usp_Load_fact_Sales` | SK lookups, casts SalePrice, computes DaysToClose |
| `usp_Load_fact_Offers` | SK lookups, casts OfferPrice, maps IsAccepted |
| `usp_Load_fact_Leads` | SK lookups, caps LeadScore at 100, maps IsConverted |
| `usp_Run_Full_DWH_Load` | Orchestrates all 9 SPs in dependency order |
| `usp_Log_PipelineRun` | Inserts execution record into stg.PipelineLog |

---

## 📋 Business Rules

| # | Rule | Detail |
|---|------|--------|
| 1 | LeadScore Cap | Values >100 corrected to 100 (179 rows fixed); enforced in SP via CASE |
| 2 | NVARCHAR Staging | All staging columns NVARCHAR — casting handled exclusively in SPs via TRY_CAST |
| 3 | Active Listing Sentinel | EndDate = 9999-12-31 for active listings to simplify date joins |
| 4 | Surrogate Keys | Auto-incrementing integer SKs on all dims/facts for SCD Type 2 readiness |
| 5 | IsCurrent Flag | All 5 dimension tables include IsCurrent BIT + EffectiveFrom/EffectiveTo |
| 6 | TRUNCATE Pre-Copy | Full refresh enforced on every pipeline run — no duplicate accumulation |
| 7 | ADF Fault Tolerance | Incompatible rows skipped (not failed); logged to Blob audit file |
| 8 | Invalid Row Routing | df_Validate_Transaction routes bad rows to error-logs Blob container |
| 9 | Parallel Dim Loading | 4 dimensions load in parallel after DimDate resolves |
| 10 | Sequential Fact Loading | Facts load sequentially to guarantee dimension availability for SK lookups |
| 11 | Automated Logging | Every run logged in stg.PipelineLog via SP_LogSuccess/SP_LogFailure |

---

## ⚠️ Known Issues

### Issue 1 — `dwh.fact_Viewings` Contains Zero Rows
- **Root cause:** JOIN column mismatch between `stg.Viewings` (ListingID) and `dwh.dim_Listing` — all LEFT JOIN rows produce NULL ListingKey, excluded by referential integrity WHERE clause
- **Fix:** Align JOIN column references in `usp_Load_fact_Viewings` and re-run transformation pipeline
- **Status:** Prioritised for next sprint

### Issue 2 — Pipeline Log RowsRead / RowsLoaded Hardcoded to Zero
- **Root cause:** ADF pipelines pass static zero values instead of dynamic activity output expressions
- **Fix:** Replace with `@activity('Copy_Agents').output.rowsRead` and `.rowsCopied`
- **Status:** Low-risk, schema-free change

---

## 🚀 Future Improvements

- **Activate Daily Trigger** — `TRG_Daily_RealEstate` (2:00 AM UTC) is built and ready; pending production sign-off
- **Power BI Dashboard** — Connect to `rpt` schema views (DirectQuery or Import); Agent Productivity and Sales Performance dashboards with Region/Year/PropertyType/Channel slicers are ready
- **SCD Type 2** — IsCurrent, EffectiveFrom, EffectiveTo columns already in place on all dimensions; implement on `dim_Agent` and `dim_Property` first
- **Incremental Load** — Replace TRUNCATE+reload with watermark-based incremental loading for high-volume tables (Leads 50K, Viewings 40K)
- **Azure Monitor Alerts** — Email/Teams notifications on pipeline failure or duration threshold breach

---

## 👤 Author

**Rydham Jadhav** — `Int_1098`
