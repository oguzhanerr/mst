-- Example: 4G Coverage Analysis
-- Description: MST example query from coverage_analysis.sql

-- =============================================================================
-- Coverage Polygon Analysis Queries for Giga MST
-- Database: mst (PostGIS)
-- Requires: PostGIS extension
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Coverage Summary Statistics
-- Overview of coverage polygons
-- -----------------------------------------------------------------------------
SELECT
    DN AS coverage_type,
    COUNT(*) AS polygon_count
FROM coverage
GROUP BY DN
ORDER BY DN;


-- -----------------------------------------------------------------------------
-- 2. Coverage GeoJSON for Map Visualization
-- Use with Superset deck.gl GeoJSON layer
-- -----------------------------------------------------------------------------
SELECT
    fid,
    DN AS coverage_level,
    geojson
FROM coverage_geojson
LIMIT 1000;


-- -----------------------------------------------------------------------------
-- 3. Total Coverage Area by Type
-- Requires PostGIS for area calculation
-- -----------------------------------------------------------------------------
SELECT
    DN AS coverage_type,
    COUNT(*) AS polygon_count,
    ROUND(SUM(ST_Area(ST_Transform(ST_SetSRID(ST_GeomFromText(WKT), 3857), 4326)::geography) / 1000000)::numeric, 2) AS total_area_sq_km
FROM coverage
GROUP BY DN
ORDER BY DN;


-- -----------------------------------------------------------------------------
-- 4. Schools Within Coverage Polygons
-- Spatial join to find covered schools
-- -----------------------------------------------------------------------------
SELECT
    c.DN AS coverage_type,
    COUNT(DISTINCT s.giga_id_school) AS schools_covered
FROM coverage c
JOIN school s ON ST_Contains(
    ST_Transform(ST_SetSRID(ST_GeomFromText(c.WKT), 3857), 4326),
    ST_SetSRID(ST_MakePoint(s.longitude, s.latitude), 4326)
)
WHERE s.latitude IS NOT NULL AND s.longitude IS NOT NULL
GROUP BY c.DN
ORDER BY c.DN;


-- -----------------------------------------------------------------------------
-- 5. Schools Outside All Coverage Areas
-- Identify completely uncovered schools
-- -----------------------------------------------------------------------------
SELECT
    s.giga_id_school,
    s.education_level,
    s.latitude,
    s.longitude,
    s.electricity_availability,
    s.fiber_node_distance
FROM school s
WHERE s.latitude IS NOT NULL
  AND s.longitude IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM coverage c
    WHERE ST_Contains(
        ST_Transform(ST_SetSRID(ST_GeomFromText(c.WKT), 3857), 4326),
        ST_SetSRID(ST_MakePoint(s.longitude, s.latitude), 4326)
    )
  )
ORDER BY s.fiber_node_distance ASC;


-- -----------------------------------------------------------------------------
-- 6. Coverage Overlap Analysis
-- Find areas with multiple coverage types
-- -----------------------------------------------------------------------------
WITH school_coverage AS (
    SELECT
        s.giga_id_school,
        s.latitude,
        s.longitude,
        ARRAY_AGG(DISTINCT c.DN ORDER BY c.DN) AS coverage_types,
        COUNT(DISTINCT c.DN) AS coverage_count
    FROM school s
    LEFT JOIN coverage c ON ST_Contains(
        ST_Transform(ST_SetSRID(ST_GeomFromText(c.WKT), 3857), 4326),
        ST_SetSRID(ST_MakePoint(s.longitude, s.latitude), 4326)
    )
    WHERE s.latitude IS NOT NULL AND s.longitude IS NOT NULL
    GROUP BY s.giga_id_school, s.latitude, s.longitude
)
SELECT
    coverage_count,
    COUNT(*) AS school_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) AS percentage
FROM school_coverage
GROUP BY coverage_count
ORDER BY coverage_count;


-- -----------------------------------------------------------------------------
-- 7. Coverage Boundary Points (for visualization)
-- Extract polygon vertices for lightweight mapping
-- -----------------------------------------------------------------------------
SELECT
    fid,
    DN AS coverage_type,
    ST_X(ST_Centroid(ST_Transform(ST_SetSRID(ST_GeomFromText(WKT), 3857), 4326))) AS center_lon,
    ST_Y(ST_Centroid(ST_Transform(ST_SetSRID(ST_GeomFromText(WKT), 3857), 4326))) AS center_lat
FROM coverage
LIMIT 500;
