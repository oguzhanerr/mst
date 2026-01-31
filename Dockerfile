FROM apache/superset

WORKDIR /app

USER root

RUN apt-get update && apt-get install -y \
    procps \
    nano \
    gcc \
    pkg-config \
    zip \
    apt-transport-https \
    && apt-get clean

RUN uv pip install --python /app/.venv/bin/python psycopg2-binary Pillow gevent

# Install Extra dependencies for Alerts & Reports
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    unzip \
    gnupg \
    ca-certificates 

# Install Firefox
RUN apt-get update && apt-get install -y --no-install-recommends firefox-esr \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Geckodriver for Firefox (supports both x86_64 and ARM64)
ENV GECKODRIVER_VERSION=0.35.0
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "aarch64" ]; then \
        GECKODRIVER_ARCH="linux-aarch64"; \
    else \
        GECKODRIVER_ARCH="linux64"; \
    fi && \
    wget -q https://github.com/mozilla/geckodriver/releases/download/v${GECKODRIVER_VERSION}/geckodriver-v${GECKODRIVER_VERSION}-${GECKODRIVER_ARCH}.tar.gz && \
    tar -x geckodriver -zf geckodriver-v${GECKODRIVER_VERSION}-${GECKODRIVER_ARCH}.tar.gz -O > /usr/bin/geckodriver && \
    chmod 755 /usr/bin/geckodriver && \
    rm geckodriver-v${GECKODRIVER_VERSION}-${GECKODRIVER_ARCH}.tar.gz

# Copy requirements and install Python dependencies
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt --upgrade pip

# Copy docker scripts to /docker and make them executable
COPY docker/superset-init.sh /docker/superset-init.sh
COPY docker/superset-entrypoint.sh /docker/superset-entrypoint.sh
COPY docker/superset-celery.sh /docker/superset-celery.sh

# Change permissions to make docker scripts executable
RUN chmod +x /docker/*.sh && \
    chown superset:superset /docker/*.sh

# Make superset user an owner of the superset_config.py
COPY --chown=superset superset_config.py /app/
ENV SUPERSET_CONFIG_PATH=/app/superset_config.py

# Bundle MST Superset assets (dashboards/charts/datasets) so init can import them on AWS
COPY --chown=superset examples/ /app/examples/

# Create a folder for custom logos
RUN mkdir -p /app/superset/static/assets/images/custom_logos/
# Copy custom images (corrected path)
COPY docker/src/img/ /app/superset/static/assets/images/custom_logos/

# Superset 6 navbar may still reference built-in logo assets directly.
# Override them so the top-left clickable logo shows MST branding.
# - superset-logo-horiz.png: main navbar brand logo
# - superset.png / s.png: smaller variants used in some layouts
COPY docker/src/img/logo.png /app/superset/static/assets/images/superset-logo-horiz.png
COPY docker/src/img/logo.png /app/superset/static/assets/images/superset.png
COPY docker/src/img/logo.png /app/superset/static/assets/images/s.png

# Create directory for Celery Beat schedule and assign permissions
RUN mkdir -p /app/celerybeat && \
    chown -R superset:superset /app/celerybeat

# Create cache directory for Selenium and assign to superset user
RUN mkdir -p /app/superset_home/.cache/selenium && \
    chown -R superset:superset /app/superset_home

USER superset

CMD ["/docker/superset-entrypoint.sh"]
