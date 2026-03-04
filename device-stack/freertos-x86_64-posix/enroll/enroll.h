/* enroll/enroll.h – public API for CDM enrollment */
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief  Run the CDM device enrollment flow.
 *
 * Reads configuration from environment variables (DEVICE_ID, TENANT_ID,
 * BRIDGE_API_URL, CERTS_DIR). Idempotent: returns 0 immediately if the
 * device is already enrolled (CERTS_DIR/.enrolled exists).
 *
 * @return 0 on success, negative on error.
 */
int cdm_enroll(void);

#ifdef __cplusplus
}
#endif
