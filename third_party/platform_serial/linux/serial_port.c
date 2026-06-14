#include "serial_port.h"

/*
 * Low-level Linux serial-port implementation built on top of termios.
 *
 * The file keeps a small amount of state per opened port (descriptor, path,
 * configured timeouts and the last errno-derived failure) and exposes a clean
 * C ABI that can be reused both by the Flutter method-channel plugin and by
 * direct Dart FFI bindings.
 */

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

struct serial_port {
  char* path;
  int fd;
  serial_port_config_t config;
  int32_t last_error;
};

static int32_t serial_error_code_from_errno(void) {
  return -errno;
}

static int32_t serial_store_error(serial_port_t* port, int32_t error_code) {
  if (port != NULL) {
    port->last_error = error_code;
  }
  return error_code;
}

static int32_t serial_validate_config(const serial_port_config_t* config) {
  if (config == NULL) {
    return -EINVAL;
  }

  if (config->data_bits < 5 || config->data_bits > 8) {
    return -EINVAL;
  }

  if (config->baud_rate <= 0) {
    return -EINVAL;
  }

  return 0;
}

static speed_t serial_translate_baud_rate(int32_t baud_rate) {
  /* Map the Dart-facing integer baud rate to the closest termios constant. */
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
#ifdef B1000000
    case 1000000:
      return B1000000;
#endif
#ifdef B1152000
    case 1152000:
      return B1152000;
#endif
#ifdef B1500000
    case 1500000:
      return B1500000;
#endif
#ifdef B2000000
    case 2000000:
      return B2000000;
#endif
#ifdef B2500000
    case 2500000:
      return B2500000;
#endif
#ifdef B3000000
    case 3000000:
      return B3000000;
#endif
#ifdef B3500000
    case 3500000:
      return B3500000;
#endif
#ifdef B4000000
    case 4000000:
      return B4000000;
#endif
    default:
      return 0;
  }
}

static int32_t serial_configure_data_bits(struct termios* options,
                                          int32_t data_bits) {
  options->c_cflag &= ~CSIZE;
  switch (data_bits) {
    case 5:
      options->c_cflag |= CS5;
      return 0;
    case 6:
      options->c_cflag |= CS6;
      return 0;
    case 7:
      options->c_cflag |= CS7;
      return 0;
    case 8:
      options->c_cflag |= CS8;
      return 0;
    default:
      return -EINVAL;
  }
}

static int32_t serial_configure_stop_bits(struct termios* options,
                                          const serial_port_config_t* config) {
  options->c_cflag &= ~CSTOPB;

  if (config->stop_bits == SERIAL_STOP_BITS_ONE) {
    return 0;
  }

  if (config->stop_bits == SERIAL_STOP_BITS_TWO) {
    options->c_cflag |= CSTOPB;
    return 0;
  }

  if (config->stop_bits == SERIAL_STOP_BITS_ONE_POINT_FIVE &&
      config->data_bits == 5) {
    options->c_cflag |= CSTOPB;
    return 0;
  }

  return -ENOTSUP;
}

static int32_t serial_configure_parity(struct termios* options,
                                       int32_t parity) {
  options->c_cflag &= ~(PARENB | PARODD);
#ifdef CMSPAR
  options->c_cflag &= ~CMSPAR;
#endif
  options->c_iflag &= ~(INPCK | ISTRIP);

  switch (parity) {
    case SERIAL_PARITY_NONE:
      return 0;
    case SERIAL_PARITY_EVEN:
      options->c_cflag |= PARENB;
      options->c_iflag |= INPCK;
      return 0;
    case SERIAL_PARITY_ODD:
      options->c_cflag |= PARENB | PARODD;
      options->c_iflag |= INPCK;
      return 0;
    case SERIAL_PARITY_MARK:
#ifdef CMSPAR
      options->c_cflag |= PARENB | PARODD | CMSPAR;
      options->c_iflag |= INPCK;
      return 0;
#else
      return -ENOTSUP;
#endif
    case SERIAL_PARITY_SPACE:
#ifdef CMSPAR
      options->c_cflag |= PARENB | CMSPAR;
      options->c_iflag |= INPCK;
      return 0;
#else
      return -ENOTSUP;
#endif
    default:
      return -EINVAL;
  }
}

