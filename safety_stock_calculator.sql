-- =============================================
-- Safety Stock Calculator
-- Author: Ketki Pawar
-- Description: Calculate optimal safety stock
-- levels based on demand variability and 
-- lead time deviation
-- =============================================

-- Safety Stock Formula:
-- Safety Stock = Z x Lead Time Deviation x Avg Daily Demand
-- Z = 1.65 for 95% service level
-- Z = 1.28 for 90% service level

-- Sample data setup
WITH demand_data AS (
    SELECT
        sku_id,
        product_name,
        AVG(daily_demand)        AS avg_daily_demand,
        STDDEV(daily_demand)     AS demand_stddev,
        AVG(lead_time_days)      AS avg_lead_time,
        STDDEV(lead_time_days)   AS lead_time_stddev
    FROM inventory_transactions
    WHERE transaction_date >= DATEADD(month, -3, CURRENT_DATE)
    GROUP BY sku_id, product_name
),

safety_stock_calc AS (
    SELECT
        sku_id,
        product_name,
        ROUND(avg_daily_demand, 2)    AS avg_daily_demand,
        ROUND(lead_time_stddev, 2)    AS lead_time_deviation,
        1.65                          AS z_score_95pct,
        -- Safety Stock at 95% service level
        ROUND(1.65 * lead_time_stddev * avg_daily_demand, 0)  AS safety_stock_95pct,
        -- Safety Stock at 90% service level
        ROUND(1.28 * lead_time_stddev * avg_daily_demand, 0)  AS safety_stock_90pct,
        -- Reorder Point = Safety Stock + (Avg Lead Time x Avg Daily Demand)
        ROUND(
            (1.65 * lead_time_stddev * avg_daily_demand)
            + (avg_lead_time * avg_daily_demand), 0
        )                             AS reorder_point
    FROM demand_data
    WHERE avg_daily_demand > 0
)

SELECT
    sku_id,
    product_name,
    avg_daily_demand,
    lead_time_deviation,
    safety_stock_95pct,
    safety_stock_90pct,
    reorder_point,
    CASE
        WHEN safety_stock_95pct > 500 THEN 'High Buffer Required'
        WHEN safety_stock_95pct > 100 THEN 'Medium Buffer Required'
        ELSE 'Low Buffer Required'
    END AS risk_category
FROM safety_stock_calc
ORDER BY safety_stock_95pct DESC;
