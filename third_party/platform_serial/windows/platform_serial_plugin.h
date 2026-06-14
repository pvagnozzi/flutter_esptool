#ifndef FLUTTER_PLUGIN_platform_serial_PLUGIN_H_
#define FLUTTER_PLUGIN_platform_serial_PLUGIN_H_

#include <stdint.h>

#if defined(_WIN32)
#define platform_serial_EXPORT __declspec(dllexport)
#else
#define platform_serial_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Status codes returned by the exported FFI functions.
enum FlutterSerialStatus : int32_t {
  kFlutterSerialSuccess = 0,
  kFlutterSerialInvalidArgument = 1,
  kFlutterSerialPortNotFound = 2,
  kFlutterSerialPortAlreadyOpen = 3,
  kFlutterSerialIoError = 4,
  kFlutterSerialTimeout = 5,
};

// Enumerates available serial ports and returns a UTF-8 encoded JSON payload.
platform_serial_EXPORT int32_t platform_serial_get_ports(
    char** ports_json,
    uint32_t* error_code,
    char** error_message);

// Opens a serial port and returns an opaque port identifier to use in
// subsequent calls.
platform_serial_EXPORT int32_t platform_serial_open_port(
    const wchar_t* port_name,
    int32_t baud_rate,
    int32_t data_bits,
    int32_t stop_bits,
    int32_t parity,
    int32_t flow_control,
    int32_t read_timeout_ms,
    int32_t write_timeout_ms,
    int64_t* port_id,
    uint32_t* error_code,
    char** error_message);

// Closes a previously opened serial port.
platform_serial_EXPORT int32_t platform_serial_close_port(
    int64_t port_id,
    uint32_t* error_code,
    char** error_message);

// Reads up to buffer_length bytes from the serial port into buffer.
platform_serial_EXPORT int32_t platform_serial_read_port(
    int64_t port_id,
    uint8_t* buffer,
    int32_t buffer_length,
    int32_t* bytes_read,
    uint32_t* error_code,
    char** error_message);

// Writes buffer_length bytes from buffer to the serial port.
platform_serial_EXPORT int32_t platform_serial_write_port(
    int64_t port_id,
    const uint8_t* buffer,
    int32_t buffer_length,
    int32_t* bytes_written,
    uint32_t* error_code,
    char** error_message);

// Returns the number of bytes currently waiting in the receive queue.
platform_serial_EXPORT int32_t platform_serial_bytes_available(
    int64_t port_id,
    int32_t* bytes_available,
    uint32_t* error_code,
    char** error_message);

// Flushes the serial port output buffers.
platform_serial_EXPORT int32_t platform_serial_flush_port(
    int64_t port_id,
    uint32_t* error_code,
    char** error_message);

// Purges input and output buffers for the serial port.
platform_serial_EXPORT int32_t platform_serial_reset_port_buffers(
    int64_t port_id,
    uint32_t* error_code,
    char** error_message);

// Returns a bit mask containing RTS, CTS, DTR, DSR, and DCD signal states.
platform_serial_EXPORT int32_t platform_serial_get_control_signals(
    int64_t port_id,
    uint32_t* signal_mask,
    uint32_t* error_code,
    char** error_message);

// Sets the DTR line state for the serial port.
platform_serial_EXPORT int32_t platform_serial_set_dtr(
    int64_t port_id,
    int32_t enabled,
    uint32_t* error_code,
    char** error_message);

// Sets the RTS line state for the serial port.
platform_serial_EXPORT int32_t platform_serial_set_rts(
    int64_t port_id,
    int32_t enabled,
    uint32_t* error_code,
    char** error_message);

// Releases UTF-8 strings allocated by this library.
platform_serial_EXPORT void platform_serial_free_string(char* value);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_platform_serial_PLUGIN_H_
