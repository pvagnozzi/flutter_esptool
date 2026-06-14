#import "serial_port_manager.h"

#import <Foundation/Foundation.h>
#import <IOKit/IOBSD.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/serial/IOSerialKeys.h>
#import <IOKit/serial/ioss.h>
#import <IOKit/usb/USBSpec.h>
#import <mach/mach_error.h>
#import <sys/event.h>
#import <fcntl.h>
#import <sys/ioctl.h>
#import <sys/select.h>
#import <sys/stat.h>
#import <termios.h>
#import <unistd.h>

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <mutex>
#include <string>
#include <unordered_set>

namespace {

constexpr int32_t kDefaultTimeoutMs = 5000;

static thread_local int32_t g_last_error_code = 0;
static thread_local std::string g_last_error_message = "OK";
static std::mutex g_open_ports_mutex;
static std::unordered_set<std::string> g_open_ports;

void SetLastError(int32_t error_code, NSString *message) {
  g_last_error_code = error_code;
  g_last_error_message = message != nil ? message.UTF8String : "";
}

int32_t SetErrnoError(int32_t error_code, NSString *prefix) {
  const int32_t normalized_error = error_code > 0 ? error_code : EIO;
  NSString *error_text = [NSString stringWithUTF8String:strerror(normalized_error)];
  NSString *message = error_text != nil
      ? [NSString stringWithFormat:@"%@ (code %d): %@", prefix, normalized_error, error_text]
      : [NSString stringWithFormat:@"%@ (code %d)", prefix, normalized_error];
  SetLastError(normalized_error, message);
  return -normalized_error;
}

int32_t SetKernError(kern_return_t return_code, NSString *prefix) {
  const char *mach_message = mach_error_string(return_code);
  NSString *message = [NSString stringWithFormat:@"%@ (code %d): %s",
      prefix,
      return_code,
      mach_message != nullptr ? mach_message : "Unknown Mach error"];
  SetLastError(return_code, message);
  return -static_cast<int32_t>(return_code == KERN_SUCCESS ? EIO : return_code);
}

CFTypeRef CopyRegistryProperty(io_registry_entry_t service, CFStringRef key) {
  return IORegistryEntrySearchCFProperty(
      service,
      kIOServicePlane,
      key,
      kCFAllocatorDefault,
      kIORegistryIterateRecursively | kIORegistryIterateParents);
}

NSString *CopyStringProperty(io_registry_entry_t service, CFStringRef key) {
  CFTypeRef property = CopyRegistryProperty(service, key);
  if (property == nullptr) {
    return nil;
  }

  NSString *result = nil;
  if (CFGetTypeID(property) == CFStringGetTypeID()) {
    result = [(__bridge NSString *)property copy];
  }
  CFRelease(property);
  return result;
}

NSNumber *CopyNumberProperty(io_registry_entry_t service, CFStringRef key) {
  CFTypeRef property = CopyRegistryProperty(service, key);
  if (property == nullptr) {
    return nil;
  }

  NSNumber *result = nil;
  if (CFGetTypeID(property) == CFNumberGetTypeID()) {
    result = [(__bridge NSNumber *)property copy];
  }
  CFRelease(property);
  return result;
}

NSString *HexStringFromNumber(NSNumber *number) {
  if (number == nil) {
    return nil;
  }
  return [NSString stringWithFormat:@"%04X", number.unsignedIntValue];
}

speed_t StandardBaudRate(int32_t baud_rate) {
  switch (baud_rate) {
    case 0:
      return B0;
    case 50:
      return B50;
    case 75:
      return B75;
    case 110:
      return B110;
    case 134:
      return B134;
    case 150:
      return B150;
    case 200:
      return B200;
    case 300:
      return B300;
    case 600:
      return B600;
    case 1200:
      return B1200;
    case 1800:
      return B1800;
    case 2400:
      return B2400;
    case 4800:
      return B4800;
    case 9600:
      return B9600;
    case 19200:
      return B19200;
    case 38400:
      return B38400;
    case 57600:
      return B57600;
    case 115200:
      return B115200;
    case 230400:
      return B230400;
#ifdef B460800
    case 460800:
      return B460800;
#endif
#ifdef B500000
    case 500000:
      return B500000;
#endif
#ifdef B576000
    case 576000:
      return B576000;
#endif
#ifdef B921600
    case 921600:
      return B921600;
#endif
    default:
      return 0;
  }
}

int32_t ConfigurePort(
    int fd,
    int32_t baud_rate,
    int32_t data_bits,
    int32_t stop_bits,
    int32_t parity,
    int32_t flow_control) {
  struct termios options {};
  if (tcgetattr(fd, &options) != 0) {
    return SetErrnoError(errno, @"Unable to read serial port attributes");
  }

  cfmakeraw(&options);
  options.c_cflag |= static_cast<tcflag_t>(CLOCAL | CREAD);
  options.c_cflag &= static_cast<tcflag_t>(~CSIZE);
  options.c_iflag &= static_cast<tcflag_t>(~(IXON | IXOFF | IXANY));
  options.c_cflag &= static_cast<tcflag_t>(~CRTSCTS);
  options.c_cc[VMIN] = 0;
  options.c_cc[VTIME] = 0;

  switch (data_bits) {
    case 5:
      options.c_cflag |= CS5;
      break;
    case 6:
      options.c_cflag |= CS6;
      break;
    case 7:
      options.c_cflag |= CS7;
      break;
    case 8:
      options.c_cflag |= CS8;
      break;
    default:
      return SetErrnoError(EINVAL, @"Unsupported data-bits value");
  }

  options.c_cflag &= static_cast<tcflag_t>(~CSTOPB);
  if (stop_bits == SERIAL_STOP_BITS_TWO) {
    options.c_cflag |= CSTOPB;
  } else if (stop_bits == SERIAL_STOP_BITS_ONE_POINT_FIVE) {
    if (data_bits != 5) {
      return SetErrnoError(
          EINVAL,
          @"1.5 stop bits is only valid with 5 data bits on macOS termios");
    }
    options.c_cflag |= CSTOPB;
  } else if (stop_bits != SERIAL_STOP_BITS_ONE) {
    return SetErrnoError(EINVAL, @"Unsupported stop-bits value");
  }

  options.c_cflag &= static_cast<tcflag_t>(~(PARENB | PARODD));
#ifdef CMSPAR
  options.c_cflag &= static_cast<tcflag_t>(~CMSPAR);
#endif
  switch (parity) {
    case SERIAL_PARITY_NONE:
      break;
    case SERIAL_PARITY_EVEN:
      options.c_cflag |= PARENB;
      break;
    case SERIAL_PARITY_ODD:
      options.c_cflag |= static_cast<tcflag_t>(PARENB | PARODD);
      break;
    case SERIAL_PARITY_MARK:
#ifdef CMSPAR
      options.c_cflag |= static_cast<tcflag_t>(PARENB | PARODD | CMSPAR);
      break;
#else
      return SetErrnoError(ENOTSUP, @"Mark parity is not supported by macOS");
#endif
    case SERIAL_PARITY_SPACE:
#ifdef CMSPAR
      options.c_cflag |= static_cast<tcflag_t>(PARENB | CMSPAR);
      break;
#else
      return SetErrnoError(ENOTSUP, @"Space parity is not supported by macOS");
#endif
    default:
      return SetErrnoError(EINVAL, @"Unsupported parity value");
  }

  switch (flow_control) {
    case SERIAL_FLOW_CONTROL_NONE:
      break;
    case SERIAL_FLOW_CONTROL_RTSCTS:
      options.c_cflag |= CRTSCTS;
      break;
    case SERIAL_FLOW_CONTROL_XONXOFF:
      options.c_iflag |= static_cast<tcflag_t>(IXON | IXOFF);
      break;
    default:
      return SetErrnoError(EINVAL, @"Unsupported flow-control value");
  }

  const speed_t standard_baud = StandardBaudRate(baud_rate);
  if (standard_baud != 0) {
    if (cfsetispeed(&options, standard_baud) != 0 ||
        cfsetospeed(&options, standard_baud) != 0) {
      return SetErrnoError(errno, @"Unable to configure the baud rate");
    }
  } else {
    // macOS supports arbitrary serial speeds via the IOSSIOSPEED ioctl.
    if (cfsetispeed(&options, B9600) != 0 || cfsetospeed(&options, B9600) != 0) {
      return SetErrnoError(errno, @"Unable to stage a custom baud rate");
    }
  }

  if (tcsetattr(fd, TCSANOW, &options) != 0) {
    return SetErrnoError(errno, @"Unable to apply serial port configuration");
  }

  if (standard_baud == 0) {
    speed_t custom_speed = static_cast<speed_t>(baud_rate);
    if (ioctl(fd, IOSSIOSPEED, &custom_speed) != 0) {
      return SetErrnoError(errno, @"Unable to apply the custom baud rate");
    }
  }

  if (tcflush(fd, TCIOFLUSH) != 0) {
    return SetErrnoError(errno, @"Unable to flush the serial port buffers");
  }

  return 0;
}

int32_t WaitWithSelect(int fd, bool writable, int32_t timeout_ms) {
  while (true) {
    fd_set descriptor_set;
    FD_ZERO(&descriptor_set);
    FD_SET(fd, &descriptor_set);

    struct timeval timeout {};
    struct timeval *timeout_pointer = nullptr;
    if (timeout_ms >= 0) {
      timeout.tv_sec = timeout_ms / 1000;
      timeout.tv_usec = (timeout_ms % 1000) * 1000;
      timeout_pointer = &timeout;
    }

    int result = writable
        ? select(fd + 1, nullptr, &descriptor_set, nullptr, timeout_pointer)
        : select(fd + 1, &descriptor_set, nullptr, nullptr, timeout_pointer);
    if (result >= 0) {
      return result;
    }
    if (errno != EINTR) {
      return SetErrnoError(errno, writable
          ? @"Unable to wait for the serial port to become writable"
          : @"Unable to wait for the serial port to become readable");
    }
  }
}

class SerialPortHandle {
 public:
  SerialPortHandle(
      std::string device_path,
      int device_fd,
      int32_t read_timeout_ms,
      int32_t write_timeout_ms)
      : path(std::move(device_path)),
        fd(device_fd),
        kqueue_fd(-1),
        read_timeout_ms(read_timeout_ms),
        write_timeout_ms(write_timeout_ms) {}

