#include "serial_port_manager.h"

#include <setupapi.h>
#include <windows.h>

#include <algorithm>
#include <cwctype>
#include <map>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace {

class ScopedDeviceInfoSet final {
 public:
  explicit ScopedDeviceInfoSet(HDEVINFO handle) : handle_(handle) {}
  ~ScopedDeviceInfoSet() {
    if (handle_ != INVALID_HANDLE_VALUE) {
      SetupDiDestroyDeviceInfoList(handle_);
    }
  }

  HDEVINFO get() const { return handle_; }

 private:
  HDEVINFO handle_ = INVALID_HANDLE_VALUE;
};

class ScopedRegistryKey final {
 public:
  explicit ScopedRegistryKey(HKEY key) : key_(key) {}
  ~ScopedRegistryKey() {
    if (key_ != nullptr && key_ != INVALID_HANDLE_VALUE) {
      RegCloseKey(key_);
    }
  }

  HKEY get() const { return key_; }

 private:
  HKEY key_ = nullptr;
};

std::wstring TrimNullTerminator(const std::wstring& value) {
  const size_t end = value.find(L'\0');
  if (end == std::wstring::npos) {
    return value;
  }
  return value.substr(0, end);
}

std::wstring ReadRegistryStringValue(HKEY key, const wchar_t* value_name) {
  DWORD type = 0;
  DWORD bytes = 0;
  if (RegQueryValueExW(key, value_name, nullptr, &type, nullptr, &bytes) !=
          ERROR_SUCCESS ||
      type != REG_SZ || bytes == 0) {
    return {};
  }

  std::wstring result(bytes / sizeof(wchar_t), L'\0');
  if (RegQueryValueExW(key, value_name, nullptr, nullptr,
                       reinterpret_cast<LPBYTE>(result.data()),
                       &bytes) != ERROR_SUCCESS) {
    return {};
  }

  return TrimNullTerminator(result);
}

std::wstring GetDevicePropertyString(HDEVINFO device_info_set,
                                     SP_DEVINFO_DATA* device_info_data,
                                     DWORD property) {
  DWORD type = 0;
  DWORD bytes = 0;
  SetupDiGetDeviceRegistryPropertyW(device_info_set, device_info_data, property,
                                    &type, nullptr, 0, &bytes);
  if (bytes == 0 || (type != REG_SZ && type != REG_MULTI_SZ)) {
    return {};
  }

  std::wstring buffer(bytes / sizeof(wchar_t), L'\0');
  if (!SetupDiGetDeviceRegistryPropertyW(
          device_info_set, device_info_data, property, &type,
          reinterpret_cast<PBYTE>(buffer.data()), bytes, nullptr)) {
    return {};
  }

  return TrimNullTerminator(buffer);
}

std::wstring GetDeviceInstanceId(HDEVINFO device_info_set,
                                 SP_DEVINFO_DATA* device_info_data) {
  DWORD required = 0;
  SetupDiGetDeviceInstanceIdW(device_info_set, device_info_data, nullptr, 0,
                              &required);
  if (required == 0) {
    return {};
  }

  std::wstring buffer(required, L'\0');
  if (!SetupDiGetDeviceInstanceIdW(device_info_set, device_info_data,
                                   buffer.data(), required, nullptr)) {
    return {};
  }

  return TrimNullTerminator(buffer);
}

std::wstring ToUpper(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](wchar_t character) {
                   return static_cast<wchar_t>(std::towupper(character));
                 });
  return value;
}

void ExtractUsbIdentifiers(const std::wstring& source,
                           std::wstring* vendor_id,
                           std::wstring* product_id,
                           std::wstring* serial_number) {
  const std::wstring upper = ToUpper(source);

  const size_t vid_index = upper.find(L"VID_");
  if (vid_index != std::wstring::npos && vendor_id != nullptr &&
      vid_index + 8 <= source.size()) {
    *vendor_id = source.substr(vid_index + 4, 4);
  }

  const size_t pid_index = upper.find(L"PID_");
  if (pid_index != std::wstring::npos && product_id != nullptr &&
      pid_index + 8 <= source.size()) {
    *product_id = source.substr(pid_index + 4, 4);
  }

  const size_t slash_index = source.find_last_of(L'\\');
  if (slash_index != std::wstring::npos && serial_number != nullptr &&
      slash_index + 1 < source.size()) {
    *serial_number = source.substr(slash_index + 1);
  }
}

