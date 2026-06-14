#ifndef FLUTTER_PLUGIN_SERIAL_PORT_MANAGER_H_
#define FLUTTER_PLUGIN_SERIAL_PORT_MANAGER_H_

#include <stdint.h>

#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "serial_port.h"

struct SerialPortInfo {
  std::wstring port_name;
  std::wstring description;
  std::wstring vendor_id;
  std::wstring product_id;
  std::wstring serial_number;
  bool is_open = false;
};

// Central manager that owns all native serial port instances and exposes
// thread-safe lookup operations for the FFI entry points.
class SerialPortManager final {
 public:
  static SerialPortManager& GetInstance();

  std::vector<SerialPortInfo> EnumeratePorts(WindowsError* error);

  bool OpenPort(const std::wstring& port_name,
                const SerialPortConfig& config,
                int64_t* port_id,
                WindowsError* error);
  bool ClosePort(int64_t port_id, WindowsError* error);
  bool ReadPort(int64_t port_id,
                uint8_t* buffer,
                int32_t buffer_length,
                int32_t* bytes_read,
                WindowsError* error);
  bool WritePort(int64_t port_id,
                 const uint8_t* buffer,
                 int32_t buffer_length,
                 int32_t* bytes_written,
                 WindowsError* error);
  bool BytesAvailable(int64_t port_id,
                      int32_t* bytes_available,
                      WindowsError* error);
  bool FlushPort(int64_t port_id, WindowsError* error);
  bool ResetPortBuffers(int64_t port_id, WindowsError* error);
  bool GetControlSignals(int64_t port_id,
                         uint32_t* signal_mask,
                         WindowsError* error);
  bool SetDtr(int64_t port_id, bool enabled, WindowsError* error);
  bool SetRts(int64_t port_id, bool enabled, WindowsError* error);

 private:
  SerialPortManager() = default;

  std::shared_ptr<SerialPort> GetPort(int64_t port_id, WindowsError* error);

  std::mutex mutex_;
  std::unordered_map<int64_t, std::shared_ptr<SerialPort>> ports_;
  int64_t next_port_id_ = 1;
};

#endif  // FLUTTER_PLUGIN_SERIAL_PORT_MANAGER_H_