  ~SerialPortHandle() { Close(); }

  bool InitializeEventQueue() {
    kqueue_fd = kqueue();
    if (kqueue_fd == -1) {
      SetErrnoError(errno, @"Unable to create the serial-port event queue");
      return false;
    }

    struct kevent change {};
    EV_SET(&change, fd, EVFILT_READ, EV_ADD | EV_ENABLE | EV_CLEAR, 0, 0, nullptr);
    if (kevent(kqueue_fd, &change, 1, nullptr, 0, nullptr) != 0) {
      SetErrnoError(errno, @"Unable to register the serial-port read filter");
      ::close(kqueue_fd);
      kqueue_fd = -1;
      return false;
    }
    return true;
  }

  void Close() {
    if (fd != -1) {
      ioctl(fd, TIOCNXCL);
      ::close(fd);
      fd = -1;
    }

    if (kqueue_fd != -1) {
      ::close(kqueue_fd);
      kqueue_fd = -1;
    }
  }

  std::string path;
  int fd;
  int kqueue_fd;
  int32_t read_timeout_ms;
  int32_t write_timeout_ms;
};

SerialPortHandle *HandleFromOpaque(intptr_t handle) {
  return reinterpret_cast<SerialPortHandle *>(handle);
}

int32_t EffectiveTimeout(int32_t requested_timeout_ms, int32_t default_timeout_ms) {
  if (requested_timeout_ms < 0) {
    return default_timeout_ms;
  }
  return requested_timeout_ms;
}

int32_t WaitReadable(SerialPortHandle *handle, int32_t timeout_ms) {
  const int32_t effective_timeout =
      EffectiveTimeout(timeout_ms, handle->read_timeout_ms);
  if (handle->kqueue_fd != -1) {
    struct kevent event {};
    struct timespec timeout {};
    struct timespec *timeout_pointer = nullptr;
    if (effective_timeout >= 0) {
      timeout.tv_sec = effective_timeout / 1000;
      timeout.tv_nsec = (effective_timeout % 1000) * 1000000L;
      timeout_pointer = &timeout;
    }

    while (true) {
      const int result = kevent(handle->kqueue_fd, nullptr, 0, &event, 1, timeout_pointer);
      if (result >= 0) {
        if (result == 0) {
          return 0;
        }
        if ((event.flags & EV_ERROR) != 0U) {
          const int32_t event_error = event.data != 0 ? static_cast<int32_t>(event.data) : EIO;
          return SetErrnoError(event_error, @"kqueue reported a serial-port error");
        }
        return 1;
      }

      if (errno != EINTR) {
        return SetErrnoError(errno, @"Unable to wait for serial-port data");
      }
    }
  }

  return WaitWithSelect(handle->fd, false, effective_timeout);
}

int32_t WriteInternal(
    SerialPortHandle *handle,
    const uint8_t *buffer,
    int32_t length,
    int32_t timeout_ms) {
  if (buffer == nullptr && length > 0) {
    return SetErrnoError(EINVAL, @"Write buffer must not be null");
  }

  const int32_t effective_timeout =
      EffectiveTimeout(timeout_ms, handle->write_timeout_ms);
  const auto started_at = std::chrono::steady_clock::now();
  int32_t total_written = 0;

  while (total_written < length) {
    int32_t remaining_timeout = effective_timeout;
    if (effective_timeout >= 0) {
      const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::steady_clock::now() - started_at);
      remaining_timeout =
          static_cast<int32_t>(std::max<int64_t>(0, effective_timeout - elapsed.count()));
    }

    const int32_t ready = WaitWithSelect(handle->fd, true, remaining_timeout);
    if (ready < 0) {
      return ready;
    }
    if (ready == 0) {
      return total_written;
    }

    const ssize_t written =
        ::write(handle->fd, buffer + total_written, length - total_written);
    if (written > 0) {
      total_written += static_cast<int32_t>(written);
      continue;
    }

    if (written == 0) {
      break;
    }

    if (errno == EAGAIN || errno == EWOULDBLOCK) {
      continue;
    }

    if (errno == EINTR) {
      continue;
    }

    return SetErrnoError(errno, @"Unable to write to the serial port");
  }

