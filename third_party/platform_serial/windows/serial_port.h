#ifndef FLUTTER_PLUGIN_SERIAL_PORT_H_
#define FLUTTER_PLUGIN_SERIAL_PORT_H_

#include <stdint.h>
#include <windows.h>

#include <mutex>
#include <string>

struct SerialPortConfig {
  int32_t baud_rate = 9600;
  int32_t data_bits = 8;
  int32_t stop_bits = 0;
  int32_t parity = 0;
  int32_t flow_control = 0;
  int32_t read_timeout_ms = 5000;
  int32_t write_timeout_ms = 5000;
};

struct WindowsError {
  uint32_t code = ERROR_SUCCESS;
  std::string message;

  void Set(uint32_t new_code, std::string new_message);
};

// Thread-safe RAII wrapper around a Windows serial port handle.
class SerialPort final {
 public:
  explicit SerialPort(std::wstring port_name);
  ~SerialPort();

  SerialPort(const SerialPort&) = delete;
  SerialPort& operator=(const SerialPort&) = delete;

  bool Open(const SerialPortConfig& config, WindowsError* error);
  bool Close(WindowsError* error);
  bool Read(uint8_t* buffer,
            int32_t buffer_length,
            int32_t* bytes_read,
            WindowsError* error);
  bool Write(const uint8_t* buffer,
             int32_t buffer_length,
             int32_t* bytes_written,
             WindowsError* error);
  bool BytesAvailable(int32_t* bytes_available, WindowsError* error);
  bool Flush(WindowsError* error);
  bool ResetBuffers(WindowsError* error);
  bool GetControlSignals(uint32_t* signal_mask, WindowsError* error);
  bool SetDtr(bool enabled, WindowsError* error);
  bool SetRts(bool enabled, WindowsError* error);
  bool IsOpen() const;

  const std::wstring& port_name() const { return port_name_; }

 private:
  bool ApplyConfiguration(WindowsError* error);
  bool ApplyTimeouts(WindowsError* error);
  bool EnsureOpen(WindowsError* error) const;
  std::wstring DevicePath() const;
  void CloseUnlocked();

  std::wstring port_name_;
  HANDLE handle_ = INVALID_HANDLE_VALUE;
  SerialPortConfig config_;
  bool dtr_enabled_ = false;
  bool rts_enabled_ = false;
  mutable std::mutex mutex_;
};

#endif  // FLUTTER_PLUGIN_SERIAL_PORT_H_
