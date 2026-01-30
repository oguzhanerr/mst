-- =============================================================================
-- Dashboard KPI Queries for Giga MST
-- Ready-to-use queries for Superset Big Number and Table charts
-- =============================================================================

-- -----------------------------------------------------------------------------
-- KPI 1: Total Schools
-- Chart type: Big Number
-- -----------------------------------------------------------------------------
SELECT COUNT(*) AS total_schools
FROM school;


-- -----------------------------------------------------------------------------
-- KPI 2: 4G Coverage Rate
-- Chart type: Big Number with Trendline
-- -----------------------------------------------------------------------------
SELECT
    ROUND(100.0 * SUM(CASE WHEN fourg THEN 1 ELSE 0 END) / COUNT(*), 1) AS coverage_rate_4g
FROM school;


-- -----------------------------------------------------------------------------
-- KPI 3: Schools Without Coverage
-- Chart type: Big Number (use red color)
-- -----------------------------------------------------------------------------
SELECT COUNT(*) AS schools_no_coverage
FROM school
WHERE NOT fourg AND NOT threeg AND NOT twog;


-- -----------------------------------------------------------------------------
-- KPI 4: Total Cell Towers
-- Chart type: Big Number
-- -----------------------------------------------------------------------------
SELECT COUNT(*) AS total_towers
FROM celltower;


-- -----------------------------------------------------------------------------
-- KPI 5: LTE Towers
-- Chart type: Big Number
-- -----------------------------------------------------------------------------
SELECT COUNT(*) AS lte_towers
FROM celltower
WHERE radio_type = 'LTE';


-- -----------------------------------------------------------------------------
-- KPI 6: Average Distance to Fiber
-- Chart type: Big Number
-- -----------------------------------------------------------------------------
SELECT ROUND(AVG(fiber_node_distance)::numeric, 2) AS avg_fiber_distance_km
FROM school
WHERE fiber_node_distance IS NOT NULL;


-- -----------------------------------------------------------------------------
-- PIE CHART: Coverage Distribution
-- Chart type: Pie Chart
-- -----------------------------------------------------------------------------
SELECT
    CASE
        WHEN fourg THEN '4G Coverage'
        WHEN threeg THEN '3G Only'
        WHEN twog THEN '2G Only'
        ELSE 'No Coverage'
    END AS coverage_status,
    COUNT(*) AS school_count
FROM school
GROUP BY 1
ORDER BY school_count DESC;


-- -----------------------------------------------------------------------------
-- BAR CHART: Schools by Education Level
-- Chart type: Bar Chart
-- -----------------------------------------------------------------------------
SELECT
    education_level,
    COUNT(*) AS total,
    SUM(CASE WHEN fourg THEN 1 ELSE 0 END) AS with_4g,
    SUM(CASE WHEN NOT fourg AND NOT threeg AND NOT twog THEN 1 ELSE 0 END) AS no_coverage
FROM school
GROUP BY education_level
ORDER BY total DESC;


-- -----------------------------------------------------------------------------
-- BAR CHART: Towers by Type
-- Chart type: Bar Chart
-- -----------------------------------------------------------------------------
SELECT
    radio_type,
    COUNT(*) AS tower_count
FROM celltower
GROUP BY radio_type
ORDER BY tower_count DESC;


-- -----------------------------------------------------------------------------
-- LINE/AREA: Distance Distribution
-- Chart type: Histogram or Area Chart
-- -----------------------------------------------------------------------------
SELECT
    CASE
        WHEN nearest_lte_distance < 1 THEN '0-1 km'
        WHEN nearest_lte_distance < 2 THEN '1-2 km'
        WHEN nearest_lte_distance < 5 THEN '2-5 km'
        WHEN nearest_lte_distance < 10 THEN '5-10 km'
        WHEN nearest_lte_distance < 20 THEN '10-20 km'
        ELSE '20+ km'
    END AS distance_range,
    COUNT(*) AS school_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1) AS percentage
FROM school
GROUP BY 1
ORDER BY MIN(nearest_lte_distance);


-- -----------------------------------------------------------------------------
-- TABLE: Top Priority Schools
-- Chart type: Table
-- -----------------------------------------------------------------------------
SELECT
    giga_id_school AS "School ID",
    education_level AS "Level",
    ROUND(latitude::numeric, 4) AS "Lat",
    ROUND(longitude::numeric, 4) AS "Lon",
    electricity_availability AS "Electricity",
    ROUND(fiber_node_distance::numeric, 2) AS "Fiber Dist (km)",
    ROUND(nearest_lte_distance::numeric, 2) AS "LTE Dist (km)"
FROM school
WHERE NOT fourg AND NOT threeg AND NOT twog
ORDER BY fiber_node_distance ASC
LIMIT 25;


-- -----------------------------------------------------------------------------
-- TABLE: Infrastructure Summary
-- Chart type: Table
-- -----------------------------------------------------------------------------
SELECT
    'Total Schools' AS metric,
    COUNT(*)::text AS value
FROM school
UNION ALL
SELECT
    'Schools with 4G',
    COUNT(*)::text
FROM school WHERE fourg
UNION ALL
SELECT
    'Schools without coverage',
    COUNT(*)::text
FROM school WHERE NOT fourg AND NOT threeg AND NOT twog
UNION ALL
SELECT
    'Total Cell Towers',
    COUNT(*)::text
FROM celltower
UNION ALL
SELECT
    'LTE Towers',
    COUNT(*)::text
FROM celltower WHERE radio_type = 'LTE';


-- -----------------------------------------------------------------------------
-- HEATMAP DATA: School Density
-- Chart type: deck.gl Heatmap
-- -----------------------------------------------------------------------------
SELECT
    latitude,
    longitude,
    CASE
        WHEN fourg THEN 3
        WHEN threeg THEN 2
        WHEN twog THEN 1
        ELSE 0
    END AS connectivity_score
FROM school
WHERE latitude IS NOT NULL AND longitude IS NOT NULL;
