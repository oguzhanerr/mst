CREATE TABLE celltower (
  fid VARCHAR(255) PRIMARY KEY,
  radio_type VARCHAR(255),
  lon DOUBLE PRECISION,
  lat DOUBLE PRECISION
);
COPY celltower FROM '/docker-entrypoint-initdb.d/rwa_celltower.csv' DELIMITER ',' CSV HEADER;

CREATE TABLE school (
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

COPY school FROM '/docker-entrypoint-initdb.d/rwa_school.csv' DELIMITER ',' CSV HEADER;

CREATE TABLE coverage (
  WKT TEXT,
  fid VARCHAR(255) PRIMARY KEY,
  DN INT
);
COPY coverage FROM '/docker-entrypoint-initdb.d/coverage.csv' DELIMITER ',' CSV HEADER;

-- Enable PostGIS and create GeoJSON view for Superset visualization
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE VIEW coverage_geojson AS 
SELECT fid, DN, ST_AsGeoJSON(ST_Transform(ST_SetSRID(ST_GeomFromText(WKT), 3857), 4326)) AS geojson 
FROM coverage;

