#include "serial_port.h"

#include <algorithm>
#include <sstream>
#include <string>
#include <utility>

namespace {

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

std::string FormatWindowsMessage(const std::string& context, DWORD error_code) {
  LPWSTR message_buffer = nullptr;
  const DWORD flags =
      FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
      FORMAT_MESSAGE_IGNORE_INSERTS;
  const DWORD length =
      FormatMessageW(flags, nullptr, error_code, 0,
                     reinterpret_cast<LPWSTR>(&message_buffer), 0, nullptr);

  std::wstring message = length > 0
                             ? std::wstring(message_buffer, length)
                             : L"Unknown Windows error";
  if (message_buffer != nullptr) {
    LocalFree(message_buffer);
  }

  while (!message.empty() &&
         (message.back() == L'\r' || message.back() == L'\n' ||
          message.back() == L' ')) {
    message.pop_back();
  }

  std::ostringstream stream;
  stream << context << " (error " << error_code << "): " << WideToUtf8(message);
  return stream.str();
}

BYTE MapParity(int32_t parity) {
  switch (parity) {
    case 1:
      return EVENPARITY;
    case 2:
      return ODDPARITY;
    case 3:
      return MARKPARITY;
    case 4:
      return SPACEPARITY;
    default:
      return NOPARITY;
  }
}

BYTE MapStopBits(int32_t stop_bits) {
  switch (stop_bits) {
    case 1:
      return ONE5STOPBITS;
    case 2:
      return TWOSTOPBITS;
    default:
      return ONESTOPBIT;
  }
}

}  // namespace

void WindowsError::Set(uint32_t new_code, std::string new_message) {
  code = new_code;
  message = std::move(new_message);
}

SerialPort::SerialPort(std::wstring port_name)
    : port_name_(std::move(port_name)) {}

SerialPort::~SerialPort() {
  std::lock_guard<std::mutex> lock(mutex_);
  CloseUnlocked();
}

bool SerialPort::Open(const SerialPortConfig& config, WindowsError* error) {
  std::lock_guard<std::mutex> lock(mutex_);

  if (handle_ != INVALID_HANDLE_VALUE) {
    if (error != nullptr) {
      error->Set(ERROR_ALREADY_EXISTS,
                 "The serial port is already open in this process.");
    }
    return false;
  }

  config_ = config;

  HANDLE handle = CreateFileW(DevicePath().c_str(), GENERIC_READ | GENERIC_WRITE,
                              0, nullptr, OPEN_EXISTING,
                              FILE_ATTRIBUTE_NORMAL, nullptr);
  if (handle == INVALID_HANDLE_VALUE) {
    const DWORD error_code = GetLastError();
    if (error != nullptr) {
      error->Set(error_code,
                 FormatWindowsMessage("Unable to open serial port", error_code));
    }
    return false;
  }

  handle_ = handle;

  if (!SetupComm(handle_, 4096, 4096)) {
    const DWORD error_code = GetLastError();
    if (error != nullptr) {
      error->Set(error_code,
                 FormatWindowsMessage("Unable to configure serial buffers",
                                      error_code));
    }
    CloseUnlocked();
    return false;
  }

  if (!ApplyConfiguration(error) || !ApplyTimeouts(error)) {
    CloseUnlocked();
    return false;
  }

  PurgeComm(handle_, PURGE_RXABORT | PURGE_RXCLEAR | PURGE_TXABORT |
                         PURGE_TXCLEAR);
  return true;
}

bool SerialPort::Close(WindowsError* error) {
  std::lock_guard<std::mutex> lock(mutex_);

  if (handle_ == INVALID_HANDLE_VALUE) {
    if (error != nullptr) {
      error->Set(ERROR_INVALID_HANDLE, "The serial port is not open.");
    }
    return false;
  }

  CloseUnlocked();
  return true;
}

bool SerialPort::Read(uint8_t* buffer,
                      int32_t buffer_length,
                      int32_t* bytes_read,
                      WindowsError* error) {
  std::lock_guard<std::mutex> lock(mutex_);

  if (buffer == nullptr || bytes_read == nullptr || buffer_length <= 0) {
    if (error != nullptr) {
      error->Set(ERROR_INVALID_PARAMETER,
                 "A valid read buffer and buffer length are required.");
    }
    return false;
  }

  if (!EnsureOpen(error)) {
    return false;
  }

  DWORD read = 0;
  if (!ReadFile(handle_, buffer, static_cast<DWORD>(buffer_length), &read,
                nullptr)) {
    const DWORD error_code = GetLastError();
    if (error != nullptr) {
      error->Set(error_code,
                 FormatWindowsMessage("Unable to read from serial port",
                                      error_code));
    }
    return false;
  }

  if (read == 0 && config_.read_timeout_ms > 0) {
    if (error != nullptr) {
      error->Set(WAIT_TIMEOUT, "Serial port read timed out.");
    }
    return false;
  }

  *bytes_read = static_cast<int32_t>(read);
  return true;
}

