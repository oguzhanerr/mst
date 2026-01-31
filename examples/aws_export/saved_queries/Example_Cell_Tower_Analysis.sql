-- Example: Cell Tower Analysis
-- Description: MST example query from celltower_analysis.sql

-- =============================================================================
-- Cell Tower Analysis Queries for Giga MST
-- Database: mst (PostGIS)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Tower Count by Radio Type
-- Overview of network infrastructure
-- -----------------------------------------------------------------------------
SELECT
    radio_type,
    COUNT(*) AS tower_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) AS percentage
FROM celltower
GROUP BY radio_type
ORDER BY tower_count DESC;


-- -----------------------------------------------------------------------------
-- 2. Tower Distribution Summary
-- Geographic spread of towers
-- -----------------------------------------------------------------------------
SELECT
    radio_type,
    COUNT(*) AS count,
    ROUND(MIN(lat)::numeric, 4) AS min_lat,
    ROUND(MAX(lat)::numeric, 4) AS max_lat,
    ROUND(MIN(lon)::numeric, 4) AS min_lon,
    ROUND(MAX(lon)::numeric, 4) AS max_lon,
    ROUND(AVG(lat)::numeric, 4) AS center_lat,
    ROUND(AVG(lon)::numeric, 4) AS center_lon
FROM celltower
GROUP BY radio_type;


-- -----------------------------------------------------------------------------
-- 3. Towers for Map Visualization
-- Use with Superset deck.gl Scatter Plot
-- -----------------------------------------------------------------------------
SELECT
    fid,
    lat AS latitude,
    lon AS longitude,
    radio_type,
    CASE radio_type
        WHEN 'LTE' THEN '#4CAF50'      -- Green for 4G
        WHEN 'UMTS' THEN '#2196F3'     -- Blue for 3G
        WHEN 'GSM' THEN '#FF9800'      -- Orange for 2G
        ELSE '#9E9E9E'                  -- Gray for unknown
    END AS color
FROM celltower
WHERE lat IS NOT NULL AND lon IS NOT NULL;


-- -----------------------------------------------------------------------------
-- 4. LTE Tower Density Analysis
-- Find areas with high/low 4G coverage
-- -----------------------------------------------------------------------------
SELECT
    ROUND(lat::numeric, 1) AS lat_grid,
    ROUND(lon::numeric, 1) AS lon_grid,
    COUNT(*) FILTER (WHERE radio_type = 'LTE') AS lte_towers,
    COUNT(*) FILTER (WHERE radio_type = 'UMTS') AS umts_towers,
    COUNT(*) FILTER (WHERE radio_type = 'GSM') AS gsm_towers,
    COUNT(*) AS total_towers
FROM celltower
GROUP BY ROUND(lat::numeric, 1), ROUND(lon::numeric, 1)
ORDER BY lte_towers DESC;


-- -----------------------------------------------------------------------------
-- 5. Schools Near Each Tower Type
-- Understanding tower reach
-- -----------------------------------------------------------------------------
WITH tower_school_distance AS (
    SELECT
        c.fid AS tower_id,
        c.radio_type,
        c.lat AS tower_lat,
        c.lon AS tower_lon,
        s.giga_id_school,
        s.latitude AS school_lat,
        s.longitude AS school_lon,
        -- Haversine distance approximation (km)
        6371 * ACOS(
            COS(RADIANS(c.lat)) * COS(RADIANS(s.latitude)) *
            COS(RADIANS(s.longitude) - RADIANS(c.lon)) +
            SIN(RADIANS(c.lat)) * SIN(RADIANS(s.latitude))
        ) AS distance_km
    FROM celltower c
    CROSS JOIN school s
    WHERE s.latitude IS NOT NULL AND s.longitude IS NOT NULL
)
SELECT
    radio_type,
    COUNT(DISTINCT tower_id) AS towers,
    COUNT(DISTINCT CASE WHEN distance_km < 2 THEN giga_id_school END) AS schools_within_2km,
    COUNT(DISTINCT CASE WHEN distance_km < 5 THEN giga_id_school END) AS schools_within_5km,
    COUNT(DISTINCT CASE WHEN distance_km < 10 THEN giga_id_school END) AS schools_within_10km
FROM tower_school_distance
GROUP BY radio_type
ORDER BY towers DESC;


-- -----------------------------------------------------------------------------
-- 6. Coverage Gap Areas
-- Grid cells with schools but no nearby LTE towers
-- -----------------------------------------------------------------------------
WITH school_grid AS (
    SELECT
        ROUND(latitude::numeric, 2) AS lat_grid,
        ROUND(longitude::numeric, 2) AS lon_grid,
        COUNT(*) AS school_count
    FROM school
    WHERE latitude IS NOT NULL AND longitude IS NOT NULL
    GROUP BY 1, 2
),
tower_grid AS (
    SELECT
        ROUND(lat::numeric, 2) AS lat_grid,
        ROUND(lon::numeric, 2) AS lon_grid,
        COUNT(*) FILTER (WHERE radio_type = 'LTE') AS lte_count
    FROM celltower
    GROUP BY 1, 2
)
SELECT
    sg.lat_grid,
    sg.lon_grid,
    sg.school_count,
    COALESCE(tg.lte_count, 0) AS nearby_lte_towers
FROM school_grid sg
LEFT JOIN tower_grid tg ON sg.lat_grid = tg.lat_grid AND sg.lon_grid = tg.lon_grid
WHERE COALESCE(tg.lte_count, 0) = 0
ORDER BY sg.school_count DESC
LIMIT 50;


-- -----------------------------------------------------------------------------
-- 7. Recommended New Tower Locations
-- Areas with most unconnected schools
-- -----------------------------------------------------------------------------
SELECT
    ROUND(latitude::numeric, 2) AS suggested_lat,
    ROUND(longitude::numeric, 2) AS suggested_lon,
    COUNT(*) AS unconnected_schools,
    ROUND(AVG(nearest_lte_distance)::numeric, 2) AS avg_distance_to_lte,
    STRING_AGG(DISTINCT education_level, ', ') AS school_types
FROM school
WHERE NOT fourg
  AND latitude IS NOT NULL
  AND longitude IS NOT NULL
GROUP BY ROUND(latitude::numeric, 2), ROUND(longitude::numeric, 2)
HAVING COUNT(*) >= 3
ORDER BY unconnected_schools DESC
LIMIT 20;
