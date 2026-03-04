/* mqtt/mqtt_client.c – minimal mTLS MQTT stub for CDM / coreMQTT
 *
 * Connects to the Tenant ThingsBoard MQTT broker using the device certificate
 * issued during enrollment (cdm_enroll()), then publishes a test telemetry
 * message to  v1/devices/me/telemetry.
 *
 * TLS is provided by mbedTLS; the network transport adapter for coreMQTT
 * is the standard POSIX socket + mbedTLS layer.
 *
 * Environment variables:
 *   THINGSBOARD_HOST       – MQTT broker hostname / IP
 *   THINGSBOARD_MQTT_PORT  – MQTT TLS port (default: 8883)
 *   DEVICE_ID              – used as MQTT Client ID
 *   CERTS_DIR              – directory containing device.pem, device-key.pem,
 *                            ca-chain.pem  (written by cdm_enroll())
 */

#include "mqtt_client.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <mbedtls/net_sockets.h>
#include <mbedtls/ssl.h>
#include <mbedtls/x509_crt.h>
#include <mbedtls/pk.h>
#include <mbedtls/entropy.h>
#include <mbedtls/ctr_drbg.h>
#include <mbedtls/error.h>

/* coreMQTT */
#include "core_mqtt.h"

/* ── Internal TLS context ────────────────────────────────────────────────── */
typedef struct {
    mbedtls_net_context      net;
    mbedtls_ssl_context      ssl;
    mbedtls_ssl_config       conf;
    mbedtls_x509_crt         ca_chain;
    mbedtls_x509_crt         client_cert;
    mbedtls_pk_context       client_key;
    mbedtls_entropy_context  entropy;
    mbedtls_ctr_drbg_context ctr_drbg;
} tls_ctx_t;

static tls_ctx_t g_tls;

/* ── coreMQTT transport callbacks ──────────────────────────────────────── */
static int32_t transport_recv(NetworkContext_t *ctx, void *buf, size_t len)
{
    (void)ctx;
    int ret = mbedtls_ssl_read(&g_tls.ssl, buf, len);
    if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE) return 0;
    return ret < 0 ? -1 : ret;
}

static int32_t transport_send(NetworkContext_t *ctx, const void *buf, size_t len)
{
    (void)ctx;
    int ret = mbedtls_ssl_write(&g_tls.ssl, buf, len);
    if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE) return 0;
    return ret < 0 ? -1 : ret;
}

/* ── Public API ─────────────────────────────────────────────────────────── */

