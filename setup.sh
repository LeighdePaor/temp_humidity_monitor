#!/usr/bin/env bash
# =============================================================================
# setup.sh - Raspberry Pi 3B+ setup for temp_humidity_monitor
# Run as  : sudo bash setup.sh   (interactive, over SSH)
#
# Sensitive values (domain, app_user, letsencrypt_email) are loaded from sensitive.json.
# Copy example.sensitive.json -> sensitive.json and fill in your values.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SENSITIVE_FILE="${SCRIPT_DIR}/sensitive.json"

if ! command -v jq &>/dev/null; then
    echo "jq is required to parse sensitive.json. Installing..."
    apt-get install -y jq
fi

if [[ ! -f "${SENSITIVE_FILE}" ]]; then
    echo "ERROR: ${SENSITIVE_FILE} not found."
    echo "Copy example.sensitive.json to sensitive.json and fill in your values."
    exit 1
fi

DOMAIN=$(jq -r '.domain' "${SENSITIVE_FILE}")
APP_USER=$(jq -r '.app_user' "${SENSITIVE_FILE}")
LETSENCRYPT_EMAIL=$(jq -r '.letsencrypt_email' "${SENSITIVE_FILE}")
APP_DIR="/home/${APP_USER}/temp_humidity_monitor"
VENV_DIR="${APP_DIR}/.venv"
TLS_STATUS="not-requested"

require_sensitive_value() {
    local key="$1"
    local value="$2"
    if [[ -z "${value}" || "${value}" == "null" ]]; then
        red "Missing '${key}' in ${SENSITIVE_FILE}"
        exit 1
    fi
}

require_sensitive_value "domain" "${DOMAIN}"
require_sensitive_value "app_user" "${APP_USER}"
require_sensitive_value "letsencrypt_email" "${LETSENCRYPT_EMAIL}"

if [[ "${LETSENCRYPT_EMAIL}" != *"@"* ]]; then
    red "Invalid letsencrypt_email in ${SENSITIVE_FILE}: ${LETSENCRYPT_EMAIL}"
    exit 1
fi

# ---------- colour helpers ---------------------------------------------------
green()  { echo -e "\033[32m$*\033[0m"; }
yellow() { echo -e "\033[33m$*\033[0m"; }
red()    { echo -e "\033[31m$*\033[0m"; }

require_root() {
    if [[ $EUID -ne 0 ]]; then
        red "This script must be run as root:  sudo bash setup.sh"
        exit 1
    fi
}

# =============================================================================
# 1. System packages
# =============================================================================
install_packages() {
    green "==> Updating package lists and upgrading system..."
    apt-get update -y
    apt-get upgrade -y

    green "==> Installing system dependencies..."
    apt-get install -y \
        python3 python3-pip python3-venv python3-dev \
        sqlite3 \
        libgpiod2 \
        nginx \
        certbot python3-certbot-nginx \
        git curl jq dnsutils

    pip3 cache purge 2>/dev/null || true
}

# =============================================================================
# 2. Application directory and Python virtual environment
# =============================================================================
setup_app() {
    green "==> Setting up application directory: ${APP_DIR}"
    mkdir -p "${APP_DIR}/templates"

    green "==> Creating Python virtual environment..."
    python3 -m venv "${VENV_DIR}"
    "${VENV_DIR}/bin/pip" install --upgrade pip

    green "==> Installing Python packages..."
    "${VENV_DIR}/bin/pip" install \
        flask \
        gunicorn \
        adafruit-circuitpython-dht

    chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}"
}

# =============================================================================
# 2.5 Preflight checks - fail fast on missing web runtime dependencies
# =============================================================================
preflight_web_runtime() {
    green "==> Running web runtime preflight checks..."

    if [[ ! -x "${VENV_DIR}/bin/gunicorn" ]]; then
        red "Missing Gunicorn executable: ${VENV_DIR}/bin/gunicorn"
        red "Run setup again or install it manually in the venv: ${VENV_DIR}/bin/pip install gunicorn"
        exit 1
    fi

    if ! "${VENV_DIR}/bin/python" -c "import flask, gunicorn" >/dev/null 2>&1; then
        red "Python dependency check failed in ${VENV_DIR}. Flask/Gunicorn import failed."
        red "Reinstall dependencies: ${VENV_DIR}/bin/pip install flask gunicorn adafruit-circuitpython-dht"
        exit 1
    fi

    green "    Preflight checks passed."
}

# =============================================================================
# 3. nginx - initial HTTP-only config (certbot will upgrade to HTTPS)
# =============================================================================
configure_nginx_http() {
    green "==> Writing initial nginx config (HTTP only)..."
    cat > /etc/nginx/sites-available/temp_monitor <<NGINX
server {
    listen 80;
    server_name ${DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        proxy_pass         http://127.0.0.1:5000;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_read_timeout 30s;
    }
}
NGINX

    ln -sf /etc/nginx/sites-available/temp_monitor \
            /etc/nginx/sites-enabled/temp_monitor
    rm -f /etc/nginx/sites-enabled/default

    nginx -t
    systemctl enable nginx
    systemctl reload nginx
}

