#!/usr/bin/env python3

import sqlite3
from flask import Flask, render_template, request
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import os
import json
from datetime import datetime, timedelta  # Import for time calculations

app = Flask(__name__, template_folder='templates', static_folder='static')

MONITOR_NAME = "tunnel01"

def load_config(config_file='config.json'):
    try:
        with open(config_file, 'r') as f:
            config = json.load(f)
            if 'access_token' not in config or 'gpio_pin' not in config:
                raise KeyError("Missing 'access_token' or 'gpio_pin' in config")
            return config['access_token'], config['gpio_pin']
    except FileNotFoundError:
        print(f"Error: {config_file} not found. Please create it with your access token and GPIO pin.")
        exit(1)
    except KeyError as e:
        print(f"Error: {e}")
        exit(1)
    except json.JSONDecodeError:
        print(f"Error: Invalid JSON in {config_file}.")
        exit(1)

def get_latest_reading():
    conn = sqlite3.connect('temp_humidity.db')
    c = conn.cursor()
    c.execute("SELECT timestamp, temperature, humidity FROM readings ORDER BY timestamp DESC LIMIT 1")
    latest = c.fetchone()
    conn.close()
    if latest:
        return {"timestamp": latest[0], "temperature": latest[1], "humidity": latest[2]}
    return None

def generate_plot(start_date, end_date):
    conn = sqlite3.connect('temp_humidity.db')
    c = conn.cursor()
    c.execute("SELECT timestamp, temperature, humidity FROM readings WHERE timestamp BETWEEN ? AND ? ORDER BY timestamp", 
              (start_date, end_date))
    data = c.fetchall()
    conn.close()

    if not data:  # Handle case with no data
        return None

    timestamps = [d[0] for d in data]
    temps = [d[1] for d in data]
    hums = [d[2] for d in data]

    plt.figure(figsize=(10, 6))
    plt.plot(timestamps, temps, 'r-', label='Temperature (°C)')
    plt.plot(timestamps, hums, 'b-', label='Humidity (%)')
    plt.xlabel('Time')
    plt.legend()
    plt.xticks(rotation=45)
    plt.tight_layout()
    
    plot_path = 'static/plot.png'
    plt.savefig(plot_path)
    plt.close()
    return plot_path

@app.route('/', methods=['GET', 'POST'])
def index():
    latest_reading = get_latest_reading()
    
    # Default to last hour on initial load
    if request.method == 'GET':
        end_date = datetime.now()
        start_date = end_date - timedelta(hours=1)
        # Format dates to match database timestamp format
        start_date_str = start_date.strftime('%Y-%m-%d %H:%M:%S')
        end_date_str = end_date.strftime('%Y-%m-%d %H:%M:%S')
        plot_path = generate_plot(start_date_str, end_date_str)
    elif request.method == 'POST':
        start_date_str = request.form['start_date'].replace('T', ' ') + ':00'  # Convert HTML datetime-local to match DB
        end_date_str = request.form['end_date'].replace('T', ' ') + ':00'
        plot_path = generate_plot(start_date_str, end_date_str)
    
    return render_template('index.html', plot_url=plot_path, monitor_name=MONITOR_NAME, latest_reading=latest_reading)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)