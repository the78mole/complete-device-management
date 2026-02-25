FROM debian:bookworm-slim

# curl: HTTP calls to hawkBit DDI API
# jq: parse JSON responses
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

COPY updater/ddi-poll.sh /usr/local/bin/ddi-poll.sh
RUN chmod +x /usr/local/bin/ddi-poll.sh

VOLUME ["/certs"]
ENTRYPOINT ["/usr/local/bin/ddi-poll.sh"]
