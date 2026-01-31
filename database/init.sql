CREATE TABLE IF NOT EXISTS celltower (
  fid VARCHAR(255) PRIMARY KEY,
  radio_type VARCHAR(255),
  lon DOUBLE PRECISION,
  lat DOUBLE PRECISION
);
TRUNCATE celltower;
\copy celltower FROM '/docker-entrypoint-initdb.d/rwa_celltower.csv' DELIMITER ',' CSV HEADER;

CREATE TABLE IF NOT EXISTS school (
  giga_id_school VARCHAR(255) PRIMARY KEY,
  education_level VARCHAR(255),
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  electricity_availability VARCHAR(255),
  internet_availability VARCHAR(255),
  connectivity_type VARCHAR(255),
  fiber_node_distance FLOAT,
  nearest_LTE_distance FLOAT,
  nearest_UMTS_distance FLOAT,
  nearest_GSM_distance FLOAT,
  twoG BOOLEAN,
  threeG BOOLEAN,
  fourG BOOLEAN
);
TRUNCATE school;
\copy school FROM '/docker-entrypoint-initdb.d/rwa_school.csv' DELIMITER ',' CSV HEADER;

CREATE TABLE IF NOT EXISTS coverage (
  WKT TEXT,
  fid VARCHAR(255) PRIMARY KEY,
  DN INT
);
TRUNCATE coverage;
\copy coverage FROM '/docker-entrypoint-initdb.d/coverage.csv' DELIMITER ',' CSV HEADER;

-- Enable PostGIS and create GeoJSON view for Superset visualization
CREATE EXTENSION IF NOT EXISTS postgis;

-- Create spatial index for faster queries
ALTER TABLE coverage ADD COLUMN IF NOT EXISTS geom geometry(Geometry, 4326);
UPDATE coverage SET geom = ST_Transform(ST_SetSRID(ST_GeomFromText(WKT), 3857), 4326) WHERE geom IS NULL;
CREATE INDEX IF NOT EXISTS idx_coverage_geom ON coverage USING GIST (geom);

-- Base GeoJSON view (geometry only)
CREATE OR REPLACE VIEW coverage_geojson AS
SELECT fid, DN, ST_AsGeoJSON(ST_Transform(ST_SetSRID(ST_GeomFromText(WKT), 3857), 4326)) AS geojson
FROM coverage;

-- GeoJSON Feature view for deck.gl visualization
CREATE OR REPLACE VIEW coverage_geojson_feature AS
SELECT
    fid,
    dn,
    json_build_object(
        'type', 'Feature',
        'properties', json_build_object('fid', fid, 'dn', dn),
        'geometry', ST_AsGeoJSON(geom)::json
    )::text AS geojson
FROM coverage;

-- Materialized view for faster rendering (pre-computed)
DROP MATERIALIZED VIEW IF EXISTS coverage_geojson_fast;
CREATE MATERIALIZED VIEW coverage_geojson_fast AS
SELECT
    fid,
    dn,
    json_build_object(
        'type', 'Feature',
        'properties', json_build_object('fid', fid, 'dn', dn),
        'geometry', ST_AsGeoJSON(geom)::json
    )::text AS geojson
FROM coverage;

-- Index on materialized view for faster lookups
CREATE INDEX IF NOT EXISTS idx_coverage_geojson_fast_fid ON coverage_geojson_fast (fid);

-- Analyze for query optimization
ANALYZE coverage_geojson_fast;

