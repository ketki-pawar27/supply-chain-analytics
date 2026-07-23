-- =============================================
-- S&OE Exception Reporting
-- Author: Ketki Pawar
-- Description: Identify demand vs supply gaps
-- for short-term execution planning.
-- Flags exceptions requiring immediate action
-- by supply planners and operations teams.
-- =============================================

-- S&OE = Sales & Operations Execution
-- Focus: Near-term (0-13 weeks) supply risk

WITH demand_forecast AS (
    SELECT
        sku_id,
        product_name,
        region,
        week_number,
        forecast_date,
        SUM(forecast_units)    AS total_forecast_demand
    FROM demand_plan
    WHERE forecast_date BETWEEN CURRENT_DATE
        AND DATEADD(week, 13, CURRENT_DATE)
    GROUP BY
        sku_id,
        product_name,
        region,
        week_number,
        forecast_date
),

supply_plan AS (
    SELECT
        sku_id,
        region,
        week_number,
        SUM(planned_supply_units)    AS total_planned_supply,
        SUM(confirmed_po_units)      AS total_confirmed_supply
    FROM supply_schedule
    WHERE planned_date BETWEEN CURRENT_DATE
        AND DATEADD(week, 13, CURRENT_DATE)
    GROUP BY
        sku_id,
        region,
        week_number
),

inventory_position AS (
    SELECT
        sku_id,
        region,
        SUM(on_hand_units)             AS on_hand,
        SUM(safety_stock_units)        AS safety_stock_target
    FROM inventory_snapshot
    WHERE snapshot_date = CURRENT_DATE
    GROUP BY sku_id, region
),

soe_gap_analysis AS (
    SELECT
        d.sku_id,
        d.product_name,
        d.region,
        d.week_number,
        d.forecast_date,
        d.total_forecast_demand,
        COALESCE(s.total_planned_supply, 0)    AS total_planned_supply,
        COALESCE(s.total_confirmed_supply, 0)  AS total_confirmed_supply,
        i.on_hand,
        i.safety_stock_target,
        -- Gap = Demand minus Supply
        d.total_forecast_demand
            - COALESCE(s.total_confirmed_supply, 0) AS supply_gap,
        -- Coverage check against safety stock
        CASE
            WHEN COALESCE(s.total_confirmed_supply, 0) = 0
                AND d.total_forecast_demand > 0
                THEN 'NO SUPPLY CONFIRMED'
            WHEN d.total_forecast_demand
                - COALESCE(s.total_confirmed_supply, 0) > 0
                THEN 'SUPPLY SHORTAGE'
            WHEN i.on_hand < i.safety_stock_target
                THEN 'BELOW SAFETY STOCK'
            WHEN COALESCE(s.total_confirmed_supply, 0)
                > d.total_forecast_demand * 1.5
                THEN 'POTENTIAL OVERSTOCK'
            ELSE 'ON TRACK'
        END AS exception_flag,
        -- Priority based on weeks out
        CASE
            WHEN d.week_number <= 4  THEN '1 - Immediate Action'
            WHEN d.week_number <= 8  THEN '2 - Monitor Closely'
            ELSE                          '3 - Plan Ahead'
        END AS action_priority
    FROM demand_forecast d
    LEFT JOIN supply_plan s
        ON d.sku_id = s.sku_id
        AND d.region = s.region
        AND d.week_number = s.week_number
    LEFT JOIN inventory_position i
        ON d.sku_id = i.sku_id
        AND d.region = i.region
)

SELECT
    sku_id,
    product_name,
    region,
    week_number,
    forecast_date,
    total_forecast_demand,
    total_confirmed_supply,
    supply_gap,
    on_hand,
    safety_stock_target,
    exception_flag,
    action_priority
FROM soe_gap_analysis
WHERE exception_flag != 'ON TRACK'
ORDER BY
    action_priority ASC,
    supply_gap DESC;
