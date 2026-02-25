/* FreeRTOSConfig.h – CDM FreeRTOS/POSIX configuration
 *
 * Minimal configuration for the POSIX/Linux simulator port targeting
 * a single-core x86_64 host process. Adjust tick rate and stack sizes
 * when porting to bare-metal hardware.
 */

#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

/* ── Scheduler ───────────────────────────────────────────────────────────── */
#define configUSE_PREEMPTION                    1
#define configUSE_IDLE_HOOK                     0
#define configUSE_TICK_HOOK                     0
#define configUSE_DAEMON_TASK_STARTUP_HOOK      0
#define configTICK_RATE_HZ                      ( ( TickType_t ) 1000 )
#define configMINIMAL_STACK_SIZE                ( ( unsigned short ) 256 )
#define configTOTAL_HEAP_SIZE                   ( ( size_t ) ( 64 * 1024 * 1024 ) )
#define configMAX_TASK_NAME_LEN                 16
#define configUSE_TRACE_FACILITY                1
#define configUSE_16_BIT_TICKS                  0
#define configIDLE_SHOULD_YIELD                 1
#define configUSE_MUTEXES                       1
#define configUSE_RECURSIVE_MUTEXES             1
#define configUSE_COUNTING_SEMAPHORES           1
#define configUSE_TASK_NOTIFICATIONS            1
#define configTASK_NOTIFICATION_ARRAY_ENTRIES   3
#define configMAX_PRIORITIES                    7
#define configQUEUE_REGISTRY_SIZE               10

/* ── Memory ──────────────────────────────────────────────────────────────── */
#define configSUPPORT_STATIC_ALLOCATION         1
#define configSUPPORT_DYNAMIC_ALLOCATION        1

/* ── Event groups ────────────────────────────────────────────────────────── */
#define configUSE_EVENT_GROUPS                  1

/* ── Software timers ─────────────────────────────────────────────────────── */
#define configUSE_TIMERS                        1
#define configTIMER_TASK_PRIORITY               ( configMAX_PRIORITIES - 1 )
#define configTIMER_QUEUE_LENGTH                10
#define configTIMER_TASK_STACK_DEPTH            ( configMINIMAL_STACK_SIZE * 2 )

/* ── Co-routines (not used) ──────────────────────────────────────────────── */
#define configUSE_CO_ROUTINES                   0

/* ── Run-time stats ──────────────────────────────────────────────────────── */
#define configGENERATE_RUN_TIME_STATS           0
#define configUSE_STATS_FORMATTING_FUNCTIONS    1

/* ── POSIX port specifics ────────────────────────────────────────────────── */
#define configUSE_POSIX_ERRNO                   1

/* ── API inclusions ──────────────────────────────────────────────────────── */
#define INCLUDE_vTaskPrioritySet                1
#define INCLUDE_uxTaskPriorityGet               1
#define INCLUDE_vTaskDelete                     1
#define INCLUDE_vTaskSuspend                    1
#define INCLUDE_vTaskDelayUntil                 1
#define INCLUDE_vTaskDelay                      1
#define INCLUDE_xTaskGetSchedulerState          1
#define INCLUDE_xTaskGetCurrentTaskHandle       1
#define INCLUDE_xEventGroupSetBitFromISR        1

#endif /* FREERTOS_CONFIG_H */