static int32_t serial_configure_flow_control(struct termios* options,
                                             int32_t flow_control) {
#ifdef CRTSCTS
  options->c_cflag &= ~CRTSCTS;
#endif
  options->c_iflag &= ~(IXON | IXOFF | IXANY);

  switch (flow_control) {
    case SERIAL_FLOW_CONTROL_NONE:
      return 0;
    case SERIAL_FLOW_CONTROL_RTSCTS:
#ifdef CRTSCTS
      options->c_cflag |= CRTSCTS;
      return 0;
#else
      return -ENOTSUP;
#endif
    case SERIAL_FLOW_CONTROL_XONXOFF:
      options->c_iflag |= IXON | IXOFF | IXANY;
      return 0;
    default:
      return -EINVAL;
  }
}

static int32_t serial_apply_configuration(serial_port_t* port,
                                          const serial_port_config_t* config) {
  /*
   * The descriptor stays non-blocking for the whole lifetime of the port.
   * Reads and writes rely on poll(2) for timeout handling rather than VMIN/VTIME
   * so the plugin can safely interoperate with the Flutter main loop.
   */
  struct termios options;
  if (tcgetattr(port->fd, &options) != 0) {
    return serial_store_error(port, serial_error_code_from_errno());
  }

  cfmakeraw(&options);
  options.c_cflag |= CLOCAL | CREAD;
  options.c_cc[VMIN] = 0;
  options.c_cc[VTIME] = 0;

  const speed_t baud = serial_translate_baud_rate(config->baud_rate);
  if (baud == 0) {
    return serial_store_error(port, -EINVAL);
  }

  if (cfsetispeed(&options, baud) != 0 || cfsetospeed(&options, baud) != 0) {
    return serial_store_error(port, serial_error_code_from_errno());
  }

  int32_t error = serial_configure_data_bits(&options, config->data_bits);
  if (error != 0) {
    return serial_store_error(port, error);
  }

  error = serial_configure_stop_bits(&options, config);
  if (error != 0) {
    return serial_store_error(port, error);
  }

  error = serial_configure_parity(&options, config->parity);
  if (error != 0) {
    return serial_store_error(port, error);
  }

  error = serial_configure_flow_control(&options, config->flow_control);
  if (error != 0) {
    return serial_store_error(port, error);
  }

  if (tcsetattr(port->fd, TCSANOW, &options) != 0) {
    return serial_store_error(port, serial_error_code_from_errno());
  }

  port->config = *config;
  port->last_error = 0;
  return 0;
}

