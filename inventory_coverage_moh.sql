-- =============================================
-- Inventory Coverage Analysis (MOH)
-- Author: Ketki Pawar
-- Description: Calculate Months on Hand (MOH)
-- across SKUs to identify coverage risks
-- and flag exception items
-- =============================================

-- MOH Formula:
-- MOH = Current Inventory / Average Monthly Demand

WITH monthly_demand AS (
    SELECT
        sku_id,
        product_name,
        region,
        SUM(demand_units)              AS total_demand_units,
        COUNT(DISTINCT month_year)     AS months_of_data,
        ROUND(
            SUM(demand_units) / NULLIF(COUNT(DISTINCT month_year), 0)
        , 2)                           AS avg_monthly_demand
    FROM demand_history
    WHERE month_year >= DATEADD(month, -6, CURRENT_DATE)
    GROUP BY sku_id, product_name, region
),

current_inventory AS (
    SELECT
        sku_id,
        region,
        SUM(on_hand_units)    AS total_on_hand,
        SUM(in_transit_units) AS total_in_transit,
        SUM(on_hand_units) + SUM(in_transit_units) AS total_available
    FROM inventory_snapshot
    WHERE snapshot_date = CURRENT_DATE
    GROUP BY sku_id, region
),

moh_calculation AS (
    SELECT
        d.sku_id,
        d.product_name,
        d.region,
        d.avg_monthly_demand,
        i.total_on_hand,
        i.total_in_transit,
        i.total_available,
        ROUND(
            i.total_available / NULLIF(d.avg_monthly_demand, 0)
        , 2)                AS months_on_hand,
        -- Coverage status based on MOH thresholds
        CASE
            WHEN i.total_available / NULLIF(d.avg_monthly_demand, 0) < 1
                THEN 'CRITICAL - Less than 1 month coverage'
            WHEN i.total_available / NULLIF(d.avg_monthly_demand, 0) < 2
                THEN 'AT RISK - Less than 2 months coverage'
            WHEN i.total_available / NULLIF(d.avg_monthly_demand, 0) > 6
                THEN 'EXCESS - More than 6 months coverage'
            ELSE 'HEALTHY - Coverage within target range'
        END AS coverage_status
    FROM monthly_demand d
    LEFT JOIN current_inventory i
        ON d.sku_id = i.sku_id
        AND d.region = i.region
)

SELECT
    sku_id,
    product_name,
    region,
    avg_monthly_demand,
    total_on_hand,
    total_in_transit,
    total_available,
    months_on_hand,
    coverage_status
FROM moh_calculation
ORDER BY
    CASE coverage_status
        WHEN 'CRITICAL - Less than 1 month coverage' THEN 1
        WHEN 'AT RISK - Less than 2 months coverage' THEN 2
        WHEN 'EXCESS - More than 6 months coverage'  THEN 3
        ELSE 4
    END,
    months_on_hand ASC;
