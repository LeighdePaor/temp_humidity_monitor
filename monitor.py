#!/usr/bin/env python3

import time
import sqlite3
import board
import adafruit_dht
from datetime import datetime
from tb_device_mqtt import TBDeviceMqttClient
import json

def init_local_db():
    conn = sqlite3.connect('temp_humidity.db')
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS readings 
                 (timestamp TEXT, temperature REAL, humidity REAL)''')
    conn.commit()
    conn.close()

def load_config(config_file='config.json'):
    try:
        with open(config_file, 'r') as f:
            config = json.load(f)
            if 'access_token' not in config or 'gpio_pin' not in config:
                raise KeyError("Missing 'access_token' or 'gpio_pin' in config")
            return config['access_token'], config['gpio_pin']
    except (FileNotFoundError, KeyError, json.JSONDecodeError) as e:
        print(f"Config error: {e}")
        exit(1)

def store_local_data(timestamp, temp, hum):
    conn = sqlite3.connect('temp_humidity.db')
    c = conn.cursor()
    c.execute("INSERT INTO readings VALUES (?, ?, ?)", (timestamp, temp, hum))
    conn.commit()
    conn.close()

def store_cloud_data(client, temp, hum):
    try:
        if not client.is_connected():
            print("Connection lost, reconnecting to ThingsBoard...")
            client.connect()
        client.send_telemetry({"temperature": temp, "humidity": hum})
        print("Telemetry sent successfully")
    except Exception as e:
        print(f"Failed to send telemetry: {e}")

def read_sensor(dht_device):
    max_attempts = 5
    for attempt in range(max_attempts):
        try:
            temp = dht_device.temperature
            hum = dht_device.humidity
            print(f"Raw reading attempt {attempt + 1}: Temp={temp}°C, Humidity={hum}%")
            
            if temp is not None and hum is not None:
                if 0 <= hum <= 100 and hum != 99.9:
                    return temp, hum
                else:
                    print(f"Invalid humidity ({hum}%), retrying...")
            else:
                print("Null reading, retrying...")
            
            time.sleep(2)
        except RuntimeError as e:
            print(f"RuntimeError on attempt {attempt + 1}: {e}, retrying...")
            time.sleep(2)
    
    print("Failed to get valid reading after all attempts, returning None")
    return None, None

def main():
    access_token, gpio_pin = load_config()
    
    # Initialize DHT22
    try:
        pin = getattr(board, f"D{gpio_pin}")
        dht_device = adafruit_dht.DHT22(pin, use_pulseio=False)
        print(f"DHT22 initialized on GPIO {gpio_pin}")
    except AttributeError:
        print(f"Error: Invalid GPIO pin {gpio_pin}. Use a valid GPIO number (e.g., 22 for D22).")
        exit(1)
    
    # ThingsBoard setup
    THINGSBOARD_HOST = 'demo.thingsboard.io'
    client = TBDeviceMqttClient(host=THINGSBOARD_HOST, access_token=access_token, port=1883)
    client._client.username_pw_set(access_token)
    
    init_local_db()
    
    try:
        client.connect()
        print("Connected to ThingsBoard successfully!")
    except Exception as e:
        print(f"Initial connection failed: {e}")
        return
    
    while True:
        temp, hum = read_sensor(dht_device)
        if temp and hum:
            timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            store_local_data(timestamp, temp, hum)
            store_cloud_data(client, temp, hum)
            print(f"Temp: {temp}°C, Humidity: {hum}%")
        else:
            print("Skipping storage due to invalid sensor reading")
        time.sleep(300)

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print("Shutting down...")