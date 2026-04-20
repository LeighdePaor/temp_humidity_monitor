#!/usr/bin/env bash
# =============================================================================
# setup.sh - Raspberry Pi 3B+ setup for temp_humidity_monitor
# Run as  : sudo bash setup.sh   (interactive, over SSH)
#
# Sensitive values (domain, app_user) are loaded from sensitive.json.
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
APP_DIR="/home/${APP_USER}/temp_humidity_monitor"
VENV_DIR="${APP_DIR}/.venv"

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
        git curl jq

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
    yellow "   You will be prompted for an email address."
    echo ""

    read -rp "Enter your email address for Let's Encrypt expiry notices: " CERT_EMAIL

    certbot --nginx \
        --non-interactive \
        --agree-tos \
        --redirect \
        --hsts \
        --domain "${DOMAIN}" \
        --email "${CERT_EMAIL}"

    green "==> Certificate obtained. Running renewal dry run..."
    certbot renew --dry-run
    green "    Auto-renewal dry run passed."
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
    cat > /etc/systemd/system/temp_monitor_web.service <<UNIT
[Unit]
Description=Temperature and Humidity Monitor Web (Gunicorn / Flask)
After=network.target

[Service]
User=${APP_USER}
Group=www-data
WorkingDirectory=${APP_DIR}
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
configure_nginx_http
obtain_cert
create_service_monitor
create_service_web
start_services
print_summary