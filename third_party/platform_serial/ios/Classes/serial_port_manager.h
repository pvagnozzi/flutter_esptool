#ifndef platform_serial_IOS_SERIAL_PORT_MANAGER_H_
#define platform_serial_IOS_SERIAL_PORT_MANAGER_H_

#include <stdint.h>

#if defined(__cplusplus)
extern "C" {
#endif

typedef enum platform_serial_parity_t {
  platform_serial_PARITY_NONE = 0,
  platform_serial_PARITY_EVEN = 1,
  platform_serial_PARITY_ODD = 2,
  platform_serial_PARITY_MARK = 3,
  platform_serial_PARITY_SPACE = 4,
} platform_serial_parity_t;

typedef enum platform_serial_stop_bits_t {
  platform_serial_STOP_BITS_ONE = 0,
  platform_serial_STOP_BITS_ONE_POINT_FIVE = 1,
  platform_serial_STOP_BITS_TWO = 2,
} platform_serial_stop_bits_t;

typedef enum platform_serial_flow_control_t {
  platform_serial_FLOW_CONTROL_NONE = 0,
  platform_serial_FLOW_CONTROL_RTSCTS = 1,
  platform_serial_FLOW_CONTROL_XONXOFF = 2,
} platform_serial_flow_control_t;

typedef struct platform_serial_port_snapshot_t {
  const char *port_name;
  const char *description;
  const char *vendor_id;
  const char *product_id;
  const char *serial_number;
  uint8_t is_open;
} platform_serial_port_snapshot_t;

// Reserved for future FFI entry points. The current iOS implementation is
// MethodChannel-based, but this header intentionally stabilizes the data types
// that a C bridge can expose later without breaking callers.

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // platform_serial_IOS_SERIAL_PORT_MANAGER_H_
