from tb_device_mqtt import TBDeviceMqttClient
import json

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


THINGSBOARD_HOST = 'demo.thingsboard.io'
access_token, gpio_pin = load_config()
client = TBDeviceMqttClient(host=THINGSBOARD_HOST, access_token=access_token, port=1883)

try:
    client.connect()
    print("Connected successfully!")
    client.disconnect()
except Exception as e:
    print(f"Connection failed: {e}")