  return total_written;
}

}  // namespace

int32_t serial_get_available_ports_json(char **json_out) {
  if (json_out == nullptr) {
    return SetErrnoError(EINVAL, @"The JSON output pointer must not be null");
  }

  *json_out = nullptr;
  SetLastError(0, @"OK");

  CFMutableDictionaryRef matching_dictionary = IOServiceMatching(kIOSerialBSDServiceValue);
  if (matching_dictionary == nullptr) {
    return SetErrnoError(ENOMEM, @"Unable to create the serial-port matching dictionary");
  }

  CFDictionarySetValue(
      matching_dictionary,
      CFSTR(kIOSerialBSDTypeKey),
      CFSTR(kIOSerialBSDAllTypes));

  io_iterator_t iterator = IO_OBJECT_NULL;
  const kern_return_t status =
      IOServiceGetMatchingServices(kIOMainPortDefault, matching_dictionary, &iterator);
  if (status != KERN_SUCCESS) {
    return SetKernError(status, @"Unable to enumerate macOS serial ports");
  }

  NSMutableArray<NSDictionary *> *ports = [NSMutableArray array];
  io_object_t service = IO_OBJECT_NULL;
  while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
    @autoreleasepool {
      NSString *device_path = CFBridgingRelease(
          IORegistryEntryCreateCFProperty(service, CFSTR(kIOCalloutDeviceKey), kCFAllocatorDefault, 0));
      if (device_path == nil) {
        IOObjectRelease(service);
        continue;
      }

      NSString *tty_name = CFBridgingRelease(
          IORegistryEntryCreateCFProperty(service, CFSTR(kIOTTYDeviceKey), kCFAllocatorDefault, 0));
      NSString *base_name = CFBridgingRelease(
          IORegistryEntryCreateCFProperty(service, CFSTR(kIOTTYBaseNameKey), kCFAllocatorDefault, 0));
      NSString *product_name = CopyStringProperty(service, CFSTR(kUSBProductString));
      NSString *serial_number =
          CopyStringProperty(service, CFSTR(kUSBSerialNumberString));
      NSNumber *vendor_id = CopyNumberProperty(service, CFSTR(kUSBVendorID));
      NSNumber *product_id = CopyNumberProperty(service, CFSTR(kUSBProductID));

      NSString *description =
          product_name ?: tty_name ?: base_name ?: device_path.lastPathComponent;

      bool is_open = false;
      {
        std::lock_guard<std::mutex> lock(g_open_ports_mutex);
        is_open = g_open_ports.find(device_path.UTF8String) != g_open_ports.end();
      }

      NSDictionary *port_info = @{
        @"portName": device_path,
        @"description": description ?: @"",
        @"vendorId": HexStringFromNumber(vendor_id) ?: [NSNull null],
        @"productId": HexStringFromNumber(product_id) ?: [NSNull null],
        @"serialNumber": serial_number ?: [NSNull null],
        @"isOpen": @(is_open),
        @"platform": @"macos",
      };
      [ports addObject:port_info];
    }

    IOObjectRelease(service);
  }

  IOObjectRelease(iterator);

  NSError *serialization_error = nil;
  NSData *json_data = [NSJSONSerialization dataWithJSONObject:ports options:0 error:&serialization_error];
  if (json_data == nil) {
    NSString *message = [NSString stringWithFormat:@"Unable to serialize port metadata: %@",
        serialization_error.localizedDescription ?: @"unknown serialization error"];
    SetLastError(EINVAL, message);
    return -EINVAL;
  }

  char *json_buffer = static_cast<char *>(malloc(json_data.length + 1));
  if (json_buffer == nullptr) {
    return SetErrnoError(ENOMEM, @"Unable to allocate the serial-port JSON payload");
  }

  memcpy(json_buffer, json_data.bytes, json_data.length);
  json_buffer[json_data.length] = '\0';
  *json_out = json_buffer;
  return 0;
}

