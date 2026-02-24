#!/bin/sh
# ddi-poll.sh – simulated rauc-hawkbit-updater DDI poller
#
# On a real Yocto device, the system-level rauc-hawkbit-updater daemon uses the
# config in /etc/rauc-hawkbit-updater/config.conf.  In this Docker simulation
# the same config values are provided via environment variables so no real RAUC
# A/B swap is performed; instead the script logs what it "would" install and
# reports success back to hawkBit.
#
# hawkBit DDI (Direct Device Integration) API flow:
#   1. GET /DEFAULT/controller/v1/{controllerId}          → get action links
#   2. GET /DEFAULT/controller/v1/{controllerId}/deploymentBase/{actionId}
#   3. POST /DEFAULT/controller/v1/{controllerId}/deploymentBase/{actionId}/feedback
#        { "status": { "execution": "proceeding", "result": { "finished": "none" } } }
#   4. (simulate download + install)
#   5. POST .../feedback  { "status": { "execution": "closed", "result": { "finished": "success" } } }

set -eu

HAWKBIT_URL="${HAWKBIT_URL:-http://host.docker.internal:8070}"
HAWKBIT_TENANT="${HAWKBIT_TENANT:-DEFAULT}"
DEVICE_ID="${DEVICE_ID:-sim-device-001}"
POLL_INTERVAL="${POLL_INTERVAL_S:-30}"
ENROLLED="/certs/.enrolled"

log() { echo "$(date '+%T') [rauc-updater] $*"; }

# ── Wait for enrollment ───────────────────────────────────────────────────────
log "Waiting for device enrollment…"
while [ ! -f "$ENROLLED" ]; do sleep 2; done
log "Device enrolled – starting DDI poll loop."

# ── Helpers ───────────────────────────────────────────────────────────────────
ddi_base="${HAWKBIT_URL}/${HAWKBIT_TENANT}/controller/v1/${DEVICE_ID}"

post_feedback() {
    action_id=$1
    execution=$2
    finished=$3
    curl -sf -X POST \
        "${ddi_base}/deploymentBase/${action_id}/feedback" \
        -H "Content-Type: application/json" \
        -d "{\"id\":\"${action_id}\",\"status\":{\"execution\":\"${execution}\",\"result\":{\"finished\":\"${finished}\"}}}" \
        > /dev/null
}

# ── DDI poll loop ─────────────────────────────────────────────────────────────
while true; do
    log "Polling hawkBit at ${ddi_base}…"

    # Fetch controller response – contains _links with any pending deployments
    RESP=$(curl -sf "${ddi_base}" 2>/dev/null) || {
        log "WARNING: cannot reach hawkBit – retrying in ${POLL_INTERVAL}s"
        sleep "$POLL_INTERVAL"
        continue
    }

    DEPLOY_LINK=$(echo "$RESP" | jq -r '._links.deploymentBase.href // empty')

    if [ -z "$DEPLOY_LINK" ]; then
        log "No pending deployments."
        sleep "$POLL_INTERVAL"
        continue
    fi

    # Extract action ID from the link
    ACTION_ID=$(basename "$DEPLOY_LINK")
    log "Found deployment action: ${ACTION_ID}"

    # Fetch deployment details
    DEPLOY=$(curl -sf "${DEPLOY_LINK}" 2>/dev/null) || {
        log "WARNING: failed to fetch deployment details"
        sleep "$POLL_INTERVAL"
        continue
    }

    BUNDLE_URL=$(echo "$DEPLOY" | jq -r '.deployment.chunks[0].artifacts[0]._links.download.href // empty')
    BUNDLE_NAME=$(echo "$DEPLOY" | jq -r '.deployment.chunks[0].name // "unknown"')
    BUNDLE_VERSION=$(echo "$DEPLOY" | jq -r '.deployment.chunks[0].version // "unknown"')

    log "Deployment: name=${BUNDLE_NAME} version=${BUNDLE_VERSION}"
    if [ -n "$BUNDLE_URL" ]; then
        log "Bundle URL: ${BUNDLE_URL}"
    fi

    # ── Simulate install ──────────────────────────────────────────────────────
    log "Acknowledging deployment (proceeding)…"
    post_feedback "$ACTION_ID" "proceeding" "none" || true

    log "Simulating RAUC bundle download (5s)…"
    sleep 5

    log "Simulating RAUC A/B slot write (5s)…"
    sleep 5

    log "Simulating reboot into new slot…"
    sleep 2

    log "Reporting installation success to hawkBit…"
    post_feedback "$ACTION_ID" "closed" "success" || {
        log "WARNING: failed to post success feedback – will retry"
        sleep "$POLL_INTERVAL"
        continue
    }

    log "OTA update complete for action ${ACTION_ID}."
    sleep "$POLL_INTERVAL"
done
