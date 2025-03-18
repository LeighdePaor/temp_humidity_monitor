# Temperature and Humidity Monitor

This project monitors temperature and humidity using a DHT22 sensor connected to a Raspberry Pi. It logs data locally to an SQLite database, sends it to ThingsBoard for cloud storage, and provides a Flask-based web interface to view the latest readings and a plot of recent data. The system runs as two systemd services: one for sensor monitoring and one for the web server.

## Features

* Sensor: Reads temperature and humidity from a DHT22 sensor on GPIO 22.
* Local Storage: Stores readings in temp_humidity.db (SQLite).
* Cloud Telemetry: Sends data to ThingsBoard (demo server).
* Web Interface: Flask app displays the latest reading and a plot (default: last hour), served via Gunicorn.
* Deployment: Runs as systemd services on a Raspberry Pi 2B.

## Prerequisites

* Hardware:
  * Raspberry Pi 2 Model B (or compatible).
  * Waveshare DHT22 sensor (or equivalent DHT22/AM2302).
  * Jumper wires (and optionally a 10kΩ resistor if no built-in pull-up).
* Software:
  * Raspberry Pi OS (tested with Buster or later).
  * Python 3.7+.
  * Git, SQLite, and required Python packages (see below).

## Setup

### Hardware Wiring

Connect the DHT22 to the Raspberry Pi 2B:

* VCC: Pi Pin 1 (3.3V).
* DATA: Pi Pin 15 (GPIO 22), with a 10kΩ pull-up resistor to 3.3V (if not built into the module).
* GND: Pi Pin 6 (GND).

### Installation

1; Clone the Repository:

```bash
git clone https://github.com/yourusername/temp_humidity_monitor.git
cd temp_humidity_monitor
```

Replace yourusername with your GitHub username if hosted there.

2; Install Dependencies

* Update the package list and install required packages:

```bash
sudo apt update
sudo apt install python3-pip python3-dev sqlite3 -y
```

* Install necessary Python packages:

```bash
sudo pip3 install adafruit-circuitpython-dht tb-device-mqtt flask matplotlib gunicorn
```

3; Configure the Project:

* Create config.json in ~/temp_humidity_monitor:

```json
{
    "access_token": "YOUR_THINGSBOARD_ACCESS_TOKEN",
    "gpio_pin": 22
}
```

* Replace YOUR_THINGSBOARD_ACCESS_TOKEN with your ThingsBoard device access token (from demo.thingsboard.io).

4; Set Up SQLite Database:

* The database (temp_humidity.db) is created automatically on first run.

### Systemd Services

Deploy as background services:

1; Sensor Service:

```bash
sudo nano /etc/systemd/system/temp_monitor_sensor.service
```

Paste:

```ini
[Unit]
Description=Temperature and Humidity Monitor Sensor
After=network.target

[Service]
User=pi
WorkingDirectory=/home/pi/temp_humidity_monitor
ExecStart=/usr/bin/python3 /home/pi/temp_humidity_monitor/monitor.py
Restart=always
StandardOutput=inherit
StandardError=inherit

[Install]
WantedBy=multi-user.target
```

Adjust User and paths if not using pi or /home/pi.

2; Web Service:

```bash
sudo nano /etc/systemd/system/temp_monitor_web.service
```

Paste:

```ini

[Unit]
Description=Temperature and Humidity Monitor Web (Gunicorn)
After=network.target

[Service]
User=pi
Group=www-data
WorkingDirectory=/home/pi/temp_humidity_monitor
ExecStart=/home/pi/.local/bin/gunicorn --workers 2 --bind 0.0.0.0:5000 app:app
Restart=always

[Install]
WantedBy=multi-user.target
```

Adjust paths if Gunicorn is installed elsewhere (check with which gunicorn).

3; Enable and Start Services:

```bash
sudo systemctl daemon-reload
sudo systemctl enable temp_monitor_sensor.service
sudo systemctl enable temp_monitor_web.service
sudo systemctl start temp_monitor_sensor.service
sudo systemctl start temp_monitor_web.service
```

### Usage

* Monitor Sensor:
  * The monitor.py script runs continuously, logging data every 5 minutes.
  * Check status:

```bash
sudo systemctl status temp_monitor_sensor.service
```

* Web Interface:
  * Access at http://<raspberry_pi_ip>:5000 (e.g., <http://192.168.1.100:5000>).
  * Displays:
    * Latest temperature and humidity reading.
    * Plot of the last hour’s data (default).
    * Option to select a custom time range for the plot.
* ThingsBoard:
  * View telemetry on demo.thingsboard.io using your device’s dashboard.

### Files

* monitor.py: Sensor reading and data storage script.
* app.py: Flask web server script.
* config.json: Configuration file (ignored by Git).
* temp_humidity.db: SQLite database (ignored by Git).
* static/plot.png: Generated plot file (ignored by Git).
* .gitignore: Excludes sensitive and temporary files.

### Troubleshooting

* Sensor Issues:
  * Verify DHT22 wiring and pull-up resistor.
  * Check monitor.py logs (sudo journalctl -u temp_monitor_sensor.service).
* Web Access:
  * Ensure Gunicorn is running (sudo systemctl status temp_monitor_web.service).
  * Check firewall if inaccessible (sudo ufw status).
* ThingsBoard:
  * Confirm access_token in config.json matches your device.

## Contributing

Feel free to fork this repo, submit issues, or send pull requests to improve the project!

## License

This project is unlicensed—use it as you see fit!

## Notes

* Paths: I assumed /home/pi —replace with /home/user if that’s your user.
* Customization: Add sections like “Hardware Notes” or “Future Improvements” if you plan to expand.