intptr_t serial_open_port(
    const char *port_name,
    int32_t baud_rate,
    int32_t data_bits,
    int32_t stop_bits,
    int32_t parity,
    int32_t flow_control,
    int32_t read_timeout_ms,
    int32_t write_timeout_ms) {
  SetLastError(0, @"OK");

  if (port_name == nullptr || port_name[0] == '\0') {
    SetErrnoError(EINVAL, @"The port name must not be empty");
    return 0;
  }

  const int fd = ::open(port_name, O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC);
  if (fd == -1) {
    SetErrnoError(errno, @"Unable to open the serial port");
    return 0;
  }

  if (ioctl(fd, TIOCEXCL) != 0 && errno != ENOTTY) {
    SetErrnoError(errno, @"Unable to acquire exclusive access to the serial port");
    ::close(fd);
    return 0;
  }

  const int32_t configuration_status = ConfigurePort(
      fd,
      baud_rate,
      data_bits,
      stop_bits,
      parity,
      flow_control);
  if (configuration_status < 0) {
    ::close(fd);
    return 0;
  }

  auto *handle = new SerialPortHandle(
      port_name,
      fd,
      read_timeout_ms >= 0 ? read_timeout_ms : kDefaultTimeoutMs,
      write_timeout_ms >= 0 ? write_timeout_ms : kDefaultTimeoutMs);
  if (!handle->InitializeEventQueue()) {
    delete handle;
    return 0;
  }

  {
    std::lock_guard<std::mutex> lock(g_open_ports_mutex);
    g_open_ports.insert(handle->path);
  }

  return reinterpret_cast<intptr_t>(handle);
}

