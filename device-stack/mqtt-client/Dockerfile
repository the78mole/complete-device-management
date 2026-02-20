FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    mosquitto-clients \
    && rm -rf /var/lib/apt/lists/*

COPY mqtt-client/publish-telemetry.sh /usr/local/bin/publish-telemetry.sh
RUN chmod +x /usr/local/bin/publish-telemetry.sh

VOLUME ["/certs"]
ENTRYPOINT ["/usr/local/bin/publish-telemetry.sh"]
