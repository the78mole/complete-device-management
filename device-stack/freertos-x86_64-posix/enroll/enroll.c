/* enroll/enroll.c – CDM device enrollment for FreeRTOS/POSIX
 *
 * Implements the CDM enrollment flow using mbedTLS (key + CSR generation)
 * and libcurl (HTTP POST to Tenant IoT Bridge API).
 *
 * Flow:
 *   1. Check idempotency flag (CERTS_DIR/.enrolled)
 *   2. Generate EC P-256 key pair
 *   3. Generate PKCS#10 CSR  (CN = DEVICE_ID, SAN = DEVICE_ID)
 *   4. POST JSON { "device_id": ..., "device_type": ..., "csr": ... }
 *      to BRIDGE_API_URL/v1/enroll
 *   5. Parse response { "certificate": ..., "ca_chain": ... }
 *   6. Write key, cert, ca_chain to CERTS_DIR/
 *   7. Touch CERTS_DIR/.enrolled
 *
 * Environment variables (read via getenv()):
 *   DEVICE_ID            – unique device identifier
 *   DEVICE_TYPE          – device model / type string
 *   TENANT_ID            – CDM tenant ID
 *   BRIDGE_API_URL       – Tenant IoT Bridge API base URL (http or https)
 *   CERTS_DIR            – directory for persisted credentials (default: ./certs)
 */

#include "enroll.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/stat.h>

#include <curl/curl.h>

#include <mbedtls/entropy.h>
#include <mbedtls/ctr_drbg.h>
#include <mbedtls/pk.h>
#include <mbedtls/x509_crt.h>
#include <mbedtls/x509_csr.h>
#include <mbedtls/pem.h>
#include <mbedtls/error.h>

/* ── helpers ─────────────────────────────────────────────────────────────── */

#define CDM_CHECK(ret, label, msg)                        \
    do {                                                   \
        if ((ret) != 0) {                                  \
            char _ebuf[256];                               \
            mbedtls_strerror((ret), _ebuf, sizeof(_ebuf)); \
            fprintf(stderr, "[enroll] %s: %s\n", (msg), _ebuf); \
            goto label;                                    \
        }                                                  \
    } while (0)

static const char *env_or(const char *key, const char *fallback)
{
    const char *v = getenv(key);
    return (v && v[0]) ? v : fallback;
}

static int write_file(const char *path, const unsigned char *data, size_t len)
{
    FILE *f = fopen(path, "wb");
    if (!f) { perror(path); return -1; }
    fwrite(data, 1, len, f);
    fclose(f);
    return 0;
}

/* libcurl response buffer */
typedef struct { char *buf; size_t len; } curl_buf_t;

static size_t curl_write_cb(void *ptr, size_t size, size_t nmemb, void *userdata)
{
    curl_buf_t *cb = (curl_buf_t *)userdata;
    size_t bytes = size * nmemb;
    cb->buf = realloc(cb->buf, cb->len + bytes + 1);
    if (!cb->buf) return 0;
    memcpy(cb->buf + cb->len, ptr, bytes);
    cb->len += bytes;
    cb->buf[cb->len] = '\0';
    return bytes;
}

/* Very small JSON field extractor – sufficient for the enroll response.
 * Finds the first occurrence of "key":"value" and copies value into out. */
static int json_get_string(const char *json, const char *key, char *out, size_t out_sz)
{
    char search[128];
    snprintf(search, sizeof(search), "\"%s\":", key);
    const char *p = strstr(json, search);
    if (!p) return -1;
    p += strlen(search);
    while (*p == ' ') p++;
    if (*p != '"') return -1;
    p++;
    size_t i = 0;
    while (*p && *p != '"' && i < out_sz - 1) {
        if (*p == '\\' && *(p+1) == 'n') { out[i++] = '\n'; p += 2; continue; }
        if (*p == '\\' && *(p+1) == '\\') { out[i++] = '\\'; p += 2; continue; }
        out[i++] = *p++;
    }
    out[i] = '\0';
    return (int)i;
}

/* ── public API ──────────────────────────────────────────────────────────── */

