#pragma once

#include <stdint.h>

#if defined(__cplusplus)
#define platform_serial_EXTERN extern "C"
#else
#define platform_serial_EXTERN extern
#endif

#if defined(__GNUC__)
#define platform_serial_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#else
#define platform_serial_EXPORT
#endif

/// Parity values expected by the native layer.
///
/// These values intentionally mirror the Dart [SerialParity] enum indexes.
typedef enum serial_parity_t {
  SERIAL_PARITY_NONE = 0,
  SERIAL_PARITY_EVEN = 1,
  SERIAL_PARITY_ODD = 2,
  SERIAL_PARITY_MARK = 3,
  SERIAL_PARITY_SPACE = 4,
} serial_parity_t;

/// Stop-bit values expected by the native layer.
///
/// These values intentionally mirror the Dart [SerialStopBits] enum indexes.
typedef enum serial_stop_bits_t {
  SERIAL_STOP_BITS_ONE = 0,
  SERIAL_STOP_BITS_ONE_POINT_FIVE = 1,
  SERIAL_STOP_BITS_TWO = 2,
} serial_stop_bits_t;

/// Flow-control values expected by the native layer.
///
/// These values intentionally mirror the Dart [SerialFlowControl] enum indexes.
typedef enum serial_flow_control_t {
  SERIAL_FLOW_CONTROL_NONE = 0,
  SERIAL_FLOW_CONTROL_RTSCTS = 1,
  SERIAL_FLOW_CONTROL_XONXOFF = 2,
} serial_flow_control_t;

/// Returns the available serial ports as a UTF-8 encoded JSON string.
///
/// The JSON payload is an array of objects containing:
/// - portName
/// - description
/// - vendorId
/// - productId
/// - serialNumber
/// - isOpen
/// - platform
///
/// The caller owns the returned buffer and must release it with
/// [serial_free_memory].
///
/// Returns 0 on success or a negative macOS/POSIX error code on failure.
platform_serial_EXTERN platform_serial_EXPORT int32_t
serial_get_available_ports_json(char **json_out);

/// Opens and configures a serial port.
///
/// The returned value is an opaque handle represented as an intptr_t.
/// Returns 0 on failure; detailed information can be retrieved through
/// [serial_get_last_error_code] and [serial_copy_last_error_message].
platform_serial_EXTERN platform_serial_EXPORT intptr_t serial_open_port(
    const char *port_name,
    int32_t baud_rate,
    int32_t data_bits,
    int32_t stop_bits,
    int32_t parity,
    int32_t flow_control,
    int32_t read_timeout_ms,
    int32_t write_timeout_ms);

/// Closes a previously opened serial port handle.
///
/// Returns 0 on success or a negative macOS/POSIX error code on failure.
platform_serial_EXTERN platform_serial_EXPORT int32_t
serial_close_port(intptr_t handle);

/// Reads up to [length] bytes into [buffer].
///
/// The port is configured for non-blocking I/O; this call waits for readiness
/// using kqueue/select according to [timeout_ms]. A negative [timeout_ms]
/// applies the timeout stored at open time.
///
/// Returns the number of bytes read, 0 on timeout/no data, or a negative
/// macOS/POSIX error code on failure.
platform_serial_EXTERN platform_serial_EXPORT int32_t
serial_read(intptr_t handle, uint8_t *buffer, int32_t length, int32_t timeout_ms);

/// Writes up to [length] bytes from [buffer].
///
/// The port is configured for non-blocking I/O; this call waits for write
/// readiness with select according to [timeout_ms]. A negative [timeout_ms]
/// applies the timeout stored at open time.
///
/// Returns the number of bytes written, 0 on timeout, or a negative
/// macOS/POSIX error code on failure.
platform_serial_EXTERN platform_serial_EXPORT int32_t serial_write(
    intptr_t handle,
    const uint8_t *buffer,
    int32_t length,
    int32_t timeout_ms);

/// Returns the number of bytes currently buffered by the kernel for reading.
///
/// Returns the available byte count or a negative macOS/POSIX error code.
platform_serial_EXTERN platform_serial_EXPORT int32_t
serial_bytes_available(intptr_t handle);

/// Waits until the file descriptor is readable.
///
/// Returns 1 when readable, 0 on timeout, or a negative macOS/POSIX error code.
platform_serial_EXTERN platform_serial_EXPORT int32_t
serial_wait_readable(intptr_t handle, int32_t timeout_ms);

/// Drains the outgoing buffer.
///
/// Returns 0 on success or a negative macOS/POSIX error code on failure.
platform_serial_EXTERN platform_serial_EXPORT int32_t
serial_flush(intptr_t handle);

/// Flushes both input and output buffers.
///
/// Returns 0 on success or a negative macOS/POSIX error code on failure.
platform_serial_EXTERN platform_serial_EXPORT int32_t
serial_reset_buffers(intptr_t handle);

/// Returns the most recent error code for the current thread.
platform_serial_EXTERN platform_serial_EXPORT int32_t
serial_get_last_error_code(void);

/// Returns a heap-allocated UTF-8 copy of the most recent error message.
///
/// The caller owns the returned buffer and must release it with
/// [serial_free_memory].
platform_serial_EXTERN platform_serial_EXPORT char *
serial_copy_last_error_message(void);

/// Releases memory previously returned by this API.
platform_serial_EXTERN platform_serial_EXPORT void
serial_free_memory(void *memory);