std::map<std::wstring, SerialPortInfo> ReadRegistryPorts() {
  std::map<std::wstring, SerialPortInfo> ports;

  HKEY raw_key = nullptr;
  if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"HARDWARE\\DEVICEMAP\\SERIALCOMM", 0,
                    KEY_READ, &raw_key) != ERROR_SUCCESS) {
    return ports;
  }

  ScopedRegistryKey key(raw_key);
  DWORD value_count = 0;
  DWORD max_value_name_length = 0;
  DWORD max_value_length = 0;
  if (RegQueryInfoKeyW(key.get(), nullptr, nullptr, nullptr, nullptr, nullptr,
                       nullptr, &value_count, &max_value_name_length,
                       &max_value_length, nullptr, nullptr) != ERROR_SUCCESS) {
    return ports;
  }

  std::wstring value_name(max_value_name_length + 1, L'\0');
  std::wstring value(max_value_length / sizeof(wchar_t) + 1, L'\0');

  for (DWORD index = 0; index < value_count; ++index) {
    DWORD value_name_length = max_value_name_length + 1;
    DWORD value_length = max_value_length;
    DWORD type = 0;
    if (RegEnumValueW(key.get(), index, value_name.data(), &value_name_length,
                      nullptr, &type, reinterpret_cast<LPBYTE>(value.data()),
                      &value_length) != ERROR_SUCCESS ||
        type != REG_SZ) {
      continue;
    }

    const std::wstring port_name =
        TrimNullTerminator(value.substr(0, value_length / sizeof(wchar_t)));
    if (port_name.empty()) {
      continue;
    }

    SerialPortInfo info;
    info.port_name = port_name;
    info.description = L"Serial Port";
    ports[port_name] = info;
  }

  return ports;
}

void MergeSetupApiPort(HDEVINFO device_info_set,
                       SP_DEVINFO_DATA* device_info_data,
                       std::map<std::wstring, SerialPortInfo>* ports) {
  HKEY raw_device_key =
      SetupDiOpenDevRegKey(device_info_set, device_info_data, DICS_FLAG_GLOBAL,
                           0, DIREG_DEV, KEY_READ);
  if (raw_device_key == INVALID_HANDLE_VALUE) {
    return;
  }

  ScopedRegistryKey device_key(raw_device_key);
  const std::wstring port_name = ReadRegistryStringValue(device_key.get(), L"PortName");
  if (port_name.empty() || port_name.rfind(L"LPT", 0) == 0) {
    return;
  }

  SerialPortInfo& info = (*ports)[port_name];
  info.port_name = port_name;

  const std::wstring friendly_name =
      GetDevicePropertyString(device_info_set, device_info_data, SPDRP_FRIENDLYNAME);
  const std::wstring description =
      GetDevicePropertyString(device_info_set, device_info_data, SPDRP_DEVICEDESC);
  const std::wstring hardware_id =
      GetDevicePropertyString(device_info_set, device_info_data, SPDRP_HARDWAREID);
  const std::wstring instance_id =
      GetDeviceInstanceId(device_info_set, device_info_data);

  if (!friendly_name.empty()) {
    info.description = friendly_name;
  } else if (!description.empty()) {
    info.description = description;
  } else if (info.description.empty()) {
    info.description = L"Serial Port";
  }

  ExtractUsbIdentifiers(!hardware_id.empty() ? hardware_id : instance_id,
                        &info.vendor_id, &info.product_id, &info.serial_number);
}

void EnumerateSetupApiPorts(std::map<std::wstring, SerialPortInfo>* ports) {
  DWORD required_guids = 0;
  SetupDiClassGuidsFromNameW(L"Ports", nullptr, 0, &required_guids);
  if (required_guids == 0) {
    return;
  }

  std::vector<GUID> guids(required_guids);
  if (!SetupDiClassGuidsFromNameW(L"Ports", guids.data(), required_guids,
                                  &required_guids)) {
    return;
  }

  for (const GUID& guid : guids) {
    ScopedDeviceInfoSet device_info_set(
        SetupDiGetClassDevsW(&guid, nullptr, nullptr, DIGCF_PRESENT));
    if (device_info_set.get() == INVALID_HANDLE_VALUE) {
      continue;
    }

    DWORD index = 0;
    while (true) {
      SP_DEVINFO_DATA device_info_data = {};
      device_info_data.cbSize = sizeof(SP_DEVINFO_DATA);
      if (!SetupDiEnumDeviceInfo(device_info_set.get(), index, &device_info_data)) {
        break;
      }

      MergeSetupApiPort(device_info_set.get(), &device_info_data, ports);
      ++index;
    }
  }
}

}  // namespace

SerialPortManager& SerialPortManager::GetInstance() {
  static SerialPortManager manager;
  return manager;
}