static int64_t serial_monotonic_millis(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static int32_t serial_wait_for_fd(int fd, short events, int32_t timeout_ms) {
  /*
   * poll(2) gives us a portable way to combine non-blocking file descriptors
   * with caller-provided timeouts. EINTR is handled explicitly so short-lived
   * signals do not permanently fail a serial operation.
   */
  struct pollfd descriptor = {
      .fd = fd,
      .events = events,
      .revents = 0,
  };

  while (true) {
    const int result = poll(&descriptor, 1, timeout_ms);
    if (result > 0) {
      if ((descriptor.revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) {
        return -EIO;
      }
      return 0;
    }
    if (result == 0) {
      return -ETIMEDOUT;
    }
    if (errno == EINTR) {
      continue;
    }
    return serial_error_code_from_errno();
  }
}

serial_port_t* serial_port_create(const char* path, int32_t* error_code) {
  if (error_code != NULL) {
    *error_code = 0;
  }

  if (path == NULL || path[0] == '\0') {
    if (error_code != NULL) {
      *error_code = -EINVAL;
    }
    return NULL;
  }

  serial_port_t* port = calloc(1, sizeof(serial_port_t));
  if (port == NULL) {
    if (error_code != NULL) {
      *error_code = -ENOMEM;
    }
    return NULL;
  }

  port->path = strdup(path);
  if (port->path == NULL) {
    free(port);
    if (error_code != NULL) {
      *error_code = -ENOMEM;
    }
    return NULL;
  }

  port->fd = -1;
  port->config.baud_rate = 9600;
  port->config.data_bits = 8;
  port->config.stop_bits = SERIAL_STOP_BITS_ONE;
  port->config.parity = SERIAL_PARITY_NONE;
  port->config.flow_control = SERIAL_FLOW_CONTROL_NONE;
  port->config.read_timeout_ms = 5000;
  port->config.write_timeout_ms = 5000;
  port->last_error = 0;
  return port;
}

void serial_port_destroy(serial_port_t* port) {
  if (port == NULL) {
    return;
  }

  if (port->fd >= 0) {
    close(port->fd);
  }

  free(port->path);
  free(port);
}

int32_t serial_port_open(serial_port_t* port, const serial_port_config_t* config) {
  if (port == NULL) {
    return -EINVAL;
  }

  int32_t error = serial_validate_config(config);
  if (error != 0) {
    return serial_store_error(port, error);
  }

  if (port->fd >= 0) {
    return serial_store_error(port, -EALREADY);
  }

  const int fd = open(port->path, O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC);
  if (fd < 0) {
    return serial_store_error(port, serial_error_code_from_errno());
  }

  port->fd = fd;
  error = serial_apply_configuration(port, config);
  if (error != 0) {
    close(port->fd);
    port->fd = -1;
    return error;
  }

  return 0;
}

int32_t serial_port_close(serial_port_t* port) {
  if (port == NULL) {
    return -EINVAL;
  }

  if (port->fd < 0) {
    return serial_store_error(port, -EBADF);
  }

  if (close(port->fd) != 0) {
    return serial_store_error(port, serial_error_code_from_errno());
  }

  port->fd = -1;
  port->last_error = 0;
  return 0;
}

const char* serial_port_get_path(const serial_port_t* port) {
  return port == NULL ? NULL : port->path;
}

bool serial_port_is_open(const serial_port_t* port) {
  return port != NULL && port->fd >= 0;
}

int32_t serial_port_read(serial_port_t* port,
                         uint8_t* buffer,
                         size_t length,
                         size_t* bytes_read) {
  if (port == NULL) {
    return -EINVAL;
  }
  return serial_port_read_with_timeout(
      port, buffer, length, port->config.read_timeout_ms, bytes_read);
}

int32_t serial_port_read_with_timeout(serial_port_t* port,
                                      uint8_t* buffer,
                                      size_t length,
                                      int32_t timeout_ms,
                                      size_t* bytes_read) {
  if (bytes_read != NULL) {
    *bytes_read = 0;
  }

  if (port == NULL || buffer == NULL) {
    return port == NULL ? -EINVAL : serial_store_error(port, -EINVAL);
  }

  if (port->fd < 0) {
    return serial_store_error(port, -EBADF);
  }

  if (length == 0) {
    port->last_error = 0;
    return 0;
  }

  if (timeout_ms < 0) {
    timeout_ms = port->config.read_timeout_ms;
  }

  /*
   * A zero timeout is used by the plugin's event pump to probe for newly
   * available bytes without blocking the GTK thread. In that mode a timeout is
   * translated into a successful 0-byte read instead of an error.
   */
  int32_t error = serial_wait_for_fd(port->fd, POLLIN, timeout_ms);
  if (error != 0) {
    if (error == -ETIMEDOUT && timeout_ms == 0) {
      port->last_error = 0;
      return 0;
    }
    return serial_store_error(port, error);
  }

  while (true) {
    const ssize_t result = read(port->fd, buffer, length);
    if (result >= 0) {
      if (bytes_read != NULL) {
        *bytes_read = (size_t)result;
      }
      port->last_error = 0;
      return 0;
    }

    if (errno == EINTR) {
      continue;
    }
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
      port->last_error = 0;
      return 0;
    }
    return serial_store_error(port, serial_error_code_from_errno());
  }
}

int32_t serial_port_write(serial_port_t* port,
                          const uint8_t* buffer,
                          size_t length,
                          size_t* bytes_written) {
  if (port == NULL) {
    return -EINVAL;
  }
  return serial_port_write_with_timeout(
      port, buffer, length, port->config.write_timeout_ms, bytes_written);
}

int32_t serial_port_write_with_timeout(serial_port_t* port,
                                       const uint8_t* buffer,
                                       size_t length,
                                       int32_t timeout_ms,
                                       size_t* bytes_written) {
  if (bytes_written != NULL) {
    *bytes_written = 0;
  }

  if (port == NULL || buffer == NULL) {
    return port == NULL ? -EINVAL : serial_store_error(port, -EINVAL);
  }

  if (port->fd < 0) {
    return serial_store_error(port, -EBADF);
  }

  if (timeout_ms < 0) {
    timeout_ms = port->config.write_timeout_ms;
  }

  /* Writes are retried until the whole buffer is drained or the timeout expires. */
  const int64_t deadline_ms =
      timeout_ms == 0 ? serial_monotonic_millis() : serial_monotonic_millis() + timeout_ms;

  size_t total_written = 0;
  while (total_written < length) {
    int32_t wait_timeout = timeout_ms;
    if (timeout_ms > 0) {
      const int64_t remaining_ms = deadline_ms - serial_monotonic_millis();
      if (remaining_ms <= 0) {
        if (bytes_written != NULL) {
          *bytes_written = total_written;
        }
        return serial_store_error(port, -ETIMEDOUT);
      }
      wait_timeout = (int32_t)remaining_ms;
    }

    int32_t error = serial_wait_for_fd(port->fd, POLLOUT, wait_timeout);
    if (error != 0) {
      if (bytes_written != NULL) {
        *bytes_written = total_written;
      }
      return serial_store_error(port, error);
    }

    const ssize_t result =
        write(port->fd, buffer + total_written, length - total_written);
    if (result > 0) {
      total_written += (size_t)result;
      continue;
    }
    if (result == 0) {
      if (bytes_written != NULL) {
        *bytes_written = total_written;
      }
      return serial_store_error(port, -EIO);
    }

    if (errno == EINTR) {
      continue;
    }
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
      continue;
    }

    if (bytes_written != NULL) {
      *bytes_written = total_written;
    }
    return serial_store_error(port, serial_error_code_from_errno());
  }

  if (bytes_written != NULL) {
    *bytes_written = total_written;
  }
  port->last_error = 0;
  return 0;
}

