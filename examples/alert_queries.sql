-- =============================================================================
-- Superset Alert Query Examples for Giga MST
-- These queries are designed to return a single value for alert conditions
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ALERT 1: Coverage Drop Alert
-- Trigger: When 4G coverage drops below threshold
-- Condition: result < 70 (less than 70% coverage)
-- -----------------------------------------------------------------------------
SELECT
    ROUND(100.0 * SUM(CASE WHEN fourG THEN 1 ELSE 0 END) / COUNT(*), 2) AS coverage_percentage
FROM school;


-- -----------------------------------------------------------------------------
-- ALERT 2: Uncovered Schools Threshold
-- Trigger: When too many schools have no coverage
-- Condition: result > 100 (more than 100 schools without coverage)
-- -----------------------------------------------------------------------------
SELECT COUNT(*) AS schools_without_coverage
FROM school
WHERE NOT fourG AND NOT threeG AND NOT twoG;


-- -----------------------------------------------------------------------------
-- ALERT 3: New Schools Without Coverage
-- Trigger: Daily check for schools needing attention
-- Condition: result > 0
-- Note: This assumes you have a created_at column (modify as needed)
-- -----------------------------------------------------------------------------
SELECT COUNT(*) AS new_uncovered_schools
FROM school
WHERE NOT fourG AND NOT threeG AND NOT twoG
  AND fiber_node_distance < 10;  -- Priority: close to fiber but uncovered


-- -----------------------------------------------------------------------------
-- ALERT 4: Tower Count Change
-- Trigger: If tower count changes unexpectedly
-- Condition: Compare with expected baseline
-- -----------------------------------------------------------------------------
SELECT COUNT(*) AS current_tower_count
FROM celltower;


-- -----------------------------------------------------------------------------
-- ALERT 5: LTE Tower Ratio
-- Trigger: When LTE towers fall below percentage of total
-- Condition: result < 30 (less than 30% LTE)
-- -----------------------------------------------------------------------------
SELECT
    ROUND(100.0 * COUNT(*) FILTER (WHERE radio_type = 'LTE') / COUNT(*), 2) AS lte_percentage
FROM celltower;


-- -----------------------------------------------------------------------------
-- ALERT 6: Average Distance to Coverage
-- Trigger: If average distance to LTE increases (infrastructure issue)
-- Condition: result > 15 (average > 15km to LTE)
-- -----------------------------------------------------------------------------
SELECT ROUND(AVG(nearest_LTE_distance)::numeric, 2) AS avg_lte_distance
FROM school
WHERE nearest_LTE_distance IS NOT NULL;


-- -----------------------------------------------------------------------------
-- ALERT 7: Schools Far from Fiber
-- Trigger: Count of schools very far from fiber infrastructure
-- Condition: result > 50
-- -----------------------------------------------------------------------------
SELECT COUNT(*) AS schools_far_from_fiber
FROM school
WHERE fiber_node_distance > 50  -- More than 50km from fiber
  AND NOT fourG;


-- -----------------------------------------------------------------------------
-- ALERT 8: Critical Schools Count
-- Trigger: Schools with no coverage AND no electricity
-- Condition: result > 0
-- -----------------------------------------------------------------------------
SELECT COUNT(*) AS critical_schools
FROM school
WHERE NOT fourG AND NOT threeG AND NOT twoG
  AND (electricity_availability IS NULL OR electricity_availability = 'No');


-- -----------------------------------------------------------------------------
-- REPORT QUERY: Weekly Coverage Summary
-- Use this for scheduled email reports
-- -----------------------------------------------------------------------------
SELECT
    'Total Schools' AS metric,
    COUNT(*)::text AS current_value,
    '-' AS change
FROM school
UNION ALL
SELECT
    '4G Coverage %',
    ROUND(100.0 * SUM(CASE WHEN fourG THEN 1 ELSE 0 END) / COUNT(*), 1)::text || '%',
    '-'
FROM school
UNION ALL
SELECT
    'Schools No Coverage',
    COUNT(*)::text,
    '-'
FROM school WHERE NOT fourG AND NOT threeG AND NOT twoG
UNION ALL
SELECT
    'Avg Distance to LTE',
    ROUND(AVG(nearest_LTE_distance)::numeric, 2)::text || ' km',
    '-'
FROM school
UNION ALL
SELECT
    'Total Towers',
    COUNT(*)::text,
    '-'
FROM celltower;
