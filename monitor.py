#!/usr/bin/env python3

import time
import sqlite3
import board  # pyright: ignore[reportMissingImports]
import adafruit_dht  # pyright: ignore[reportMissingImports]
import json
import logging
import sys
from datetime import datetime
from pathlib import Path
from typing import Any, Optional, Tuple

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger(__name__)

BASE_DIR = Path(__file__).parent
CONFIG_FILE = BASE_DIR / 'config.json'
DB_FILE = BASE_DIR / 'temp_humidity.db'


def load_config():
    try:
        with open(CONFIG_FILE) as f:
            config = json.load(f)
        if 'gpio_pin' not in config:
            raise KeyError("Missing 'gpio_pin' in config")
        return config
    except (FileNotFoundError, KeyError, json.JSONDecodeError) as e:
        logger.error(f"Config error: {e}")
        sys.exit(1)


def init_db():
    with sqlite3.connect(DB_FILE) as conn:
        conn.execute(
            '''CREATE TABLE IF NOT EXISTS readings (
                id        INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT    NOT NULL,
                temperature REAL  NOT NULL,
                humidity    REAL  NOT NULL
            )'''
        )
        conn.execute(
            'CREATE INDEX IF NOT EXISTS idx_timestamp ON readings(timestamp)'
        )
        conn.commit()


def store_reading(timestamp: str, temp: float, hum: float):
    with sqlite3.connect(DB_FILE) as conn:
        conn.execute(
            "INSERT INTO readings (timestamp, temperature, humidity) VALUES (?, ?, ?)",
            (timestamp, temp, hum),
        )
        conn.commit()


def read_sensor(dht_device: Any, max_attempts: int = 5) -> Tuple[Optional[float], Optional[float]]:
    for attempt in range(1, max_attempts + 1):
        try:
            temp = dht_device.temperature
            hum = dht_device.humidity
            if temp is not None and hum is not None and 0.0 <= hum <= 100.0:
                return temp, hum
            logger.warning(
                f"Attempt {attempt}: invalid reading temp={temp} hum={hum}, retrying..."
            )
        except RuntimeError as e:
            logger.warning(f"Attempt {attempt}: RuntimeError: {e}, retrying...")
        time.sleep(2)
    logger.error("All sensor read attempts failed")
    return None, None


def main():
    config = load_config()
    gpio_pin = config['gpio_pin']
    read_interval = config.get('read_interval_seconds', 60)

    try:
        pin: Any = getattr(board, f"D{gpio_pin}")
        dht_device: Any = adafruit_dht.DHT22(pin, use_pulseio=False)  # pyright: ignore[reportUnknownVariableType,reportUnknownMemberType]
        logger.info(f"DHT22 initialised on GPIO {gpio_pin}")
    except AttributeError:
        logger.error(
            f"Invalid GPIO pin {gpio_pin}. Use a valid BCM GPIO number (e.g. 22)."
        )
        sys.exit(1)

    init_db()
    logger.info(f"Database initialised. Reading every {read_interval}s.")

    while True:
        temp, hum = read_sensor(dht_device)
        if temp is not None and hum is not None:
            ts = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            store_reading(ts, temp, hum)
            logger.info(f"Stored: {ts}  temp={temp:.1f}°C  hum={hum:.1f}%")
        time.sleep(read_interval)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        logger.info("Shutting down...")