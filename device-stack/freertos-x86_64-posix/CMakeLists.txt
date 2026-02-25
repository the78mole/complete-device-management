cmake_minimum_required(VERSION 3.20)
project(cdm-freertos-device C)

set(CMAKE_C_STANDARD 11)

include(FetchContent)

# ── FreeRTOS Kernel (POSIX/Linux simulator port) ──────────────────────────────
FetchContent_Declare(freertos_kernel
  GIT_REPOSITORY https://github.com/FreeRTOS/FreeRTOS-Kernel.git
  GIT_TAG        V11.1.0
)
set(FREERTOS_PORT GCC_POSIX CACHE STRING "" FORCE)
set(FREERTOS_HEAP  "4"      CACHE STRING "" FORCE)
FetchContent_MakeAvailable(freertos_kernel)

# ── mbedTLS ───────────────────────────────────────────────────────────────────
FetchContent_Declare(mbedtls
  GIT_REPOSITORY https://github.com/Mbed-TLS/mbedtls.git
  GIT_TAG        v3.6.2
)
set(ENABLE_TESTING  OFF CACHE BOOL "" FORCE)
set(ENABLE_PROGRAMS OFF CACHE BOOL "" FORCE)
set(MBEDTLS_USER_CONFIG_FILE "${CMAKE_CURRENT_SOURCE_DIR}/enroll/mbedtls_config.h"
    CACHE STRING "" FORCE)
FetchContent_MakeAvailable(mbedtls)

# ── coreMQTT ──────────────────────────────────────────────────────────────────
FetchContent_Declare(coremqtt
  GIT_REPOSITORY https://github.com/FreeRTOS/coreMQTT.git
  GIT_TAG        v2.3.1
)
FetchContent_MakeAvailable(coremqtt)

# ── FreeRTOS config ───────────────────────────────────────────────────────────
# FreeRTOSConfig.h must live somewhere on the include path.
add_library(freertos_config INTERFACE)
target_include_directories(freertos_config INTERFACE ${CMAKE_CURRENT_SOURCE_DIR})

# ── Main executable ───────────────────────────────────────────────────────────
add_executable(cdm-freertos-device
  main.c
  enroll/enroll.c
  mqtt/mqtt_client.c
)

target_include_directories(cdm-freertos-device PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}
  ${CMAKE_CURRENT_SOURCE_DIR}/enroll
  ${CMAKE_CURRENT_SOURCE_DIR}/mqtt
)

target_link_libraries(cdm-freertos-device PRIVATE
  freertos_kernel
  mbedtls
  mbedx509
  mbedcrypto
  coremqtt
  curl       # used only for enrollment HTTP POST
  pthread
  m
)

target_compile_options(cdm-freertos-device PRIVATE -Wall -Wextra)