int32_t serial_close_port(intptr_t handle_value) {
  auto *handle = HandleFromOpaque(handle_value);
  if (handle == nullptr) {
    return SetErrnoError(EINVAL, @"Invalid serial-port handle");
  }

  {
    std::lock_guard<std::mutex> lock(g_open_ports_mutex);
    g_open_ports.erase(handle->path);
  }

  delete handle;
  return 0;
}

int32_t serial_read(intptr_t handle_value, uint8_t *buffer, int32_t length, int32_t timeout_ms) {
  auto *handle = HandleFromOpaque(handle_value);
  if (handle == nullptr) {
    return SetErrnoError(EINVAL, @"Invalid serial-port handle");
  }

  if (buffer == nullptr && length > 0) {
    return SetErrnoError(EINVAL, @"Read buffer must not be null");
  }

  const int32_t ready = WaitReadable(handle, timeout_ms);
  if (ready <= 0) {
    return ready;
  }

  while (true) {
    const ssize_t bytes_read =
        ::read(handle->fd, buffer, static_cast<size_t>(length));
    if (bytes_read >= 0) {
      return static_cast<int32_t>(bytes_read);
    }

    if (errno == EAGAIN || errno == EWOULDBLOCK) {
      return 0;
    }

    if (errno != EINTR) {
      return SetErrnoError(errno, @"Unable to read from the serial port");
    }
  }
}