std::vector<SerialPortInfo> SerialPortManager::EnumeratePorts(WindowsError* error) {
  std::map<std::wstring, SerialPortInfo> merged_ports = ReadRegistryPorts();
  EnumerateSetupApiPorts(&merged_ports);

  {
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto& [_, info] : merged_ports) {
      info.is_open = std::any_of(
          ports_.begin(), ports_.end(),
          [&info](const auto& entry) {
            return entry.second != nullptr &&
                   entry.second->port_name() == info.port_name &&
                   entry.second->IsOpen();
          });
    }
  }

  std::vector<SerialPortInfo> ports;
  ports.reserve(merged_ports.size());
  for (auto& [_, info] : merged_ports) {
    ports.push_back(std::move(info));
  }

  if (error != nullptr) {
    error->Set(ERROR_SUCCESS, {});
  }
  return ports;
}

bool SerialPortManager::OpenPort(const std::wstring& port_name,
                                 const SerialPortConfig& config,
                                 int64_t* port_id,
                                 WindowsError* error) {
  if (port_name.empty() || port_id == nullptr) {
    if (error != nullptr) {
      error->Set(ERROR_INVALID_PARAMETER,
                 "A port name and output port identifier are required.");
    }
    return false;
  }

  auto port = std::make_shared<SerialPort>(port_name);
  if (!port->Open(config, error)) {
    return false;
  }

  std::lock_guard<std::mutex> lock(mutex_);
  const bool already_open = std::any_of(
      ports_.begin(), ports_.end(),
      [&port_name](const auto& entry) {
        return entry.second != nullptr && entry.second->port_name() == port_name &&
               entry.second->IsOpen();
      });

  if (already_open) {
    WindowsError close_error;
    port->Close(&close_error);
    if (error != nullptr) {
      error->Set(ERROR_ALREADY_EXISTS,
                 "The requested serial port is already open in this process.");
    }
    return false;
  }

  const int64_t id = next_port_id_++;
  ports_[id] = port;
  *port_id = id;
  return true;
}

bool SerialPortManager::ClosePort(int64_t port_id, WindowsError* error) {
  std::shared_ptr<SerialPort> port;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    auto iterator = ports_.find(port_id);
    if (iterator == ports_.end()) {
      if (error != nullptr) {
        error->Set(ERROR_FILE_NOT_FOUND, "Unknown serial port identifier.");
      }
      return false;
    }

    port = iterator->second;
    ports_.erase(iterator);
  }

  return port->Close(error);
}

bool SerialPortManager::ReadPort(int64_t port_id,
                                 uint8_t* buffer,
                                 int32_t buffer_length,
                                 int32_t* bytes_read,
                                 WindowsError* error) {
  const auto port = GetPort(port_id, error);
  return port != nullptr &&
         port->Read(buffer, buffer_length, bytes_read, error);
}

bool SerialPortManager::WritePort(int64_t port_id,
                                  const uint8_t* buffer,
                                  int32_t buffer_length,
                                  int32_t* bytes_written,
                                  WindowsError* error) {
  const auto port = GetPort(port_id, error);
  return port != nullptr &&
         port->Write(buffer, buffer_length, bytes_written, error);
}

bool SerialPortManager::BytesAvailable(int64_t port_id,
                                       int32_t* bytes_available,
                                       WindowsError* error) {
  const auto port = GetPort(port_id, error);
  return port != nullptr && port->BytesAvailable(bytes_available, error);
}

bool SerialPortManager::FlushPort(int64_t port_id, WindowsError* error) {
  const auto port = GetPort(port_id, error);
  return port != nullptr && port->Flush(error);
}

bool SerialPortManager::ResetPortBuffers(int64_t port_id, WindowsError* error) {
  const auto port = GetPort(port_id, error);
  return port != nullptr && port->ResetBuffers(error);
}

bool SerialPortManager::GetControlSignals(int64_t port_id,
                                           uint32_t* signal_mask,
                                           WindowsError* error) {
  const auto port = GetPort(port_id, error);
  return port != nullptr && port->GetControlSignals(signal_mask, error);
}

bool SerialPortManager::SetDtr(int64_t port_id,
                               bool enabled,
                               WindowsError* error) {
  const auto port = GetPort(port_id, error);
  return port != nullptr && port->SetDtr(enabled, error);
}

bool SerialPortManager::SetRts(int64_t port_id,
                               bool enabled,
                               WindowsError* error) {
  const auto port = GetPort(port_id, error);
  return port != nullptr && port->SetRts(enabled, error);
}

std::shared_ptr<SerialPort> SerialPortManager::GetPort(int64_t port_id,
                                                       WindowsError* error) {
  std::lock_guard<std::mutex> lock(mutex_);
  const auto iterator = ports_.find(port_id);
  if (iterator == ports_.end()) {
    if (error != nullptr) {
      error->Set(ERROR_FILE_NOT_FOUND, "Unknown serial port identifier.");
    }
    return nullptr;
  }
  return iterator->second;
}
