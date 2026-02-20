FROM alpine:3.20

RUN apk add --no-cache mosquitto-clients

COPY mqtt-client/publish-telemetry.sh /usr/local/bin/publish-telemetry.sh
RUN chmod +x /usr/local/bin/publish-telemetry.sh

VOLUME ["/certs"]
ENTRYPOINT ["/usr/local/bin/publish-telemetry.sh"]