int cdm_enroll(void)
{
    const char *device_id    = env_or("DEVICE_ID",      "freertos-device-001");
    const char *device_type  = env_or("DEVICE_TYPE",    "freertos-posix");
    const char *tenant_id    = env_or("TENANT_ID",      "tenant1");
    const char *api_url      = env_or("BRIDGE_API_URL", "");
    const char *certs_dir    = env_or("CERTS_DIR",      "./certs");

    if (!api_url[0]) {
        fprintf(stderr, "[enroll] BRIDGE_API_URL is not set\n");
        return -1;
    }
    (void)tenant_id; /* used in log messages */

    /* Idempotency */
    char flag_path[512]; snprintf(flag_path, sizeof(flag_path), "%s/.enrolled", certs_dir);
    char key_path[512];  snprintf(key_path,  sizeof(key_path),  "%s/device-key.pem", certs_dir);
    char crt_path[512];  snprintf(crt_path,  sizeof(crt_path),  "%s/device.pem", certs_dir);
    char ca_path[512];   snprintf(ca_path,   sizeof(ca_path),   "%s/ca-chain.pem", certs_dir);

    {   FILE *f = fopen(flag_path, "r");
        if (f) { fclose(f);
                 printf("[enroll] Already enrolled – skipping.\n");
                 return 0; }
    }

    mkdir(certs_dir, 0755);
    printf("[enroll] Enrolling device '%s' (tenant: %s)\n", device_id, tenant_id);

    /* ── 1. RNG init ─────────────────────────────────────────────────────── */
    mbedtls_entropy_context  entropy;
    mbedtls_ctr_drbg_context ctr_drbg;
    mbedtls_pk_context       pk;
    mbedtls_x509write_csr    csr;
    int ret = 0;

    mbedtls_entropy_init(&entropy);
    mbedtls_ctr_drbg_init(&ctr_drbg);
    mbedtls_pk_init(&pk);
    mbedtls_x509write_csr_init(&csr);

    ret = mbedtls_ctr_drbg_seed(&ctr_drbg, mbedtls_entropy_func, &entropy,
                                 (const unsigned char *)"cdm-enroll", 10);
    CDM_CHECK(ret, cleanup, "ctr_drbg_seed");

    /* ── 2. Generate EC P-256 key pair ──────────────────────────────────── */
    printf("[enroll] Generating EC P-256 key pair...\n");
    ret = mbedtls_pk_setup(&pk, mbedtls_pk_info_from_type(MBEDTLS_PK_ECKEY));
    CDM_CHECK(ret, cleanup, "pk_setup");

    ret = mbedtls_ecp_gen_key(MBEDTLS_ECP_DP_SECP256R1, mbedtls_pk_ec(pk),
                               mbedtls_ctr_drbg_random, &ctr_drbg);
    CDM_CHECK(ret, cleanup, "ecp_gen_key");

    /* Write private key */
    unsigned char key_pem[4096] = {0};
    ret = mbedtls_pk_write_key_pem(&pk, key_pem, sizeof(key_pem));
    CDM_CHECK(ret, cleanup, "pk_write_key_pem");
    write_file(key_path, key_pem, strlen((char *)key_pem));
    printf("[enroll] Key written to %s\n", key_path);

    /* ── 3. Generate PKCS#10 CSR ─────────────────────────────────────────── */
    printf("[enroll] Generating CSR for CN=%s...\n", device_id);
    mbedtls_x509write_csr_set_key(&csr, &pk);
    mbedtls_x509write_csr_set_md_alg(&csr, MBEDTLS_MD_SHA256);

    char subject[256];
    snprintf(subject, sizeof(subject), "CN=%s,O=CDM,OU=%s", device_id, tenant_id);
    ret = mbedtls_x509write_csr_set_subject_name(&csr, subject);
    CDM_CHECK(ret, cleanup, "csr_set_subject_name");

    /* Add SAN = device_id as dNSName */
    /* NOTE: mbedTLS 3.x supports SANs via mbedtls_x509write_csr_set_extension */

    unsigned char csr_pem[4096] = {0};
    ret = mbedtls_x509write_csr_pem(&csr, csr_pem, sizeof(csr_pem),
                                     mbedtls_ctr_drbg_random, &ctr_drbg);
    CDM_CHECK(ret, cleanup, "x509write_csr_pem");
    printf("[enroll] CSR generated.\n");

    /* ── 4. POST CSR to IoT Bridge API ──────────────────────────────────── */
    char enroll_url[512];
    snprintf(enroll_url, sizeof(enroll_url), "%s/v1/enroll", api_url);
    printf("[enroll] POSTing CSR to %s\n", enroll_url);

    /* Build JSON body – escape PEM newlines as \n */
    char csr_escaped[8192]; size_t ei = 0;
    for (const char *p = (char *)csr_pem; *p && ei < sizeof(csr_escaped) - 3; p++) {
        if (*p == '\n') { csr_escaped[ei++] = '\\'; csr_escaped[ei++] = 'n'; }
        else              csr_escaped[ei++] = *p;
    }
    csr_escaped[ei] = '\0';

    char post_body[8192 + 256];
    snprintf(post_body, sizeof(post_body),
             "{\"device_id\":\"%s\",\"device_type\":\"%s\",\"csr\":\"%s\"}",
             device_id, device_type, csr_escaped);

    curl_global_init(CURL_GLOBAL_DEFAULT);
    CURL *curl = curl_easy_init();
    curl_buf_t response = {0};
    long http_code = 0;

    if (!curl) { fprintf(stderr, "[enroll] curl_easy_init failed\n"); ret = -1; goto cleanup; }

    struct curl_slist *headers = NULL;
    headers = curl_slist_append(headers, "Content-Type: application/json");

    curl_easy_setopt(curl, CURLOPT_URL, enroll_url);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, post_body);
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, curl_write_cb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 30L);

    CURLcode curl_ret = curl_easy_perform(curl);
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    curl_global_cleanup();

    if (curl_ret != CURLE_OK) {
        fprintf(stderr, "[enroll] curl error: %s\n", curl_easy_strerror(curl_ret));
        ret = -1; goto cleanup;
    }
    if (http_code != 200) {
        fprintf(stderr, "[enroll] HTTP %ld from enroll endpoint: %s\n",
                http_code, response.buf ? response.buf : "(empty)");
        ret = -1; goto cleanup;
    }

    /* ── 5. Parse response and persist certificate + CA chain ───────────── */
    char cert_pem[8192]  = {0};
    char chain_pem[8192] = {0};

    if (json_get_string(response.buf, "certificate", cert_pem,  sizeof(cert_pem))  < 0 ||
        json_get_string(response.buf, "ca_chain",    chain_pem, sizeof(chain_pem)) < 0) {
        fprintf(stderr, "[enroll] Failed to parse enroll response\n");
        ret = -1; goto cleanup;
    }

    /* Unescape \n back to real newlines */
    for (char *p = cert_pem;  *p; p++) if (*p == '\\' && *(p+1) == 'n') { *p = '\n'; memmove(p+1, p+2, strlen(p+2)+1); }
    for (char *p = chain_pem; *p; p++) if (*p == '\\' && *(p+1) == 'n') { *p = '\n'; memmove(p+1, p+2, strlen(p+2)+1); }

    write_file(crt_path, (unsigned char *)cert_pem,  strlen(cert_pem));
    write_file(ca_path,  (unsigned char *)chain_pem, strlen(chain_pem));
    printf("[enroll] Certificate written to %s\n", crt_path);
    printf("[enroll] CA chain written to    %s\n", ca_path);

    /* Touch .enrolled flag */
    { FILE *f = fopen(flag_path, "w"); if (f) fclose(f); }
    printf("[enroll] Enrollment complete.\n");

cleanup:
    free(response.buf);
    mbedtls_x509write_csr_free(&csr);
    mbedtls_pk_free(&pk);
    mbedtls_ctr_drbg_free(&ctr_drbg);
    mbedtls_entropy_free(&entropy);
    return ret;
}