int32_t serial_write(
    intptr_t handle_value,
    const uint8_t *buffer,
    int32_t length,
    int32_t timeout_ms) {
  auto *handle = HandleFromOpaque(handle_value);
  if (handle == nullptr) {
    return SetErrnoError(EINVAL, @"Invalid serial-port handle");
  }
  return WriteInternal(handle, buffer, length, timeout_ms);
}

int32_t serial_bytes_available(intptr_t handle_value) {
  auto *handle = HandleFromOpaque(handle_value);
  if (handle == nullptr) {
    return SetErrnoError(EINVAL, @"Invalid serial-port handle");
  }

  int bytes_available = 0;
  if (ioctl(handle->fd, FIONREAD, &bytes_available) != 0) {
    return SetErrnoError(errno, @"Unable to query the pending byte count");
  }
  return bytes_available;
}

int32_t serial_wait_readable(intptr_t handle_value, int32_t timeout_ms) {
  auto *handle = HandleFromOpaque(handle_value);
  if (handle == nullptr) {
    return SetErrnoError(EINVAL, @"Invalid serial-port handle");
  }
  return WaitReadable(handle, timeout_ms);
}

int32_t serial_flush(intptr_t handle_value) {
  auto *handle = HandleFromOpaque(handle_value);
  if (handle == nullptr) {
    return SetErrnoError(EINVAL, @"Invalid serial-port handle");
  }

  if (tcdrain(handle->fd) != 0) {
    return SetErrnoError(errno, @"Unable to drain the serial-port output buffer");
  }
  return 0;
}

int32_t serial_reset_buffers(intptr_t handle_value) {
  auto *handle = HandleFromOpaque(handle_value);
  if (handle == nullptr) {
    return SetErrnoError(EINVAL, @"Invalid serial-port handle");
  }

  if (tcflush(handle->fd, TCIOFLUSH) != 0) {
    return SetErrnoError(errno, @"Unable to reset the serial-port buffers");
  }
  return 0;
}

int32_t serial_get_last_error_code(void) { return g_last_error_code; }

char *serial_copy_last_error_message(void) {
  char *message = static_cast<char *>(malloc(g_last_error_message.size() + 1));
  if (message == nullptr) {
    SetErrnoError(ENOMEM, @"Unable to allocate the native error-message buffer");
    return nullptr;
  }

  memcpy(message, g_last_error_message.c_str(), g_last_error_message.size() + 1);
  return message;
}

void serial_free_memory(void *memory) { free(memory); }