bool SerialPort::Write(const uint8_t* buffer,
                       int32_t buffer_length,
                       int32_t* bytes_written,
                       WindowsError* error) {
  std::lock_guard<std::mutex> lock(mutex_);

  if (bytes_written == nullptr || buffer_length < 0 ||
      (buffer == nullptr && buffer_length > 0)) {
    if (error != nullptr) {
      error->Set(ERROR_INVALID_PARAMETER,
                 "A valid write buffer and output counter are required.");
    }
    return false;
  }

  if (!EnsureOpen(error)) {
    return false;
  }

  if (buffer_length == 0) {
    *bytes_written = 0;
    return true;
  }

  DWORD written = 0;
  if (!WriteFile(handle_, buffer, static_cast<DWORD>(buffer_length), &written,
                 nullptr)) {
    const DWORD error_code = GetLastError();
    if (error != nullptr) {
      error->Set(error_code,
                 FormatWindowsMessage("Unable to write to serial port",
                                      error_code));
    }
    return false;
  }

  if (written == 0 && config_.write_timeout_ms > 0) {
    if (error != nullptr) {
      error->Set(WAIT_TIMEOUT, "Serial port write timed out.");
    }
    return false;
  }

  *bytes_written = static_cast<int32_t>(written);
  return true;
}

bool SerialPort::BytesAvailable(int32_t* bytes_available, WindowsError* error) {
  std::lock_guard<std::mutex> lock(mutex_);

  if (bytes_available == nullptr) {
    if (error != nullptr) {
      error->Set(ERROR_INVALID_PARAMETER,
                 "An output counter is required for BytesAvailable.");
    }
    return false;
  }

  if (!EnsureOpen(error)) {
    return false;
  }

  COMSTAT status = {};
  DWORD communication_errors = 0;
  if (!ClearCommError(handle_, &communication_errors, &status)) {
    const DWORD error_code = GetLastError();
    if (error != nullptr) {
      error->Set(error_code,
                 FormatWindowsMessage("Unable to query serial port state",
                                      error_code));
    }
    return false;
  }

  *bytes_available = static_cast<int32_t>(status.cbInQue);
  return true;
}

bool SerialPort::Flush(WindowsError* error) {
  std::lock_guard<std::mutex> lock(mutex_);

  if (!EnsureOpen(error)) {
    return false;
  }

  if (!FlushFileBuffers(handle_)) {
    const DWORD error_code = GetLastError();
    if (error != nullptr) {
      error->Set(error_code,
                 FormatWindowsMessage("Unable to flush serial port buffers",
                                      error_code));
    }
    return false;
  }

  return true;
}

bool SerialPort::ResetBuffers(WindowsError* error) {
  std::lock_guard<std::mutex> lock(mutex_);

  if (!EnsureOpen(error)) {
    return false;
  }

  if (!PurgeComm(handle_, PURGE_RXABORT | PURGE_RXCLEAR | PURGE_TXABORT |
                               PURGE_TXCLEAR)) {
    const DWORD error_code = GetLastError();
    if (error != nullptr) {
      error->Set(error_code,
                 FormatWindowsMessage("Unable to purge serial port buffers",
                                      error_code));
    }
    return false;
  }

  return true;
}

bool SerialPort::GetControlSignals(uint32_t* signal_mask, WindowsError* error) {
  std::lock_guard<std::mutex> lock(mutex_);

  if (signal_mask == nullptr) {
    if (error != nullptr) {
      error->Set(ERROR_INVALID_PARAMETER,
                 "An output signal mask pointer is required.");
    }
    return false;
  }

  if (!EnsureOpen(error)) {
    return false;
  }

  DWORD modem_status = 0;
  if (!GetCommModemStatus(handle_, &modem_status)) {
    const DWORD error_code = GetLastError();
    if (error != nullptr) {
      error->Set(error_code,
                 FormatWindowsMessage("Unable to read modem signal status",
                                      error_code));
    }
    return false;
  }

  uint32_t mask = 0;
  if (rts_enabled_) {
    mask |= 1u << 0;
  }
  if ((modem_status & MS_CTS_ON) != 0) {
    mask |= 1u << 1;
  }
  if (dtr_enabled_) {
    mask |= 1u << 2;
  }
  if ((modem_status & MS_DSR_ON) != 0) {
    mask |= 1u << 3;
  }
  if ((modem_status & MS_RLSD_ON) != 0) {
    mask |= 1u << 4;
  }

  *signal_mask = mask;
  return true;
}

