from tb_device_mqtt import TBDeviceMqttClient
import json
from pathlib import Path

BASE_DIR = Path(__file__).parent


def load_sensitive(sensitive_file=BASE_DIR / 'sensitive.json'):
    try:
        with open(sensitive_file, 'r') as f:
            data = json.load(f)
        for key in ('thingsboard_host', 'access_token'):
            if key not in data:
                raise KeyError(f"Missing '{key}' in sensitive.json")
        return data['thingsboard_host'], data['access_token']
    except (FileNotFoundError, KeyError, json.JSONDecodeError) as e:
        print(f"Sensitive config error: {e}")
        print("Copy example.sensitive.json to sensitive.json and fill in your values.")
        exit(1)


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


THINGSBOARD_HOST, access_token = load_sensitive()
gpio_pin = load_config()
client = TBDeviceMqttClient(host=THINGSBOARD_HOST, access_token=access_token, port=1883)

try:
    client.connect()
    print("Connected successfully!")
    client.disconnect()
except Exception as e:
    print(f"Connection failed: {e}")