# =============================================================================
# 4. Let's Encrypt certificate via certbot --nginx
#    certbot will:
#      - obtain the cert via HTTP-01 ACME challenge
#      - rewrite the nginx config to add TLS + HTTP->HTTPS redirect
#      - install a systemd timer for automatic 90-day renewal
# =============================================================================
obtain_cert() {
    green "==> Obtaining Let's Encrypt certificate for ${DOMAIN}..."
    yellow "   Using email from sensitive.json: ${LETSENCRYPT_EMAIL}"

    local a_records
    local aaaa_records
    a_records=$(dig +short A "${DOMAIN}" @1.1.1.1 | tr -d '\r' || true)
    aaaa_records=$(dig +short AAAA "${DOMAIN}" @1.1.1.1 | tr -d '\r' || true)

    if [[ -z "${a_records}" && -z "${aaaa_records}" ]]; then
        TLS_STATUS="skipped-dns-not-ready"
        red "No public DNS records found for ${DOMAIN} (A/AAAA lookup returned NXDOMAIN or empty)."
        yellow "Skipping certbot for now so setup can complete."
        yellow "Create DNS records for ${DOMAIN} and rerun:"
        yellow "  sudo certbot --nginx --non-interactive --agree-tos --redirect --hsts --domain ${DOMAIN} --email ${LETSENCRYPT_EMAIL}"
        return 0
    fi

    if certbot --nginx \
        --non-interactive \
        --agree-tos \
        --redirect \
        --hsts \
        --domain "${DOMAIN}" \
        --email "${LETSENCRYPT_EMAIL}"; then
        TLS_STATUS="enabled"
        green "==> Certificate obtained. Running renewal dry run..."
        if certbot renew --dry-run; then
            green "    Auto-renewal dry run passed."
        else
            yellow "    Renewal dry run failed. Check certbot logs."
        fi
    else
        TLS_STATUS="failed"
        red "Certbot failed. Continuing setup so services stay available over HTTP."
        yellow "Check: /var/log/letsencrypt/letsencrypt.log"
        yellow "Retry later with:"
        yellow "  sudo certbot --nginx --non-interactive --agree-tos --redirect --hsts --domain ${DOMAIN} --email ${LETSENCRYPT_EMAIL}"
    fi
}

# =============================================================================
# 5. systemd service - sensor monitor (DHT22 -> SQLite)
# =============================================================================
create_service_monitor() {
    green "==> Creating systemd service: temp_monitor_sensor"
    cat > /etc/systemd/system/temp_monitor_sensor.service <<UNIT
[Unit]
Description=Temperature and Humidity Sensor Monitor (DHT22 to SQLite)
After=network.target

[Service]
User=${APP_USER}
WorkingDirectory=${APP_DIR}
ExecStart=${VENV_DIR}/bin/python ${APP_DIR}/monitor.py
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=temp_monitor_sensor

[Install]
WantedBy=multi-user.target
UNIT
}

# =============================================================================
# 6. systemd service - web app (Gunicorn/Flask behind nginx)
# =============================================================================
create_service_web() {
    green "==> Creating systemd service: temp_monitor_web"

    # Remove legacy overrides/units so ExecStart is pinned to the venv every run.
    rm -rf /etc/systemd/system/temp_monitor_web.service.d
    rm -f /etc/systemd/system/temp_monitor_web.service

    cat > /etc/systemd/system/temp_monitor_web.service <<UNIT
[Unit]
Description=Temperature and Humidity Monitor Web (Gunicorn / Flask)
After=network.target

[Service]
User=${APP_USER}
Group=www-data
WorkingDirectory=${APP_DIR}
Environment=PATH=${VENV_DIR}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=${VENV_DIR}/bin/gunicorn \
    --workers 2 \
    --bind 127.0.0.1:5000 \
    --timeout 30 \
    --access-logfile - \
    app:app
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=temp_monitor_web

[Install]
WantedBy=multi-user.target
UNIT
}

# =============================================================================
# 7. Enable and start services
# =============================================================================
start_services() {
    green "==> Enabling and starting services..."
    systemctl daemon-reload

    # Verify the effective ExecStart still points to the venv gunicorn binary.
    WEB_EXECSTART=$(systemctl show temp_monitor_web -p ExecStart --value || true)
    if [[ "${WEB_EXECSTART}" != *"${VENV_DIR}/bin/gunicorn"* ]]; then
        red "temp_monitor_web ExecStart is not pinned to ${VENV_DIR}/bin/gunicorn"
        red "Resolved ExecStart: ${WEB_EXECSTART}"
        exit 1
    fi

    systemctl enable temp_monitor_sensor temp_monitor_web
    systemctl restart temp_monitor_sensor temp_monitor_web
    systemctl reload nginx
}

# =============================================================================
# 8. Summary
# =============================================================================
print_summary() {
    echo ""
    green "=================================================================="
    green " Setup complete!"
    green "=================================================================="
    echo ""
    echo "  Web interface : https://${DOMAIN}/"
    echo "  Sensor service: $(systemctl is-active temp_monitor_sensor)"
    echo "  Web service   : $(systemctl is-active temp_monitor_web)"
    echo "  nginx         : $(systemctl is-active nginx)"
    echo "  TLS status    : ${TLS_STATUS}"
    echo ""
    yellow "Certificate auto-renewal:"
    systemctl is-enabled certbot.timer 2>/dev/null \
        && echo "  certbot.timer is active (systemd)" \
        || echo "  /etc/cron.d/certbot (cron)"
    echo ""
    yellow "Useful commands:"
    echo "  sudo journalctl -u temp_monitor_sensor -f   # sensor logs"
    echo "  sudo journalctl -u temp_monitor_web -f      # web logs"
    echo "  sudo certbot renew --dry-run                # test cert renewal"
    echo "  sudo nginx -t && sudo systemctl reload nginx"
    echo ""
}

# =============================================================================
# Main
# =============================================================================
require_root
install_packages
setup_app
preflight_web_runtime
configure_nginx_http
obtain_cert
create_service_monitor
create_service_web
start_services
print_summary