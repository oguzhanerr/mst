FROM postgis/postgis:16-3.4

# Copy database initialization files
COPY rwa_celltower.csv /docker-entrypoint-initdb.d/rwa_celltower.csv
COPY rwa_school.csv /docker-entrypoint-initdb.d/rwa_school.csv
COPY coverage.csv /docker-entrypoint-initdb.d/coverage.csv
COPY init.sql /docker-entrypoint-initdb.d/init.sql
