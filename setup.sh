#!/bin/bash
#get base software installed for hosting the temperature & humidity monitor/plot
# Update system
sudo apt update && sudo apt upgrade -y

# Install Python and pip
sudo apt install python3 python3-pip -y

# Install DHT22 library
pip3 install adafruit-circuitpython-dht

# Install SQLite for local database
sudo apt install sqlite3 -y

# Install Flask for local web server
pip3 install flask

# Install ThingsBoard client for cloud database (free cloud IoT platform)
pip3 install tb-mqtt-client

# Install required plotting libraries
pip3 install matplotlib

# Install GPIO library
sudo apt install libgpiod2 -y

# Install gunicorn for running the flask app
pip3 install gunicorn

# Install papirus for e-ink display
sudo apt-get install python3-pil python3-smbus python3-dateutil -y
git clone --depth=1 https://github.com/PiSupply/PaPiRus.git
cd PaPiRus
sudo python3 setup.py install
sudo papirus-setup  # Follow prompts to configure your screen size (e.g., 2.0" or 2.7")

# Create directory structure
mkdir -p ~/temp_humidity_monitor/static ~/temp_humidity_monitor/templates

# run the following from the terminal
# chmod +x setup.sh
# sudo ./setup.sh

# Since we’ve split the app into two parts, create two systemd services:

# temp_monitor_web.service for the Flask app via Gunicorn.
# temp_monitor_sensor.service for the sensor monitoring.

# To set this up as a service on a Raspberry Pi, create a systemd unit file as follows:
# sudo nano /etc/systemd/system/temp_monitor_web.service
# [Unit]
# Description=Temperature and Humidity Monitor Web (Gunicorn)
# After=network.target
# [Service]
# User=pi
# Group=www-data
# WorkingDirectory=/home/<user_dir>/temp_humidity_monitor
# ExecStart=/home/<user_dir>/.local/bin/gunicorn --workers 2 --bind 0.0.0.0:5000 app:app
# Restart=always
# [Install]
# WantedBy=multi-user.target
#
# Save the file

# sudo nano /etc/systemd/system/temp_monitor_sensor.service
# [Unit]
# Description=Temperature and Humidity Monitor Sensor
# After=network.target
# [Service]
# User=pi
# WorkingDirectory=/home/<user_dir>/temp_humidity_monitor
# ExecStart=/usr/bin/python3 /home/<user_dir>/temp_humidity_monitor/monitor.py
# Restart=always
# StandardOutput=inherit
# StandardError=inherit
# [Install]
# WantedBy=multi-user.target

# Enable the services with the following commands:
# sudo systemctl enable temp_monitor_web.service
# sudo systemctl enable temp_monitor_sensor.service

# to restart the service:
# sudo systemctl daemon-reload
# sudo systemctl restart temp_monitor_web.service
# sudo systemctl status temp_monitor_web.service
# sudo systemctl restart temp_monitor_sensor.service
# sudo systemctl status temp_monitor_sensor.service