int32_t serial_port_bytes_available(serial_port_t* port, int32_t* bytes_available) {
  if (bytes_available != NULL) {
    *bytes_available = 0;
  }

  if (port == NULL) {
    return -EINVAL;
  }

  if (port->fd < 0) {
    return serial_store_error(port, -EBADF);
  }

  int available = 0;
  if (ioctl(port->fd, FIONREAD, &available) != 0) {
    return serial_store_error(port, serial_error_code_from_errno());
  }

  if (bytes_available != NULL) {
    *bytes_available = (int32_t)available;
  }
  port->last_error = 0;
  return 0;
}

int32_t serial_port_flush(serial_port_t* port) {
  if (port == NULL) {
    return -EINVAL;
  }

  if (port->fd < 0) {
    return serial_store_error(port, -EBADF);
  }

  if (tcdrain(port->fd) != 0) {
    return serial_store_error(port, serial_error_code_from_errno());
  }

  port->last_error = 0;
  return 0;
}

int32_t serial_port_reset_buffers(serial_port_t* port) {
  if (port == NULL) {
    return -EINVAL;
  }

  if (port->fd < 0) {
    return serial_store_error(port, -EBADF);
  }

  if (tcflush(port->fd, TCIOFLUSH) != 0) {
    return serial_store_error(port, serial_error_code_from_errno());
  }

  port->last_error = 0;
  return 0;
}

