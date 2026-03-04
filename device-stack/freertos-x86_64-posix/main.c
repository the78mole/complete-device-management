/* main.c – CDM FreeRTOS/POSIX device entry point
 *
 * Creates two FreeRTOS tasks:
 *   1. EnrollTask  – runs cdm_enroll() once; signals xEnrolledEvent on success.
 *   2. MQTTTask    – waits for xEnrolledEvent, then calls
 *                    cdm_mqtt_connect_and_publish() in a loop.
 */

#include <stdio.h>
#include <stdlib.h>

/* FreeRTOS */
#include "FreeRTOS.h"
#include "task.h"
#include "event_groups.h"

/* CDM modules */
#include "enroll/enroll.h"
#include "mqtt/mqtt_client.h"

#define ENROLL_DONE_BIT   ( 1UL << 0 )
#define STACK_SIZE        ( 32768 / sizeof(StackType_t) )
#define MQTT_PUBLISH_INTERVAL_MS  30000

static EventGroupHandle_t xEnrolledEvent;

/* ── Enroll task ─────────────────────────────────────────────────────────── */
static void vEnrollTask(void *pvParameters)
{
    (void)pvParameters;
    printf("[main] Enrollment task started\n");

    int ret = cdm_enroll();
    if (ret == 0) {
        printf("[main] Enrollment successful\n");
        xEventGroupSetBits(xEnrolledEvent, ENROLL_DONE_BIT);
    } else {
        fprintf(stderr, "[main] Enrollment FAILED (%d) – device will not connect\n", ret);
    }
    vTaskDelete(NULL);
}

/* ── MQTT task ───────────────────────────────────────────────────────────── */
static void vMQTTTask(void *pvParameters)
{
    (void)pvParameters;
    printf("[main] MQTT task waiting for enrollment...\n");

    xEventGroupWaitBits(xEnrolledEvent, ENROLL_DONE_BIT,
                        pdFALSE, pdTRUE, portMAX_DELAY);

    printf("[main] MQTT task starting\n");
    for (;;) {
        int ret = cdm_mqtt_connect_and_publish();
        if (ret != 0)
            fprintf(stderr, "[main] MQTT connect/publish failed (%d) – retrying in %d ms\n",
                    ret, MQTT_PUBLISH_INTERVAL_MS);
        vTaskDelay(pdMS_TO_TICKS(MQTT_PUBLISH_INTERVAL_MS));
    }
}

/* ── Entry point ─────────────────────────────────────────────────────────── */
int main(void)
{
    printf("CDM FreeRTOS/POSIX device starting\n");

    xEnrolledEvent = xEventGroupCreate();
    if (!xEnrolledEvent) {
        fprintf(stderr, "xEventGroupCreate failed\n");
        return 1;
    }

    xTaskCreate(vEnrollTask, "Enroll", STACK_SIZE, NULL, tskIDLE_PRIORITY + 2, NULL);
    xTaskCreate(vMQTTTask,   "MQTT",   STACK_SIZE, NULL, tskIDLE_PRIORITY + 1, NULL);

    vTaskStartScheduler();

    /* Should never reach here */
    fprintf(stderr, "Scheduler returned – out of memory?\n");
    return 1;
}
