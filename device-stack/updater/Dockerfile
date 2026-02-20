FROM alpine:3.20

# curl: HTTP calls to hawkBit DDI API
# jq: parse JSON responses
RUN apk add --no-cache curl jq

COPY updater/ddi-poll.sh /usr/local/bin/ddi-poll.sh
RUN chmod +x /usr/local/bin/ddi-poll.sh

VOLUME ["/certs"]
ENTRYPOINT ["/usr/local/bin/ddi-poll.sh"]
