-- =============================================================================
-- School Connectivity Analysis Queries for Giga MST
-- Database: mst (PostGIS)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. School Connectivity Overview
-- Summary statistics for all schools
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*) AS total_schools,
    SUM(CASE WHEN fourG THEN 1 ELSE 0 END) AS schools_with_4g,
    SUM(CASE WHEN threeG THEN 1 ELSE 0 END) AS schools_with_3g,
    SUM(CASE WHEN twoG THEN 1 ELSE 0 END) AS schools_with_2g,
    SUM(CASE WHEN NOT fourG AND NOT threeG AND NOT twoG THEN 1 ELSE 0 END) AS no_coverage,
    ROUND(100.0 * SUM(CASE WHEN fourG THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_4g_coverage
FROM school;


-- -----------------------------------------------------------------------------
-- 2. Coverage by Education Level
-- Breakdown of connectivity by school type
-- -----------------------------------------------------------------------------
SELECT
    education_level,
    COUNT(*) AS school_count,
    SUM(CASE WHEN fourG THEN 1 ELSE 0 END) AS with_4g,
    SUM(CASE WHEN threeG AND NOT fourG THEN 1 ELSE 0 END) AS with_3g_only,
    SUM(CASE WHEN twoG AND NOT threeG AND NOT fourG THEN 1 ELSE 0 END) AS with_2g_only,
    SUM(CASE WHEN NOT fourG AND NOT threeG AND NOT twoG THEN 1 ELSE 0 END) AS no_coverage,
    ROUND(100.0 * SUM(CASE WHEN fourG THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_4g
FROM school
GROUP BY education_level
ORDER BY school_count DESC;


-- -----------------------------------------------------------------------------
-- 3. Schools Without Any Coverage (Connectivity Gap)
-- Priority targets for infrastructure investment
-- -----------------------------------------------------------------------------
SELECT
    giga_id_school,
    education_level,
    latitude,
    longitude,
    electricity_availability,
    nearest_LTE_distance,
    nearest_UMTS_distance,
    nearest_GSM_distance,
    fiber_node_distance
FROM school
WHERE NOT fourG AND NOT threeG AND NOT twoG
ORDER BY fiber_node_distance ASC
LIMIT 100;


-- -----------------------------------------------------------------------------
-- 4. Schools Close to Fiber but Without 4G
-- Quick wins - schools that could easily get connected
-- -----------------------------------------------------------------------------
SELECT
    giga_id_school,
    education_level,
    latitude,
    longitude,
    fiber_node_distance,
    nearest_LTE_distance,
    electricity_availability
FROM school
WHERE NOT fourG
  AND fiber_node_distance < 5  -- Within 5km of fiber
ORDER BY fiber_node_distance ASC;


-- -----------------------------------------------------------------------------
-- 5. Electricity and Internet Correlation
-- Understanding infrastructure dependencies
-- -----------------------------------------------------------------------------
SELECT
    electricity_availability,
    internet_availability,
    COUNT(*) AS school_count,
    SUM(CASE WHEN fourG THEN 1 ELSE 0 END) AS with_4g,
    ROUND(100.0 * SUM(CASE WHEN fourG THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_4g
FROM school
GROUP BY electricity_availability, internet_availability
ORDER BY school_count DESC;


-- -----------------------------------------------------------------------------
-- 6. Distance to Nearest Tower Analysis
-- Understanding coverage gaps
-- -----------------------------------------------------------------------------
SELECT
    CASE
        WHEN nearest_LTE_distance < 1 THEN '< 1 km'
        WHEN nearest_LTE_distance < 5 THEN '1-5 km'
        WHEN nearest_LTE_distance < 10 THEN '5-10 km'
        WHEN nearest_LTE_distance < 20 THEN '10-20 km'
        ELSE '> 20 km'
    END AS distance_to_lte,
    COUNT(*) AS school_count,
    SUM(CASE WHEN fourG THEN 1 ELSE 0 END) AS with_4g_coverage,
    ROUND(100.0 * SUM(CASE WHEN fourG THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_covered
FROM school
GROUP BY 1
ORDER BY 
    CASE
        WHEN nearest_LTE_distance < 1 THEN 1
        WHEN nearest_LTE_distance < 5 THEN 2
        WHEN nearest_LTE_distance < 10 THEN 3
        WHEN nearest_LTE_distance < 20 THEN 4
        ELSE 5
    END;


-- -----------------------------------------------------------------------------
-- 7. Schools for Map Visualization (GeoJSON ready)
-- Use with Superset deck.gl Scatter Plot
-- -----------------------------------------------------------------------------
SELECT
    giga_id_school,
    latitude,
    longitude,
    education_level,
    CASE
        WHEN fourG THEN '4G'
        WHEN threeG THEN '3G'
        WHEN twoG THEN '2G'
        ELSE 'No Coverage'
    END AS coverage_type,
    electricity_availability,
    fiber_node_distance
FROM school
WHERE latitude IS NOT NULL AND longitude IS NOT NULL;


-- -----------------------------------------------------------------------------
-- 8. Connectivity Improvement Potential
-- Schools that would benefit most from new infrastructure
-- -----------------------------------------------------------------------------
SELECT
    giga_id_school,
    education_level,
    latitude,
    longitude,
    CASE
        WHEN NOT fourG AND NOT threeG AND NOT twoG THEN 'Critical - No Coverage'
        WHEN NOT fourG AND NOT threeG THEN 'High - 2G Only'
        WHEN NOT fourG THEN 'Medium - 3G Only'
        ELSE 'Low - Has 4G'
    END AS upgrade_priority,
    nearest_LTE_distance,
    fiber_node_distance,
    electricity_availability
FROM school
ORDER BY
    CASE
        WHEN NOT fourG AND NOT threeG AND NOT twoG THEN 1
        WHEN NOT fourG AND NOT threeG THEN 2
        WHEN NOT fourG THEN 3
        ELSE 4
    END,
    fiber_node_distance ASC;