static uint32_t serial_convert_modem_bits(int modem_bits) {
  uint32_t signal_mask = 0;
  if ((modem_bits & TIOCM_RTS) != 0) {
    signal_mask |= SERIAL_SIGNAL_RTS;
  }
  if ((modem_bits & TIOCM_CTS) != 0) {
    signal_mask |= SERIAL_SIGNAL_CTS;
  }
  if ((modem_bits & TIOCM_DTR) != 0) {
    signal_mask |= SERIAL_SIGNAL_DTR;
  }
  if ((modem_bits & TIOCM_DSR) != 0) {
    signal_mask |= SERIAL_SIGNAL_DSR;
  }
  if ((modem_bits & TIOCM_CAR) != 0) {
    signal_mask |= SERIAL_SIGNAL_DCD;
  }
  return signal_mask;
}

static int serial_convert_requested_modem_bits(uint32_t signal_mask) {
  int modem_bits = 0;
  if ((signal_mask & SERIAL_SIGNAL_RTS) != 0) {
    modem_bits |= TIOCM_RTS;
  }
  if ((signal_mask & SERIAL_SIGNAL_DTR) != 0) {
    modem_bits |= TIOCM_DTR;
  }
  if ((signal_mask & SERIAL_SIGNAL_CTS) != 0) {
    modem_bits |= TIOCM_CTS;
  }
  if ((signal_mask & SERIAL_SIGNAL_DSR) != 0) {
    modem_bits |= TIOCM_DSR;
  }
  if ((signal_mask & SERIAL_SIGNAL_DCD) != 0) {
    modem_bits |= TIOCM_CAR;
  }
  return modem_bits;
}

int32_t serial_port_get_control_signals(serial_port_t* port, uint32_t* signal_mask) {
  /* Query modem-control line state such as RTS/CTS/DTR/DSR/DCD. */
  if (signal_mask != NULL) {
    *signal_mask = 0;
  }

  if (port == NULL) {
    return -EINVAL;
  }

  if (port->fd < 0) {
    return serial_store_error(port, -EBADF);
  }

  int modem_bits = 0;
  if (ioctl(port->fd, TIOCMGET, &modem_bits) != 0) {
    return serial_store_error(port, serial_error_code_from_errno());
  }

  if (signal_mask != NULL) {
    *signal_mask = serial_convert_modem_bits(modem_bits);
  }
  port->last_error = 0;
  return 0;
}

int32_t serial_port_set_control_signals(serial_port_t* port,
                                        uint32_t set_mask,
                                        uint32_t clear_mask) {
  /*
   * Linux exposes modem-line updates through TIOCMBIS/TIOCMBIC. The mask-based
   * API is intentionally simple so Dart can toggle multiple lines in one FFI
   * call without additional native allocations.
   */
  if (port == NULL) {
    return -EINVAL;
  }

  if (port->fd < 0) {
    return serial_store_error(port, -EBADF);
  }

  const int set_bits = serial_convert_requested_modem_bits(set_mask);
  const int clear_bits = serial_convert_requested_modem_bits(clear_mask);

  if (set_bits != 0 && ioctl(port->fd, TIOCMBIS, &set_bits) != 0) {
    return serial_store_error(port, serial_error_code_from_errno());
  }

  if (clear_bits != 0 && ioctl(port->fd, TIOCMBIC, &clear_bits) != 0) {
    return serial_store_error(port, serial_error_code_from_errno());
  }

  port->last_error = 0;
  return 0;
}

int32_t serial_port_get_last_error(const serial_port_t* port) {
  return port == NULL ? -EINVAL : port->last_error;
}

const serial_port_config_t* serial_port_get_config(const serial_port_t* port) {
  return port == NULL ? NULL : &port->config;
}
