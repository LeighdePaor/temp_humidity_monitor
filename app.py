#!/usr/bin/env python3

import sqlite3
import json
import sys
from datetime import datetime, timedelta
from pathlib import Path
from flask import Flask, render_template, request, jsonify, abort

BASE_DIR = Path(__file__).parent
CONFIG_FILE = BASE_DIR / 'config.json'
DB_FILE = BASE_DIR / 'temp_humidity.db'


def load_config():
    try:
        with open(CONFIG_FILE) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"Config error: {e}", file=sys.stderr)
        sys.exit(1)


config = load_config()
MONITOR_NAME = config.get('monitor_name', 'Monitor')

app = Flask(__name__, template_folder='templates')


def get_db():
    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row
    return conn


@app.route('/')
def index():
    with get_db() as conn:
        row = conn.execute(
            "SELECT timestamp, temperature, humidity FROM readings ORDER BY timestamp DESC LIMIT 1"
        ).fetchone()
    latest = dict(row) if row else None
    return render_template('index.html', monitor_name=MONITOR_NAME, latest=latest)


@app.route('/api/readings')
def api_readings():
    """Return JSON readings.

    Supports either:
    - `hours=<int>`: last N hours based on the Raspberry Pi system clock
    - `start`/`end`: ISO 8601 range

    Defaults to last 24 hours. Maximum range is 366 days.
    """
    max_seconds = 366 * 86400
    hours_param = request.args.get('hours')

    if hours_param is not None:
        try:
            hours = int(hours_param)
        except ValueError:
            abort(400, description="Invalid hours value. Use a positive integer.")

        if hours <= 0:
            abort(400, description="Hours must be greater than zero.")

        if hours * 3600 > max_seconds:
            abort(400, description="Date range must not exceed 366 days.")

        end_dt = datetime.now()
        start_dt = end_dt - timedelta(hours=hours)
    else:
        try:
            now = datetime.now()
            end_dt = datetime.fromisoformat(
                request.args.get('end', now.strftime('%Y-%m-%dT%H:%M:%S'))
            )
            start_dt = datetime.fromisoformat(
                request.args.get('start', (end_dt - timedelta(hours=24)).strftime('%Y-%m-%dT%H:%M:%S'))
            )
        except ValueError:
            abort(400, description="Invalid date format. Use ISO 8601 (e.g. 2026-04-20T10:00:00).")

        if (end_dt - start_dt).total_seconds() > max_seconds:
            abort(400, description="Date range must not exceed 366 days.")

    start_str = start_dt.strftime('%Y-%m-%d %H:%M:%S')
    end_str = end_dt.strftime('%Y-%m-%d %H:%M:%S')

    with get_db() as conn:
        rows = conn.execute(
            "SELECT timestamp, temperature, humidity FROM readings "
            "WHERE timestamp BETWEEN ? AND ? ORDER BY timestamp",
            (start_str, end_str),
        ).fetchall()

    return jsonify([dict(r) for r in rows])


@app.route('/api/latest')
def api_latest():
    """Return the most recent reading as JSON."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT timestamp, temperature, humidity FROM readings ORDER BY timestamp DESC LIMIT 1"
        ).fetchone()
    return jsonify(dict(row) if row else None)


if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000, debug=False)
