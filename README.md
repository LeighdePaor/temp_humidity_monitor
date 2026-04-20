# Temperature and Humidity Monitor

![Platform](https://img.shields.io/badge/platform-Raspberry%20Pi%203B%2B-C51A4A)
![Python](https://img.shields.io/badge/python-3.9%2B-3776AB)
![Web](https://img.shields.io/badge/web-Flask%20%2B%20Gunicorn-000000)
![TLS](https://img.shields.io/badge/TLS-Let%27s%20Encrypt-003A70)
![Storage](https://img.shields.io/badge/storage-SQLite-003B57)

A lightweight Raspberry Pi project that reads temperature and humidity from a DHT22 sensor, stores data in SQLite, and serves a secure HTTPS dashboard with interactive charts.

Built for reliable home or greenhouse monitoring with a simple two-service deployment model.

## Features

- DHT22 sensor polling on configurable GPIO
- Local SQLite time-series storage
- Interactive browser chart (Chart.js)
- Flask API + Gunicorn behind nginx
- HTTPS with Let\'s Encrypt and automatic renewal
- systemd-managed services for sensor and web layers

## Quickstart

> These steps assume you are running **PowerShell** on your local machine (Windows, macOS, or Linux).

### 0. Load sensitive values into your session

Copy `example.sensitive.json` to `sensitive.json` and fill in your values, then load them into PowerShell variables:

```powershell
$s = Get-Content .\sensitive.json | ConvertFrom-Json
$domain      = $s.domain
$appUser     = $s.app_user
$piIp        = $s.pi_ip_address
$tbHost      = $s.thingsboard_host
$accessToken = $s.access_token
```

All subsequent commands use these variables — you never type sensitive values by hand.

### 1. Copy this project to your Pi

```powershell
scp -r . "${appUser}@${piIp}:~/temp_humidity_monitor/"
```

### 2. SSH to the Pi and open the project

```powershell
ssh "${appUser}@${piIp}"
```

Once connected:

```bash
cd ~/temp_humidity_monitor
```

### 3. Install PowerShell on the Pi and set it as the default shell (Raspbian Trixie)

Run the following on the Pi over your SSH session:

```bash
# Install prerequisites
sudo apt-get update
sudo apt-get install -y curl apt-transport-https

# Add the Microsoft package repository
curl -sSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/microsoft.gpg
echo "deb [arch=arm64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/microsoft-debian-bookworm-prod bookworm main" \
    | sudo tee /etc/apt/sources.list.d/microsoft.list

# Install PowerShell
sudo apt-get update
sudo apt-get install -y powershell
```

Verify the install:

```bash
pwsh --version
```

Set PowerShell as the default shell for your user:

```bash
chsh -s $(which pwsh)
```

> Log out and back in for the shell change to take effect. Confirm with `echo $SHELL`.

### 4. Confirm deployment variables in `sensitive.json`

Fields required by `setup.sh`:

- `domain` — your public domain name
- `app_user` — the Pi Linux user account
- `pi_ip_address` — your Pi's local IP address

### 5. Load variables on the Pi (PowerShell)

Once PowerShell is your shell on the Pi, load sensitive values the same way:

```powershell
$s = Get-Content ~/temp_humidity_monitor/sensitive.json | ConvertFrom-Json
$env:DOMAIN       = $s.domain
$env:APP_USER     = $s.app_user
$env:PI_IP        = $s.pi_ip_address
```

To persist across sessions, add those lines to your PowerShell profile:

```powershell
Add-Content $PROFILE "`n`$s = Get-Content ~/temp_humidity_monitor/sensitive.json | ConvertFrom-Json"
Add-Content $PROFILE '`$env:DOMAIN = $s.domain; $env:APP_USER = $s.app_user'
```

### 6. Run the installer

```bash
sudo bash setup.sh
```

### 7. Open the dashboard

- [https://\<your-domain\>/]()

## Deployment Notes

setup.sh performs full server setup in one run:

- Installs system packages (Python, nginx, certbot, sqlite, libgpiod2)
- Creates a local virtual environment at .venv
- Installs Python dependencies (Flask, Gunicorn, adafruit-circuitpython-dht)
- Configures nginx reverse proxy to Gunicorn on 127.0.0.1:5000
- Requests and installs Let\'s Encrypt certificates
- Enables automatic certificate renewal (with dry-run test)
- Creates and enables two systemd services:
  - temp_monitor_sensor
  - temp_monitor_web

## Configuration

Example config.json:

```json
{
  "gpio_pin": 22,
  "monitor_name": "<Monitor Name>",
  "read_interval_seconds": 60
}
```

Fields:

- gpio_pin: BCM pin used by DHT22 data pin
- monitor_name: title shown in the dashboard
- read_interval_seconds: sensor polling interval

## Hardware Wiring

Typical DHT22 wiring on Raspberry Pi 3B+:

- VCC -> 3.3V (physical pin 1)
- DATA -> GPIO 22 (physical pin 15)
- GND -> GND (physical pin 6)

If your module does not include a pull-up resistor, add 10k between DATA and 3.3V.

## API Endpoints

- GET /api/latest
- `GET /api/readings?start={iso_datetime}&end={iso_datetime}`

## Operations

Service status:

```bash
sudo systemctl status temp_monitor_sensor
sudo systemctl status temp_monitor_web
sudo systemctl status nginx
```

Live logs:

```bash
sudo journalctl -u temp_monitor_sensor -f
sudo journalctl -u temp_monitor_web -f
```

Certificate renewal test:

```bash
sudo certbot renew --dry-run
```

## Troubleshooting

- Let\'s Encrypt fails:
  - Check DNS points to your public IP
  - Check router forwards ports 80 and 443 to the Pi
  - Ensure nginx is the only service binding port 80
- No sensor data:
  - Check wiring and gpio_pin value
  - Check sensor service logs
- Dashboard has no points:
  - Verify sensor service is running
  - Verify temp_humidity.db is being updated
  - Check /api/latest returns JSON

## Project Layout

- monitor.py: sensor read loop and database writes
- app.py: web routes and JSON API
- templates/index.html: browser dashboard
- config.json: runtime settings
- setup.sh: full deployment and HTTPS provisioning
