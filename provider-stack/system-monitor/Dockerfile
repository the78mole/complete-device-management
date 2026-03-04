FROM python:3.14-alpine

# paho-mqtt 2.x – pure Python, no C deps required
RUN pip install --no-cache-dir "paho-mqtt==2.1.0"

COPY monitor.py /app/monitor.py

# Non-root execution – no elevated capabilities needed.
# /proc/loadavg and /proc/meminfo are world-readable.
RUN adduser -D -u 10001 monitor
USER monitor

CMD ["python3", "/app/monitor.py"]