int cdm_mqtt_connect_and_publish(void)
{
    const char *host      = getenv("THINGSBOARD_HOST");
    const char *port_str  = getenv("THINGSBOARD_MQTT_PORT");
    const char *device_id = getenv("DEVICE_ID");
    const char *certs_dir = getenv("CERTS_DIR");

    if (!host || !host[0]) { fprintf(stderr, "[mqtt] THINGSBOARD_HOST not set\n"); return -1; }
    if (!port_str)  port_str  = "8883";
    if (!device_id) device_id = "freertos-device-001";
    if (!certs_dir) certs_dir = "./certs";

    char ca_path[512], crt_path[512], key_path[512];
    snprintf(ca_path,  sizeof(ca_path),  "%s/ca-chain.pem",  certs_dir);
    snprintf(crt_path, sizeof(crt_path), "%s/device.pem",    certs_dir);
    snprintf(key_path, sizeof(key_path), "%s/device-key.pem", certs_dir);

    int ret = 0;

    /* ── TLS setup ──────────────────────────────────────────────────────── */
    mbedtls_net_init(&g_tls.net);
    mbedtls_ssl_init(&g_tls.ssl);
    mbedtls_ssl_config_init(&g_tls.conf);
    mbedtls_x509_crt_init(&g_tls.ca_chain);
    mbedtls_x509_crt_init(&g_tls.client_cert);
    mbedtls_pk_init(&g_tls.client_key);
    mbedtls_entropy_init(&g_tls.entropy);
    mbedtls_ctr_drbg_init(&g_tls.ctr_drbg);

    ret = mbedtls_ctr_drbg_seed(&g_tls.ctr_drbg, mbedtls_entropy_func, &g_tls.entropy,
                                 (const unsigned char *)"cdm-mqtt", 8);
    if (ret) { fprintf(stderr, "[mqtt] ctr_drbg_seed: -0x%04x\n", -ret); goto cleanup; }

    ret = mbedtls_x509_crt_parse_file(&g_tls.ca_chain, ca_path);
    if (ret) { fprintf(stderr, "[mqtt] parse CA chain: -0x%04x\n", -ret); goto cleanup; }

    ret = mbedtls_x509_crt_parse_file(&g_tls.client_cert, crt_path);
    if (ret) { fprintf(stderr, "[mqtt] parse client cert: -0x%04x\n", -ret); goto cleanup; }

    ret = mbedtls_pk_parse_keyfile(&g_tls.client_key, key_path, NULL,
                                   mbedtls_ctr_drbg_random, &g_tls.ctr_drbg);
    if (ret) { fprintf(stderr, "[mqtt] parse client key: -0x%04x\n", -ret); goto cleanup; }

    ret = mbedtls_net_connect(&g_tls.net, host, port_str, MBEDTLS_NET_PROTO_TCP);
    if (ret) { fprintf(stderr, "[mqtt] net_connect %s:%s: -0x%04x\n", host, port_str, -ret); goto cleanup; }

    ret = mbedtls_ssl_config_defaults(&g_tls.conf, MBEDTLS_SSL_IS_CLIENT,
                                       MBEDTLS_SSL_TRANSPORT_STREAM,
                                       MBEDTLS_SSL_PRESET_DEFAULT);
    if (ret) { fprintf(stderr, "[mqtt] ssl_config_defaults: -0x%04x\n", -ret); goto cleanup; }

    mbedtls_ssl_conf_authmode(&g_tls.conf, MBEDTLS_SSL_VERIFY_REQUIRED);
    mbedtls_ssl_conf_ca_chain(&g_tls.conf, &g_tls.ca_chain, NULL);
    mbedtls_ssl_conf_own_cert(&g_tls.conf, &g_tls.client_cert, &g_tls.client_key);
    mbedtls_ssl_conf_rng(&g_tls.conf, mbedtls_ctr_drbg_random, &g_tls.ctr_drbg);

    ret = mbedtls_ssl_setup(&g_tls.ssl, &g_tls.conf);
    if (ret) { fprintf(stderr, "[mqtt] ssl_setup: -0x%04x\n", -ret); goto cleanup; }

    ret = mbedtls_ssl_set_hostname(&g_tls.ssl, host);
    if (ret) { fprintf(stderr, "[mqtt] ssl_set_hostname: -0x%04x\n", -ret); goto cleanup; }

    mbedtls_ssl_set_bio(&g_tls.ssl, &g_tls.net,
                         mbedtls_net_send, mbedtls_net_recv, NULL);

    while ((ret = mbedtls_ssl_handshake(&g_tls.ssl)) != 0) {
        if (ret != MBEDTLS_ERR_SSL_WANT_READ && ret != MBEDTLS_ERR_SSL_WANT_WRITE) {
            fprintf(stderr, "[mqtt] TLS handshake failed: -0x%04x\n", -ret);
            goto cleanup;
        }
    }
    printf("[mqtt] mTLS handshake OK – connected to %s:%s\n", host, port_str);

    /* ── coreMQTT CONNECT ───────────────────────────────────────────────── */
    static uint8_t mqtt_buf[4096];
    NetworkContext_t net_ctx = {0};
    TransportInterface_t transport = {
        .recv = transport_recv,
        .send = transport_send,
        .pNetworkContext = &net_ctx,
    };
    MQTTFixedBuffer_t fixed_buf = { .pBuffer = mqtt_buf, .size = sizeof(mqtt_buf) };
    MQTTContext_t     mqtt_ctx;

    MQTTStatus_t status = MQTT_Init(&mqtt_ctx, &transport, NULL, NULL, &fixed_buf);
    if (status != MQTTSuccess) {
        fprintf(stderr, "[mqtt] MQTT_Init failed: %d\n", status);
        ret = -1; goto cleanup;
    }

    MQTTConnectInfo_t conn_info = {
        .cleanSession     = true,
        .pClientIdentifier = device_id,
        .clientIdentifierLength = (uint16_t)strlen(device_id),
        .keepAliveSeconds = 60,
    };
    bool session_present = false;
    status = MQTT_Connect(&mqtt_ctx, &conn_info, NULL, 5000, &session_present);
    if (status != MQTTSuccess) {
        fprintf(stderr, "[mqtt] MQTT_Connect failed: %d\n", status);
        ret = -1; goto cleanup;
    }
    printf("[mqtt] MQTT CONNACK received\n");

    /* ── Publish test telemetry ─────────────────────────────────────────── */
    static const char topic[]   = "v1/devices/me/telemetry";
    static const char payload[] = "{\"enrolled\":true,\"platform\":\"freertos-posix\"}";
    MQTTPublishInfo_t pub = {
        .qos             = MQTTQoS0,
        .pTopicName      = topic,
        .topicNameLength = sizeof(topic) - 1,
        .pPayload        = payload,
        .payloadLength   = sizeof(payload) - 1,
    };
    status = MQTT_Publish(&mqtt_ctx, &pub, 0);
    if (status != MQTTSuccess)
        fprintf(stderr, "[mqtt] MQTT_Publish failed: %d\n", status);
    else
        printf("[mqtt] Published telemetry: %s\n", payload);

    MQTT_Disconnect(&mqtt_ctx);

cleanup:
    mbedtls_ssl_close_notify(&g_tls.ssl);
    mbedtls_net_free(&g_tls.net);
    mbedtls_ssl_free(&g_tls.ssl);
    mbedtls_ssl_config_free(&g_tls.conf);
    mbedtls_x509_crt_free(&g_tls.ca_chain);
    mbedtls_x509_crt_free(&g_tls.client_cert);
    mbedtls_pk_free(&g_tls.client_key);
    mbedtls_ctr_drbg_free(&g_tls.ctr_drbg);
    mbedtls_entropy_free(&g_tls.entropy);
    return ret;
}