bool SerialPort::SetDtr(bool enabled, WindowsError* error) {
  std::lock_guard<std::mutex> lock(mutex_);

  if (!EnsureOpen(error)) {
    return false;
  }

  if (!EscapeCommFunction(handle_, enabled ? SETDTR : CLRDTR)) {
    const DWORD error_code = GetLastError();
    if (error != nullptr) {
      error->Set(error_code,
                 FormatWindowsMessage("Unable to change DTR state",
                                      error_code));
    }
    return false;
  }

  dtr_enabled_ = enabled;
  return true;
}

bool SerialPort::SetRts(bool enabled, WindowsError* error) {
  std::lock_guard<std::mutex> lock(mutex_);

  if (!EnsureOpen(error)) {
    return false;
  }

  if (!EscapeCommFunction(handle_, enabled ? SETRTS : CLRRTS)) {
    const DWORD error_code = GetLastError();
    if (error != nullptr) {
      error->Set(error_code,
                 FormatWindowsMessage("Unable to change RTS state",
                                      error_code));
    }
    return false;
  }

  rts_enabled_ = enabled;
  return true;
}

bool SerialPort::IsOpen() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return handle_ != INVALID_HANDLE_VALUE;
}

bool SerialPort::ApplyConfiguration(WindowsError* error) {
  DCB state = {};
  state.DCBlength = sizeof(DCB);
  if (!GetCommState(handle_, &state)) {
    const DWORD error_code = GetLastError();
    if (error != nullptr) {
      error->Set(error_code,
                 FormatWindowsMessage("Unable to read serial port state",
                                      error_code));
    }
    return false;
  }

  state.BaudRate = static_cast<DWORD>(config_.baud_rate);
  state.ByteSize = static_cast<BYTE>(config_.data_bits);
  state.StopBits = MapStopBits(config_.stop_bits);
  state.Parity = MapParity(config_.parity);
  state.fBinary = TRUE;
  state.fParity = state.Parity != NOPARITY;

  state.fOutxCtsFlow = FALSE;
  state.fRtsControl = RTS_CONTROL_DISABLE;
  state.fInX = FALSE;
  state.fOutX = FALSE;
  state.fDtrControl = DTR_CONTROL_ENABLE;
  dtr_enabled_ = true;
  rts_enabled_ = false;

  switch (config_.flow_control) {
    case 1:
      state.fOutxCtsFlow = TRUE;
      state.fRtsControl = RTS_CONTROL_HANDSHAKE;
      rts_enabled_ = true;
      break;
    case 2:
      state.fInX = TRUE;
      state.fOutX = TRUE;
      state.XonChar = 0x11;
      state.XoffChar = 0x13;
      break;
    default:
      break;
  }

  if (!SetCommState(handle_, &state)) {
    const DWORD error_code = GetLastError();
    if (error != nullptr) {
      error->Set(error_code,
                 FormatWindowsMessage("Unable to apply serial configuration",
                                      error_code));
    }
    return false;
  }

  return true;
}

bool SerialPort::ApplyTimeouts(WindowsError* error) {
  COMMTIMEOUTS timeouts = {};

  if (config_.read_timeout_ms <= 0) {
    timeouts.ReadIntervalTimeout = 0;
    timeouts.ReadTotalTimeoutMultiplier = 0;
    timeouts.ReadTotalTimeoutConstant = 0;
  } else {
    timeouts.ReadIntervalTimeout = static_cast<DWORD>(config_.read_timeout_ms);
    timeouts.ReadTotalTimeoutMultiplier = 0;
    timeouts.ReadTotalTimeoutConstant =
        static_cast<DWORD>(config_.read_timeout_ms);
  }

  if (config_.write_timeout_ms <= 0) {
    timeouts.WriteTotalTimeoutMultiplier = 0;
    timeouts.WriteTotalTimeoutConstant = 0;
  } else {
    timeouts.WriteTotalTimeoutMultiplier = 0;
    timeouts.WriteTotalTimeoutConstant =
        static_cast<DWORD>(config_.write_timeout_ms);
  }

  if (!SetCommTimeouts(handle_, &timeouts)) {
    const DWORD error_code = GetLastError();
    if (error != nullptr) {
      error->Set(error_code,
                 FormatWindowsMessage("Unable to apply serial timeouts",
                                      error_code));
    }
    return false;
  }

  return true;
}

bool SerialPort::EnsureOpen(WindowsError* error) const {
  if (handle_ != INVALID_HANDLE_VALUE) {
    return true;
  }

  if (error != nullptr) {
    error->Set(ERROR_INVALID_HANDLE, "The serial port is not open.");
  }
  return false;
}

std::wstring SerialPort::DevicePath() const {
  if (port_name_.rfind(L"\\\\.\\", 0) == 0) {
    return port_name_;
  }
  return L"\\\\.\\" + port_name_;
}

void SerialPort::CloseUnlocked() {
  if (handle_ != INVALID_HANDLE_VALUE) {
    CloseHandle(handle_);
    handle_ = INVALID_HANDLE_VALUE;
  }
}
