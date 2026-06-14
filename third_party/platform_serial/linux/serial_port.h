#ifndef platform_serial_LINUX_SERIAL_PORT_H_
#define platform_serial_LINUX_SERIAL_PORT_H_

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__GNUC__)
#define platform_serial_EXPORT __attribute__((visibility("default")))
#else
#define platform_serial_EXPORT
#endif

enum {
  SERIAL_SIGNAL_RTS = 1u << 0,
  SERIAL_SIGNAL_CTS = 1u << 1,
  SERIAL_SIGNAL_DTR = 1u << 2,
  SERIAL_SIGNAL_DSR = 1u << 3,
  SERIAL_SIGNAL_DCD = 1u << 4,
};

typedef enum serial_parity_t {
  SERIAL_PARITY_NONE = 0,
  SERIAL_PARITY_EVEN = 1,
  SERIAL_PARITY_ODD = 2,
  SERIAL_PARITY_MARK = 3,
  SERIAL_PARITY_SPACE = 4,
} serial_parity_t;

typedef enum serial_stop_bits_t {
  SERIAL_STOP_BITS_ONE = 0,
  SERIAL_STOP_BITS_ONE_POINT_FIVE = 1,
  SERIAL_STOP_BITS_TWO = 2,
} serial_stop_bits_t;

typedef enum serial_flow_control_t {
  SERIAL_FLOW_CONTROL_NONE = 0,
  SERIAL_FLOW_CONTROL_RTSCTS = 1,
  SERIAL_FLOW_CONTROL_XONXOFF = 2,
} serial_flow_control_t;

typedef struct serial_port_config_t {
  int32_t baud_rate;
  int32_t data_bits;
  int32_t stop_bits;
  int32_t parity;
  int32_t flow_control;
  int32_t read_timeout_ms;
  int32_t write_timeout_ms;
} serial_port_config_t;

typedef struct serial_port serial_port_t;

platform_serial_EXPORT serial_port_t* serial_port_create(const char* path,
                                                        int32_t* error_code);
platform_serial_EXPORT void serial_port_destroy(serial_port_t* port);

platform_serial_EXPORT int32_t serial_port_open(serial_port_t* port,
                                               const serial_port_config_t* config);
platform_serial_EXPORT int32_t serial_port_close(serial_port_t* port);

platform_serial_EXPORT const char* serial_port_get_path(const serial_port_t* port);
platform_serial_EXPORT bool serial_port_is_open(const serial_port_t* port);

platform_serial_EXPORT int32_t serial_port_read(serial_port_t* port,
                                               uint8_t* buffer,
                                               size_t length,
                                               size_t* bytes_read);
platform_serial_EXPORT int32_t serial_port_read_with_timeout(serial_port_t* port,
                                                            uint8_t* buffer,
                                                            size_t length,
                                                            int32_t timeout_ms,
                                                            size_t* bytes_read);
platform_serial_EXPORT int32_t serial_port_write(serial_port_t* port,
                                                const uint8_t* buffer,
                                                size_t length,
                                                size_t* bytes_written);
platform_serial_EXPORT int32_t serial_port_write_with_timeout(
    serial_port_t* port,
    const uint8_t* buffer,
    size_t length,
    int32_t timeout_ms,
    size_t* bytes_written);

platform_serial_EXPORT int32_t serial_port_bytes_available(serial_port_t* port,
                                                          int32_t* bytes_available);
platform_serial_EXPORT int32_t serial_port_flush(serial_port_t* port);
platform_serial_EXPORT int32_t serial_port_reset_buffers(serial_port_t* port);

platform_serial_EXPORT int32_t serial_port_get_control_signals(
    serial_port_t* port,
    uint32_t* signal_mask);
platform_serial_EXPORT int32_t serial_port_set_control_signals(
    serial_port_t* port,
    uint32_t set_mask,
    uint32_t clear_mask);

platform_serial_EXPORT int32_t serial_port_get_last_error(
    const serial_port_t* port);
platform_serial_EXPORT const serial_port_config_t* serial_port_get_config(
    const serial_port_t* port);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // platform_serial_LINUX_SERIAL_PORT_H_
