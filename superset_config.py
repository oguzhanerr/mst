# Configuration file for Superset
import os

from cachelib.redis import RedisCache
from celery.schedules import crontab
from selenium.webdriver.firefox.options import Options as FirefoxOptions
from selenium.webdriver.firefox.service import Service as FirefoxService

# Secret key for session management
SECRET_KEY = os.getenv("SUPERSET_SECRET_KEY", "default_secret_key")

# Mapbox API key for map visualizations
MAPBOX_API_KEY = os.getenv("MAPBOX_API_KEY", "")

# Connection to metadata database
SQLALCHEMY_DATABASE_URI = f"postgresql://{os.getenv('SUPERSET_META_USER')}:{os.getenv('SUPERSET_META_PASS')}@metadata_db:{os.getenv('SUPERSET_META_PORT')}/superset"

FEATURE_FLAGS = {
    "HORIZONTAL_FILTER_BAR": True,
    "ENABLE_JAVASCRIPT_CONTROLS": True,
    "ALERT_REPORT_TABS": True,
    "ENABLE_DASHBOARD_DOWNLOAD_WEBDRIVER_SCREENSHOT": True,
    "DASHBOARD_NATIVE_FILTERS": True,
    "ALERT_REPORTS": True,
    "ENABLE_TEMPLATE_PROCESSING": True,
    "DRILL_BY": True,
}

####### Superset Customization ######
APP_ICON = "/static/assets/images/custom_logos/logo.png"
LOGO_TOOLTIP = "Navigates to the landing page"
FAVICONS = [{"href": "/static/assets/images/custom_logos/favicon.png"}]
APP_NAME = "Giga Mobile Simulation Tool"
# Custom color schemes
EXTRA_CATEGORICAL_COLOR_SCHEMES = [
    {
        "id": "CustomScheme",
        "label": "4G Coverage",
        "isDefault": False,
        "colors": [
            "#E04355",  # red
            "#5AC189",  # green
        ],
    },
    {
        "id": "CustomScheme2",
        "label": "Electricity",
        "isDefault": False,
        "colors": [
            "#5AC189",  # green
            "#E04355",  # red
        ],
    },]

# Celery Configuration
class CeleryConfig:
    # Basic Celery Configuration (using new Celery 6.x naming conventions)
    broker_url = os.getenv("CELERY_BROKER_URL", "redis://redis:6379/0")
    imports = ("superset.sql_lab", "superset.tasks")
    result_backend = os.getenv("CELERY_RESULT_BACKEND", "redis://redis:6379/1")
    TASK_ACKS_LATE = True
    TASK_ANNOTATIONS = {
        "sql_lab.get_sql_results": {
            "rate_limit": "100/s",
        }
    }

    # Celery Beat Configuration (using new Celery 6.x naming conventions)
    beat_schedule = {
        "reports.scheduler": {
            "task": "reports.scheduler",
            "schedule": crontab(minute="*", hour="*"),
        },
        "reports.prune_log": {
            "task": "reports.prune_log",
            "schedule": crontab(minute=10, hour=0),
        },
    }


CELERY_CONFIG = CeleryConfig

# Driver Settings
WEBDRIVER_TYPE = "firefox"
WEBDRIVER_BASEURL = "http://superset_app:8088"
WEBDRIVER_BASEURL_USER_FRIENDLY = "http://localhost:8088"

# Webdriver options
WEBDRIVER_OPTION_ARGS = [
    "--headless",
    "--width=1600",
    "--height=1200",
]

# Webdriver configuration for ARM64 compatibility
WEBDRIVER_CONFIGURATION = {
    "service": {
        "executable_path": "/usr/bin/geckodriver",
        "log_output": "/dev/null",
        "service_args": [],
    },
    "options": {
        "preferences": {
            "security.sandbox.content.level": 0,
        },
    },
}

# Email SMTP Configurations
SMTP_HOST = "smtp.gmail.com"  # change to your host
SMTP_PORT = 587  # your port, e.g. 587
SMTP_STARTTLS = True
SMTP_SSL_SERVER_AUTH = True  # If you're using an SMTP server with a valid certificate
SMTP_SSL = False
SMTP_USER = os.getenv("SMTP_USER")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD")
SMTP_MAIL_FROM = SMTP_USER
EMAIL_REPORTS_SUBJECT_PREFIX = (
    "[Superset] "  # optional - overwrites default value in config.py of "[Report] "
)


# Configuring Caching
REDIS_CACHE_URL = os.getenv("REDIS_CACHE_URL", "redis://redis:6379/0")
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = os.getenv("REDIS_PORT", 6379)

# Rate Limiting Storage (fixes flask_limiter in-memory warning)
RATELIMIT_STORAGE_URI = REDIS_CACHE_URL

# Cache Config
CACHE_CONFIG = {
    "CACHE_TYPE": "RedisCache",
    "CACHE_DEFAULT_TIMEOUT": 86400,  # 24 hours
    "CACHE_KEY_PREFIX": "superset_",
    "CACHE_REDIS_URL": REDIS_CACHE_URL,
}

# Data Query Cache
DATA_CACHE_CONFIG = {
    "CACHE_TYPE": "RedisCache",
    "CACHE_REDIS_URL": REDIS_CACHE_URL,
    "CACHE_DEFAULT_TIMEOUT": 86400,
    "CACHE_KEY_PREFIX": "superset_results_cache_",
}

# Dashboard Filter State Cache
FILTER_STATE_CACHE_CONFIG = {
    "CACHE_TYPE": "RedisCache",
    "CACHE_REDIS_URL": REDIS_CACHE_URL,
    "CACHE_DEFAULT_TIMEOUT": 86400,
    "CACHE_KEY_PREFIX": "superset_filter_cache_",
}

# Explore Form Data Cache
EXPLORE_FORM_DATA_CACHE_CONFIG = {
    "CACHE_TYPE": "RedisCache",
    "CACHE_REDIS_URL": REDIS_CACHE_URL,
    "CACHE_DEFAULT_TIMEOUT": 86400,
    "CACHE_KEY_PREFIX": "superset_explore_cache_",
}

RESULT_BACKEND = RedisCache(
    host=REDIS_HOST,
    port=REDIS_PORT,
    key_prefix="superset_results_backend_",
)

ALERT_REPORTS_NOTIFICATION_DRY_RUN = False
