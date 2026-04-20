import adafruit_dht
import board
import time
import json
from pathlib import Path

BASE_DIR = Path(__file__).parent


def load_config(config_file=BASE_DIR / 'config.json'):
    try:
        with open(config_file, 'r') as f:
            config = json.load(f)
        if 'gpio_pin' not in config:
            raise KeyError("Missing 'gpio_pin' in config")
        return config['gpio_pin']
    except (FileNotFoundError, KeyError, json.JSONDecodeError) as e:
        print(f"Config error: {e}")
        exit(1)


gpio_pin = load_config()
    
# Initialize DHT22
try:
    pin = getattr(board, f"D{gpio_pin}")
    dht_device = adafruit_dht.DHT22(pin, use_pulseio=False)
    print(f"DHT22 initialized on GPIO {gpio_pin}")
    for _ in range(10):
        try:
            print(f"Temp: {dht_device.temperature}°C, Humidity: {dht_device.humidity}%")
        except RuntimeError as e:
            print(f"Error: {e}")
        time.sleep(2)
except AttributeError:
    print(f"Error: Invalid GPIO pin {gpio_pin}. Use a valid GPIO number (e.g., 22 for D22).")
    exit(1)
