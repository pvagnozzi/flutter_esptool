#include "platform_serial_plugin.h"

#include <windows.h>

#include <cstring>
#include <cstdlib>
#include <iomanip>
#include <sstream>
#include <string>
#include <vector>

#include "serial_port_manager.h"

namespace {

char* AllocateUtf8String(const std::string& value) {
  char* buffer =
      static_cast<char*>(std::malloc((value.size() + 1) * sizeof(char)));
  if (buffer == nullptr) {
    return nullptr;
  }

  std::memcpy(buffer, value.c_str(), value.size() + 1);
  return buffer;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return {};
  }

  const int length = WideCharToMultiByte(
      CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), nullptr, 0,
      nullptr, nullptr);
  std::string result(length, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()),
                      result.data(), length, nullptr, nullptr);
  return result;
}

std::string EscapeJsonString(const std::wstring& value) {
  std::ostringstream stream;
  for (const wchar_t character : value) {
    switch (character) {
      case L'\\':
        stream << "\\\\";
        break;
      case L'"':
        stream << "\\\"";
        break;
      case L'\b':
        stream << "\\b";
        break;
      case L'\f':
        stream << "\\f";
        break;
      case L'\n':
        stream << "\\n";
        break;
      case L'\r':
        stream << "\\r";
        break;
      case L'\t':
        stream << "\\t";
        break;
      default:
        if (character < 0x20) {
          stream << "\\u" << std::uppercase << std::hex << std::setw(4)
                 << std::setfill('0') << static_cast<int>(character)
                 << std::nouppercase << std::dec << std::setfill(' ');
        } else {
          stream << WideToUtf8(std::wstring(1, character));
        }
        break;
    }
  }
  return stream.str();
}

std::string SerializePortsJson(const std::vector<SerialPortInfo>& ports) {
  std::ostringstream stream;
  stream << '[';
  for (size_t index = 0; index < ports.size(); ++index) {
    const SerialPortInfo& port = ports[index];
    if (index > 0) {
      stream << ',';
    }

    stream << '{'
           << "\"portName\":\"" << EscapeJsonString(port.port_name) << "\","
           << "\"description\":\"" << EscapeJsonString(port.description)
           << "\",";

    if (!port.vendor_id.empty()) {
      stream << "\"vendorId\":\"" << EscapeJsonString(port.vendor_id) << "\",";
    } else {
      stream << "\"vendorId\":null,";
    }

    if (!port.product_id.empty()) {
      stream << "\"productId\":\"" << EscapeJsonString(port.product_id)
             << "\",";
    } else {
      stream << "\"productId\":null,";
    }

    if (!port.serial_number.empty()) {
      stream << "\"serialNumber\":\"" << EscapeJsonString(port.serial_number)
             << "\",";
    } else {
      stream << "\"serialNumber\":null,";
    }

    stream << "\"isOpen\":" << (port.is_open ? "true" : "false") << ','
           << "\"platform\":\"windows\""
           << '}';
  }
  stream << ']';
  return stream.str();
}

int32_t StatusFromErrorCode(uint32_t error_code) {
  switch (error_code) {
    case ERROR_SUCCESS:
      return kFlutterSerialSuccess;
    case ERROR_INVALID_PARAMETER:
      return kFlutterSerialInvalidArgument;
    case ERROR_FILE_NOT_FOUND:
    case ERROR_PATH_NOT_FOUND:
    case ERROR_INVALID_HANDLE:
      return kFlutterSerialPortNotFound;
    case ERROR_ALREADY_EXISTS:
    case ERROR_ALREADY_ASSIGNED:
    case ERROR_ACCESS_DENIED:
      return kFlutterSerialPortAlreadyOpen;
    case WAIT_TIMEOUT:
      return kFlutterSerialTimeout;
    default:
      return kFlutterSerialIoError;
  }
}

int32_t WriteError(const WindowsError& error,
                   uint32_t* error_code,
                   char** error_message) {
  if (error_code != nullptr) {
    *error_code = error.code;
  }
  if (error_message != nullptr) {
    *error_message = AllocateUtf8String(error.message);
  }
  return StatusFromErrorCode(error.code);
}

int32_t WriteSuccess(uint32_t* error_code, char** error_message) {
  if (error_code != nullptr) {
    *error_code = ERROR_SUCCESS;
  }
  if (error_message != nullptr) {
    *error_message = nullptr;
  }
  return kFlutterSerialSuccess;
}

}  // namespace

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID reserved) {
  (void)module;
  (void)reason;
  (void)reserved;
  return TRUE;
}

int32_t platform_serial_get_ports(char** ports_json,
                                 uint32_t* error_code,
                                 char** error_message) {
  if (ports_json == nullptr) {
    WindowsError error;
    error.Set(ERROR_INVALID_PARAMETER,
              "An output pointer for the port list is required.");
    return WriteError(error, error_code, error_message);
  }

  *ports_json = nullptr;
  if (error_message != nullptr) {
    *error_message = nullptr;
  }

  WindowsError error;
  const std::vector<SerialPortInfo> ports =
      SerialPortManager::GetInstance().EnumeratePorts(&error);
  if (error.code != ERROR_SUCCESS) {
    return WriteError(error, error_code, error_message);
  }

  *ports_json = AllocateUtf8String(SerializePortsJson(ports));
  if (*ports_json == nullptr) {
    error.Set(ERROR_OUTOFMEMORY, "Unable to allocate memory for port list.");
    return WriteError(error, error_code, error_message);
  }

  return WriteSuccess(error_code, error_message);
}

