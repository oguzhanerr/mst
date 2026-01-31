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
# Local docker-compose uses SUPERSET_META_* vars; AWS uses DATABASE_* vars.
# Provide safe defaults so we never generate an invalid SQLAlchemy URL like ":None/".
_META_USER = os.getenv("SUPERSET_META_USER") or os.getenv("DATABASE_USER") or "superset"
_META_PASS = os.getenv("SUPERSET_META_PASS") or os.getenv("DATABASE_PASSWORD") or "superset"
_META_HOST = os.getenv("SUPERSET_META_HOST") or os.getenv("DATABASE_HOST") or "metadata_db"
_META_PORT = os.getenv("SUPERSET_META_PORT") or os.getenv("DATABASE_PORT") or "5432"
SQLALCHEMY_DATABASE_URI = f"postgresql://{_META_USER}:{_META_PASS}@{_META_HOST}:{_META_PORT}/superset"

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
# Top-left navbar logo
APP_ICON = "/static/assets/images/custom_logos/logo.svg"
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
    # In AWS/ECS we pass REDIS_HOST/REDIS_PORT; avoid defaulting to redis:6379.
    _redis_host = os.getenv("REDIS_HOST", "redis")
    _redis_port = os.getenv("REDIS_PORT", "6379")
    broker_url = os.getenv("CELERY_BROKER_URL") or f"redis://{_redis_host}:{_redis_port}/0"
    imports = ("superset.sql_lab", "superset.tasks")
    result_backend = os.getenv("CELERY_RESULT_BACKEND") or f"redis://{_redis_host}:{_redis_port}/1"
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
# Used by Alerts & Reports and by dashboard download (PDF/image) features.
# In AWS/ECS the celery containers must reach Superset via the ALB URL (not docker-compose hostnames).
WEBDRIVER_TYPE = "firefox"
_WEBDRIVER_BASEURL = (
    os.getenv("WEBDRIVER_BASEURL")
    or os.getenv("SUPERSET_PUBLIC_URL")
    or "http://superset_app:8088"  # docker-compose default
)
WEBDRIVER_BASEURL = _WEBDRIVER_BASEURL
WEBDRIVER_BASEURL_USER_FRIENDLY = (
    os.getenv("WEBDRIVER_BASEURL_USER_FRIENDLY")
    or os.getenv("SUPERSET_PUBLIC_URL")
    or "http://localhost:8088"
)

# Public URL for links in emails and external access
SUPERSET_WEBSERVER_PROTOCOL = os.getenv("SUPERSET_WEBSERVER_PROTOCOL", "http")

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
# In docker-compose we can reach Redis at hostname "redis".
# In AWS/ECS we pass REDIS_HOST/REDIS_PORT (ElastiCache endpoint) and may not set REDIS_CACHE_URL.
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = str(os.getenv("REDIS_PORT", "6379"))
REDIS_CACHE_URL = os.getenv("REDIS_CACHE_URL") or f"redis://{REDIS_HOST}:{REDIS_PORT}/0"

# Celery URLs
CELERY_BROKER_URL = os.getenv("CELERY_BROKER_URL") or REDIS_CACHE_URL
CELERY_RESULT_BACKEND = os.getenv("CELERY_RESULT_BACKEND") or f"redis://{REDIS_HOST}:{REDIS_PORT}/1"

# Rate Limiting Storage (fixes flask_limiter in-memory warning)
RATELIMIT_STORAGE_URI = REDIS_CACHE_URL

# -----------------------------
# Sessions / CSRF
# -----------------------------
# On ECS behind an ALB, make sessions server-side so CSRF tokens don't disappear.
# Toggle cookie security when you move to HTTPS (set SESSION_COOKIE_SECURE=true).
import redis as _redis

ENABLE_PROXY_FIX = True
SESSION_SERVER_SIDE = True
SESSION_TYPE = "redis"
SESSION_REDIS = _redis.from_url(REDIS_CACHE_URL)
SESSION_KEY_PREFIX = "superset_session_"
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = os.getenv("SESSION_COOKIE_SAMESITE", "Lax")
SESSION_COOKIE_SECURE = os.getenv("SESSION_COOKIE_SECURE", "false").lower() == "true"

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

# Content Security Policy - allow unsafe-eval for JavaScript controls in charts
TALISMAN_ENABLED = True
# Flask-Talisman defaults to setting session cookies as Secure=True. That's correct for HTTPS,
# but it breaks logins on HTTP-only deployments because the browser won't send the cookie.
TALISMAN_CONFIG = {
    "content_security_policy": {
        "default-src": ["'self'"],
        "img-src": ["'self'", "data:", "blob:", "https:"],
        "worker-src": ["'self'", "blob:"],
        "connect-src": [
            "'self'",
            "https://api.mapbox.com",
            "https://events.mapbox.com",
        ],
        "object-src": "'none'",
        "style-src": ["'self'", "'unsafe-inline'"],
        "script-src": ["'self'", "'unsafe-inline'", "'unsafe-eval'"],
    },
    "content_security_policy_nonce_in": ["script-src"],
    "force_https": False,
    "session_cookie_secure": SESSION_COOKIE_SECURE,
    "session_cookie_http_only": True,
}
