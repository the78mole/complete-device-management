/* mqtt/mqtt_client.h */
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief  Connect to the Tenant ThingsBoard MQTT broker with mTLS and publish
 *         a single test telemetry message, then disconnect.
 *
 * Reads THINGSBOARD_HOST, THINGSBOARD_MQTT_PORT, DEVICE_ID, CERTS_DIR from
 * the environment.  Credentials (ca-chain.pem, device.pem, device-key.pem)
 * must already exist in CERTS_DIR (written by cdm_enroll()).
 *
 * @return 0 on success, negative on error.
 */
int cdm_mqtt_connect_and_publish(void);

#ifdef __cplusplus
}
#endif
