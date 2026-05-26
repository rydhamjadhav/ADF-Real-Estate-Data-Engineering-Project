-- ══════════════════════════════════════════════════════════════
-- SECTION B : ANALYTICAL / POWER BI QUERIES
-- ══════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- B1. Agent Productivity Dashboard
--     Metrics : Sales count, Total Revenue, Avg Sale Price,
--               Total Leads, Conversion Rate (leads→sales)
-- ─────────────────────────────────────────────────────────────
SELECT
    da.AgentID,
    da.AgentName,
    da.Region,
    da.City,
    da.ExperienceYears,
    -- Sales metrics
    COUNT(DISTINCT fs.SalesKey)          AS TotalSales,
    ISNULL(SUM(fs.SalePrice), 0)         AS TotalRevenue,
    ISNULL(AVG(fs.SalePrice), 0)         AS AvgSalePrice,
    ISNULL(AVG(fs.PriceDiscountPct), 0)  AS AvgDiscountPct,
    ISNULL(AVG(CAST(fs.DaysToClose AS FLOAT)), 0) AS AvgDaysToClose,
    -- Lead metrics (per agent's listings)
    COUNT(DISTINCT fl.LeadKey)           AS TotalLeads,
    -- Conversion rate
    CASE
        WHEN COUNT(DISTINCT fl.LeadKey) > 0
        THEN ROUND(COUNT(DISTINCT fs.SalesKey) * 100.0
                   / COUNT(DISTINCT fl.LeadKey), 2)
        ELSE 0
    END                                  AS LeadToSaleConvPct
FROM dwh.dim_Agent   da
LEFT JOIN dwh.fact_Sales  fs ON fs.AgentKey    = da.AgentKey
LEFT JOIN dwh.dim_Listing dl ON dl.ListingKey  = fs.ListingKey AND dl.IsCurrent = 1
LEFT JOIN dwh.fact_Leads  fl ON fl.ListingKey  = dl.ListingKey
WHERE da.IsCurrent = 1
GROUP BY
    da.AgentID, da.AgentName, da.Region, da.City, da.ExperienceYears
ORDER BY TotalRevenue DESC;


-- ─────────────────────────────────────────────────────────────
-- B2. Sales Performance by Region & Property Type (Monthly)
-- ─────────────────────────────────────────────────────────────
SELECT
    dd.Year,
    dd.MonthNum,
    dd.MonthName,
    dd.Quarter,
    dp.Region,
    dp.PropertyType,
    COUNT(fs.SalesKey)           AS SalesCount,
    SUM(fs.SalePrice)            AS TotalRevenue,
    AVG(fs.SalePrice)            AS AvgSalePrice,
    MIN(fs.SalePrice)            AS MinSalePrice,
    MAX(fs.SalePrice)            AS MaxSalePrice,
    AVG(CAST(fs.DaysToClose AS FLOAT)) AS AvgDaysToClose
FROM dwh.fact_Sales   fs
JOIN dwh.dim_Date     dd ON dd.DateKey    = fs.ClosingDateKey
JOIN dwh.dim_Property dp ON dp.PropertyKey = fs.PropertyKey
GROUP BY
    dd.Year, dd.MonthNum, dd.MonthName, dd.Quarter,
    dp.Region, dp.PropertyType
ORDER BY dd.Year, dd.MonthNum, dp.Region;


-- B3. Property Inventory & Pricing Trends
-- ─────────────────────────────────────────────────────────────
SELECT
    dp.Region,
    dp.City,
    dp.PropertyType,
    dp.SizeCategory,
    COUNT(dl.ListingKey)          AS TotalListings,
    SUM(CASE WHEN dl.Status = 'Active' THEN 1 ELSE 0 END) AS ActiveListings,
    SUM(CASE WHEN dl.Status = 'Sold'   THEN 1 ELSE 0 END) AS SoldListings,
    AVG(dl.AskingPrice)           AS AvgAskingPrice,
    AVG(fs.SalePrice)             AS AvgActualSalePrice,
    AVG(CAST(dl.ListingDays AS FLOAT)) AS AvgDaysOnMarket
FROM dwh.dim_Property dp
JOIN dwh.dim_Listing  dl ON dl.PropertyID = dp.PropertyID AND dl.IsCurrent = 1
LEFT JOIN dwh.fact_Sales fs ON fs.ListingKey = dl.ListingKey
WHERE dp.IsCurrent = 1
GROUP BY dp.Region, dp.City, dp.PropertyType, dp.SizeCategory
ORDER BY dp.Region, dp.City;


-- B4. Campaign ROI & Lead Conversion
-- ─────────────────────────────────────────────────────────────
SELECT
    dc.Channel,
    COUNT(DISTINCT dc.CampaignKey)   AS CampaignCount,
    SUM(dc.Cost)                     AS TotalCost,
    COUNT(DISTINCT fl.LeadKey)       AS TotalLeads,
    COUNT(DISTINCT fs.SalesKey)      AS ConvertedSales,
    ISNULL(SUM(fs.SalePrice), 0)     AS TotalRevenue,
    -- Cost per Lead
    CASE WHEN COUNT(DISTINCT fl.LeadKey) > 0
         THEN ROUND(SUM(dc.Cost) / COUNT(DISTINCT fl.LeadKey), 2) ELSE 0
    END AS CostPerLead,
    -- ROI %
    CASE WHEN SUM(dc.Cost) > 0
         THEN ROUND((ISNULL(SUM(fs.SalePrice), 0) - SUM(dc.Cost)) * 100.0
                    / SUM(dc.Cost), 2)
         ELSE 0
    END AS ROI_Pct
FROM dwh.dim_Campaign  dc
LEFT JOIN dwh.dim_Listing dl ON dl.ListingID = dc.ListingID AND dl.IsCurrent = 1
LEFT JOIN dwh.fact_Leads  fl ON fl.ListingKey = dl.ListingKey
LEFT JOIN dwh.fact_Sales  fs ON fs.ListingKey  = dl.ListingKey
GROUP BY dc.Channel
ORDER BY ROI_Pct DESC;


-- ─────────────────────────────────────────────────────────────
-- B5. Sales Funnel (Leads → Viewings → Offers → Sales)
-- ─────────────────────────────────────────────────────────────
SELECT
    dl.ListingID,
    da.AgentName,
    dp.Region,
    dp.PropertyType,
    dl.AskingPrice,
    COUNT(DISTINCT fl.LeadKey)    AS Leads,
    COUNT(DISTINCT fv.ViewingKey) AS Viewings,
    COUNT(DISTINCT fo.OfferKey)   AS Offers,
    COUNT(DISTINCT fs.SalesKey)   AS Sales,
    -- Funnel rates
    CASE WHEN COUNT(DISTINCT fl.LeadKey) > 0
         THEN ROUND(COUNT(DISTINCT fv.ViewingKey)*100.0/COUNT(DISTINCT fl.LeadKey),1)
         ELSE 0 END AS LeadToViewingPct,
    CASE WHEN COUNT(DISTINCT fv.ViewingKey) > 0
         THEN ROUND(COUNT(DISTINCT fo.OfferKey)*100.0/COUNT(DISTINCT fv.ViewingKey),1)
         ELSE 0 END AS ViewingToOfferPct,
    CASE WHEN COUNT(DISTINCT fo.OfferKey) > 0
         THEN ROUND(COUNT(DISTINCT fs.SalesKey)*100.0/COUNT(DISTINCT fo.OfferKey),1)
         ELSE 0 END AS OfferToSalePct
FROM dwh.dim_Listing  dl
JOIN dwh.dim_Agent    da ON da.AgentID    = dl.AgentID    AND da.IsCurrent = 1
JOIN dwh.dim_Property dp ON dp.PropertyID = dl.PropertyID AND dp.IsCurrent = 1
LEFT JOIN dwh.fact_Leads    fl ON fl.ListingKey = dl.ListingKey
LEFT JOIN dwh.fact_Viewings fv ON fv.ListingKey = dl.ListingKey
LEFT JOIN dwh.fact_Offers   fo ON fo.ListingKey = dl.ListingKey
LEFT JOIN dwh.fact_Sales    fs ON fs.ListingKey = dl.ListingKey
WHERE dl.IsCurrent = 1
GROUP BY dl.ListingID, da.AgentName, dp.Region, dp.PropertyType, dl.AskingPrice
ORDER BY Leads DESC;

PRINT 'Validation and Analytical queries ready.';
GO