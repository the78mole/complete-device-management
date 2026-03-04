#!/usr/bin/env python3
"""
monitor.py – Provider-Stack system metrics publisher
=====================================================
Reads CPU load and RAM usage from /proc and publishes a JSON payload
every INTERVAL seconds to an MQTT broker using mTLS authentication.

Environment variables:
  MQTT_HOST      – Broker hostname (default: rabbitmq)
  MQTT_PORT      – Broker TLS port  (default: 8883)
  MQTT_TOPIC     – Publish topic    (default: cdm/provider/system)
  TLS_CA         – CA certificate   (default: /tls/ca.crt)
  TLS_CERT       – Client cert      (default: /tls/system-monitor.crt)
  TLS_KEY        – Client key       (default: /tls/system-monitor.key)
  INTERVAL       – Publish interval in seconds (default: 5)

No username / password – identity is derived from the client cert CN
by the RabbitMQ EXTERNAL auth mechanism (mqtt.ssl_cert_login = true).
"""

import json
import os
import ssl
import time
import logging

import paho.mqtt.client as mqtt

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [system-monitor] %(levelname)s %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
log = logging.getLogger(__name__)

# ── Configuration ────────────────────────────────────────────────────────────
MQTT_HOST = os.environ.get("MQTT_HOST", "rabbitmq")
MQTT_PORT = int(os.environ.get("MQTT_PORT", "8883"))
MQTT_TOPIC = os.environ.get("MQTT_TOPIC", "cdm/provider/system")
TLS_CA   = os.environ.get("TLS_CA",   "/tls/ca.crt")
TLS_CERT = os.environ.get("TLS_CERT", "/tls/system-monitor.crt")
TLS_KEY  = os.environ.get("TLS_KEY",  "/tls/system-monitor.key")
INTERVAL = int(os.environ.get("INTERVAL", "5"))


# ── Proc readers ─────────────────────────────────────────────────────────────

def read_cpu_load() -> dict:
    """Return the three load averages from /proc/loadavg."""
    with open("/proc/loadavg") as f:
        parts = f.read().split()
    return {
        "cpu_load_1m":  float(parts[0]),
        "cpu_load_5m":  float(parts[1]),
        "cpu_load_15m": float(parts[2]),
    }


def read_memory() -> dict:
    """Return memory statistics (kB) from /proc/meminfo."""
    info: dict[str, int] = {}
    with open("/proc/meminfo") as f:
        for line in f:
            key, _, value = line.partition(":")
            info[key.strip()] = int(value.split()[0])

    mem_total     = info["MemTotal"]
    mem_available = info["MemAvailable"]
    mem_used      = mem_total - mem_available

    return {
        "mem_total_kb":     mem_total,
        "mem_available_kb": mem_available,
        "mem_used_kb":      mem_used,
        "mem_used_percent": round(mem_used / mem_total * 100, 2),
    }


# ── MQTT client ──────────────────────────────────────────────────────────────

def on_connect(client, userdata, flags, reason_code, properties):  # paho v2
    if reason_code == 0:
        log.info("Connected to %s:%d (topic: %s)", MQTT_HOST, MQTT_PORT, MQTT_TOPIC)
    else:
        log.error("Connection refused – reason code %s", reason_code)


def on_disconnect(client, userdata, disconnect_flags, reason_code, properties):
    if reason_code != 0:
        log.warning("Unexpected disconnect (%s) – reconnecting…", reason_code)


def main() -> None:
    log.info("Starting system-monitor (interval=%ds)", INTERVAL)
    log.info("Broker: tls://%s:%d", MQTT_HOST, MQTT_PORT)
    log.info("Cert:   %s", TLS_CERT)

    client = mqtt.Client(
        callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
        client_id="system-monitor",
        protocol=mqtt.MQTTv311,   # paho 2.x defaults to MQTTv5; RabbitMQ MQTT plugin expects 3.1.1
        clean_session=True,
    )
    client.on_connect    = on_connect
    client.on_disconnect = on_disconnect
    # ssl.PROTOCOL_TLS_CLIENT enables hostname verification without the strict
    # EKU purpose-checking that ssl.Purpose.SERVER_AUTH adds.  step-ca issues
    # server certs without the serverAuth EKU by default via the iot-bridge
    # provisioner, which causes ssl.Purpose.SERVER_AUTH to reject them.
    _ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    _ctx.verify_mode = ssl.CERT_REQUIRED
    _ctx.check_hostname = True
    _ctx.load_verify_locations(cafile=TLS_CA)
    _ctx.load_cert_chain(certfile=TLS_CERT, keyfile=TLS_KEY)
    client.tls_set_context(_ctx)

    # Connect with reconnect-on-failure; loop_start() handles the network thread
    client.connect_async(MQTT_HOST, MQTT_PORT, keepalive=60)
    client.loop_start()

    try:
        while True:
            payload = {
                **read_cpu_load(),
                **read_memory(),
            }
            msg_info = client.publish(
                topic=MQTT_TOPIC,
                payload=json.dumps(payload),
                qos=1,
                retain=False,
            )
            if msg_info.rc == mqtt.MQTT_ERR_SUCCESS:
                log.info(
                    "Published – cpu_1m=%.2f  mem_used=%.1f%%",
                    payload["cpu_load_1m"],
                    payload["mem_used_percent"],
                )
            else:
                log.warning("Publish failed (rc=%d) – broker not yet ready", msg_info.rc)

            time.sleep(INTERVAL)
    except KeyboardInterrupt:
        log.info("Shutting down.")
    finally:
        client.loop_stop()
        client.disconnect()


if __name__ == "__main__":
    main()
