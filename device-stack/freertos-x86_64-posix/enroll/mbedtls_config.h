/* enroll/mbedtls_config.h – minimal mbedTLS profile for CDM device
 *
 * Required features:
 *   - EC key generation (P-256)
 *   - PKCS#10 CSR generation + PEM output
 *   - TLS 1.2 / 1.3 client with mTLS (X.509 mutual auth)
 *   - SHA-256, AES-128-GCM, ECDHE-ECDSA cipher suites
 *
 * Deliberately excludes: RSA, deprecated ciphers, DTLS, server-side TLS.
 */

#ifndef MBEDTLS_CONFIG_H
#define MBEDTLS_CONFIG_H

/* ── System ─────────────────────────────────────────────────────────────── */
#define MBEDTLS_PLATFORM_C
#define MBEDTLS_ENTROPY_C
#define MBEDTLS_CTR_DRBG_C
#define MBEDTLS_TIMING_C

/* ── Bignum & ECC ─────────────────────────────────────────────────────── */
#define MBEDTLS_BIGNUM_C
#define MBEDTLS_ECP_C
#define MBEDTLS_ECP_DP_SECP256R1_ENABLED
#define MBEDTLS_ECDSA_C
#define MBEDTLS_ECDH_C

/* ── PK abstraction + PEM I/O ────────────────────────────────────────── */
#define MBEDTLS_PK_C
#define MBEDTLS_PK_WRITE_C
#define MBEDTLS_PEM_WRITE_C
#define MBEDTLS_PEM_PARSE_C
#define MBEDTLS_BASE64_C
#define MBEDTLS_ASN1_WRITE_C
#define MBEDTLS_ASN1_PARSE_C
#define MBEDTLS_OID_C

/* ── X.509 CSR generation ─────────────────────────────────────────────── */
#define MBEDTLS_X509_USE_C
#define MBEDTLS_X509_CRT_PARSE_C
#define MBEDTLS_X509_CSR_WRITE_C
#define MBEDTLS_X509_CSR_PARSE_C

/* ── Hash ──────────────────────────────────────────────────────────────── */
#define MBEDTLS_MD_C
#define MBEDTLS_SHA256_C
#define MBEDTLS_SHA512_C   /* needed by entropy */

/* ── Symmetric + AEAD ─────────────────────────────────────────────────── */
#define MBEDTLS_AES_C
#define MBEDTLS_GCM_C
#define MBEDTLS_CIPHER_C
#define MBEDTLS_CIPHER_MODE_CBC   /* TLS 1.2 CBC fallback */

/* ── TLS client (mTLS) ────────────────────────────────────────────────── */
#define MBEDTLS_SSL_TLS_C
#define MBEDTLS_SSL_CLI_C
#define MBEDTLS_SSL_PROTO_TLS1_2
#define MBEDTLS_SSL_PROTO_TLS1_3
#define MBEDTLS_KEY_EXCHANGE_ECDHE_ECDSA_ENABLED
#define MBEDTLS_SSL_MAX_CONTENT_LEN  16384

/* ── Network I/O (POSIX sockets) ─────────────────────────────────────── */
#define MBEDTLS_NET_C

/* ── Debug (disable in release) ─────────────────────────────────────── */
#ifdef DEBUG
#define MBEDTLS_DEBUG_C
#endif

#include "mbedtls/check_config.h"

#endif /* MBEDTLS_CONFIG_H */
