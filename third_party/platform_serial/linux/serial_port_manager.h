#ifndef platform_serial_LINUX_SERIAL_PORT_MANAGER_H_
#define platform_serial_LINUX_SERIAL_PORT_MANAGER_H_

#include <stddef.h>
#include <stdint.h>

#include "serial_port.h"

#ifdef __cplusplus
extern "C" {
#endif

enum {
  SERIAL_PORT_PATH_MAX_LENGTH = 256,
  SERIAL_PORT_DESCRIPTION_MAX_LENGTH = 256,
};

typedef struct serial_port_info_t {
  char port_name[SERIAL_PORT_PATH_MAX_LENGTH];
  char description[SERIAL_PORT_DESCRIPTION_MAX_LENGTH];
  int32_t is_open;
} serial_port_info_t;

typedef struct serial_port_manager serial_port_manager_t;

platform_serial_EXPORT serial_port_manager_t* serial_port_manager_create(void);
platform_serial_EXPORT void serial_port_manager_destroy(
    serial_port_manager_t* manager);

platform_serial_EXPORT int32_t serial_port_manager_list_ports(
    serial_port_manager_t* manager,
    serial_port_info_t* ports,
    size_t capacity,
    size_t* port_count);

platform_serial_EXPORT int32_t serial_port_manager_open(
    serial_port_manager_t* manager,
    const char* port_name,
    const serial_port_config_t* config,
    int32_t* handle_out);
platform_serial_EXPORT int32_t serial_port_manager_close(
    serial_port_manager_t* manager,
    int32_t handle);
platform_serial_EXPORT int32_t serial_port_manager_close_by_name(
    serial_port_manager_t* manager,
    const char* port_name);
platform_serial_EXPORT int32_t serial_port_manager_find_handle(
    serial_port_manager_t* manager,
    const char* port_name,
    int32_t* handle_out);

platform_serial_EXPORT int32_t serial_port_manager_read(
    serial_port_manager_t* manager,
    int32_t handle,
    uint8_t* buffer,
    size_t length,
    size_t* bytes_read);
platform_serial_EXPORT int32_t serial_port_manager_read_with_timeout(
    serial_port_manager_t* manager,
    int32_t handle,
    uint8_t* buffer,
    size_t length,
    int32_t timeout_ms,
    size_t* bytes_read);
platform_serial_EXPORT int32_t serial_port_manager_write(
    serial_port_manager_t* manager,
    int32_t handle,
    const uint8_t* buffer,
    size_t length,
    size_t* bytes_written);
platform_serial_EXPORT int32_t serial_port_manager_write_with_timeout(
    serial_port_manager_t* manager,
    int32_t handle,
    const uint8_t* buffer,
    size_t length,
    int32_t timeout_ms,
    size_t* bytes_written);

platform_serial_EXPORT int32_t serial_port_manager_bytes_available(
    serial_port_manager_t* manager,
    int32_t handle,
    int32_t* bytes_available);
platform_serial_EXPORT int32_t serial_port_manager_flush(
    serial_port_manager_t* manager,
    int32_t handle);
platform_serial_EXPORT int32_t serial_port_manager_reset_buffers(
    serial_port_manager_t* manager,
    int32_t handle);
platform_serial_EXPORT int32_t serial_port_manager_get_control_signals(
    serial_port_manager_t* manager,
    int32_t handle,
    uint32_t* signal_mask);
platform_serial_EXPORT int32_t serial_port_manager_set_control_signals(
    serial_port_manager_t* manager,
    int32_t handle,
    uint32_t set_mask,
    uint32_t clear_mask);

platform_serial_EXPORT const char* serial_port_manager_error_message(
    int32_t error_code);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // platform_serial_LINUX_SERIAL_PORT_MANAGER_H_