int32_t platform_serial_open_port(const wchar_t* port_name,
                                 int32_t baud_rate,
                                 int32_t data_bits,
                                 int32_t stop_bits,
                                 int32_t parity,
                                 int32_t flow_control,
                                 int32_t read_timeout_ms,
                                 int32_t write_timeout_ms,
                                 int64_t* port_id,
                                 uint32_t* error_code,
                                 char** error_message) {
  if (port_name == nullptr || port_id == nullptr) {
    WindowsError error;
    error.Set(ERROR_INVALID_PARAMETER,
              "A port name and output port identifier are required.");
    return WriteError(error, error_code, error_message);
  }

  SerialPortConfig config;
  config.baud_rate = baud_rate;
  config.data_bits = data_bits;
  config.stop_bits = stop_bits;
  config.parity = parity;
  config.flow_control = flow_control;
  config.read_timeout_ms = read_timeout_ms;
  config.write_timeout_ms = write_timeout_ms;

  WindowsError error;
  if (!SerialPortManager::GetInstance().OpenPort(port_name, config, port_id,
                                                 &error)) {
    return WriteError(error, error_code, error_message);
  }

  return WriteSuccess(error_code, error_message);
}

int32_t platform_serial_close_port(int64_t port_id,
                                  uint32_t* error_code,
                                  char** error_message) {
  WindowsError error;
  if (!SerialPortManager::GetInstance().ClosePort(port_id, &error)) {
    return WriteError(error, error_code, error_message);
  }

  return WriteSuccess(error_code, error_message);
}

int32_t platform_serial_read_port(int64_t port_id,
                                 uint8_t* buffer,
                                 int32_t buffer_length,
                                 int32_t* bytes_read,
                                 uint32_t* error_code,
                                 char** error_message) {
  if (bytes_read == nullptr) {
    WindowsError error;
    error.Set(ERROR_INVALID_PARAMETER,
              "An output counter for bytes read is required.");
    return WriteError(error, error_code, error_message);
  }

  *bytes_read = 0;
  WindowsError error;
  if (!SerialPortManager::GetInstance().ReadPort(port_id, buffer, buffer_length,
                                                 bytes_read, &error)) {
    return WriteError(error, error_code, error_message);
  }

  return WriteSuccess(error_code, error_message);
}

int32_t platform_serial_write_port(int64_t port_id,
                                  const uint8_t* buffer,
                                  int32_t buffer_length,
                                  int32_t* bytes_written,
                                  uint32_t* error_code,
                                  char** error_message) {
  if (bytes_written == nullptr) {
    WindowsError error;
    error.Set(ERROR_INVALID_PARAMETER,
              "An output counter for bytes written is required.");
    return WriteError(error, error_code, error_message);
  }

  *bytes_written = 0;
  WindowsError error;
  if (!SerialPortManager::GetInstance().WritePort(
          port_id, buffer, buffer_length, bytes_written, &error)) {
    return WriteError(error, error_code, error_message);
  }

  return WriteSuccess(error_code, error_message);
}

int32_t platform_serial_bytes_available(int64_t port_id,
                                       int32_t* bytes_available,
                                       uint32_t* error_code,
                                       char** error_message) {
  if (bytes_available == nullptr) {
    WindowsError error;
    error.Set(ERROR_INVALID_PARAMETER,
              "An output counter for available bytes is required.");
    return WriteError(error, error_code, error_message);
  }

  *bytes_available = 0;
  WindowsError error;
  if (!SerialPortManager::GetInstance().BytesAvailable(port_id, bytes_available,
                                                       &error)) {
    return WriteError(error, error_code, error_message);
  }

  return WriteSuccess(error_code, error_message);
}

int32_t platform_serial_flush_port(int64_t port_id,
                                  uint32_t* error_code,
                                  char** error_message) {
  WindowsError error;
  if (!SerialPortManager::GetInstance().FlushPort(port_id, &error)) {
    return WriteError(error, error_code, error_message);
  }

  return WriteSuccess(error_code, error_message);
}

int32_t platform_serial_reset_port_buffers(int64_t port_id,
                                          uint32_t* error_code,
                                          char** error_message) {
  WindowsError error;
  if (!SerialPortManager::GetInstance().ResetPortBuffers(port_id, &error)) {
    return WriteError(error, error_code, error_message);
  }

  return WriteSuccess(error_code, error_message);
}

int32_t platform_serial_get_control_signals(int64_t port_id,
                                            uint32_t* signal_mask,
                                            uint32_t* error_code,
                                            char** error_message) {
  if (signal_mask == nullptr) {
    WindowsError error;
    error.Set(ERROR_INVALID_PARAMETER,
              "An output signal mask pointer is required.");
    return WriteError(error, error_code, error_message);
  }

  *signal_mask = 0;
  WindowsError error;
  if (!SerialPortManager::GetInstance().GetControlSignals(port_id, signal_mask,
                                                          &error)) {
    return WriteError(error, error_code, error_message);
  }

  return WriteSuccess(error_code, error_message);
}

int32_t platform_serial_set_dtr(int64_t port_id,
                               int32_t enabled,
                               uint32_t* error_code,
                               char** error_message) {
  WindowsError error;
  if (!SerialPortManager::GetInstance().SetDtr(port_id, enabled != 0, &error)) {
    return WriteError(error, error_code, error_message);
  }

  return WriteSuccess(error_code, error_message);
}

int32_t platform_serial_set_rts(int64_t port_id,
                               int32_t enabled,
                               uint32_t* error_code,
                               char** error_message) {
  WindowsError error;
  if (!SerialPortManager::GetInstance().SetRts(port_id, enabled != 0, &error)) {
    return WriteError(error, error_code, error_message);
  }

  return WriteSuccess(error_code, error_message);
}

void platform_serial_free_string(char* value) {
  std::free(value);
}
