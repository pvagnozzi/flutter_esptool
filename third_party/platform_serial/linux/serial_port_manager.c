#include "serial_port_manager.h"

/*
 * Manager layer responsible for:
 *   - enumerating candidate Linux serial devices under /dev
 *   - assigning stable integer handles for Dart FFI callers
 *   - protecting the opened-port table with a mutex
 *   - normalizing a few process-level signal concerns such as SIGPIPE
 *
 * The manager deliberately exposes a flat C API so the same code can be used
 * from Flutter's Linux embedding and from direct dart:ffi consumers.
 */

#include <errno.h>
#include <glob.h>
#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct serial_port_entry {
  int32_t handle;
  serial_port_t* port;
  struct serial_port_entry* next;
} serial_port_entry_t;

struct serial_port_manager {
  pthread_mutex_t mutex;
  serial_port_entry_t* ports;
  int32_t next_handle;
};

static pthread_once_t g_signal_once = PTHREAD_ONCE_INIT;

static void serial_port_manager_initialize_signals(void) {
  /* Ignore SIGPIPE once for the whole process so failed writes surface as errno. */
  struct sigaction action;
  memset(&action, 0, sizeof(action));
  action.sa_handler = SIG_IGN;
  sigemptyset(&action.sa_mask);
  sigaction(SIGPIPE, &action, NULL);
}

static serial_port_entry_t* serial_port_manager_find_by_handle_locked(
    serial_port_manager_t* manager,
    int32_t handle) {
  serial_port_entry_t* current = manager->ports;
  while (current != NULL) {
    if (current->handle == handle) {
      return current;
    }
    current = current->next;
  }
  return NULL;
}

static serial_port_entry_t* serial_port_manager_find_by_name_locked(
    serial_port_manager_t* manager,
    const char* port_name) {
  serial_port_entry_t* current = manager->ports;
  while (current != NULL) {
    if (strcmp(serial_port_get_path(current->port), port_name) == 0) {
      return current;
    }
    current = current->next;
  }
  return NULL;
}

static bool serial_port_manager_is_open_locked(serial_port_manager_t* manager,
                                               const char* port_name) {
  return serial_port_manager_find_by_name_locked(manager, port_name) != NULL;
}

static serial_port_entry_t* serial_port_manager_detach_locked(
    serial_port_manager_t* manager,
    int32_t handle) {
  serial_port_entry_t* previous = NULL;
  serial_port_entry_t* current = manager->ports;
  while (current != NULL) {
    if (current->handle == handle) {
      if (previous == NULL) {
        manager->ports = current->next;
      } else {
        previous->next = current->next;
      }
      current->next = NULL;
      return current;
    }
    previous = current;
    current = current->next;
  }
  return NULL;
}

static serial_port_entry_t* serial_port_manager_detach_by_name_locked(
    serial_port_manager_t* manager,
    const char* port_name) {
  serial_port_entry_t* previous = NULL;
  serial_port_entry_t* current = manager->ports;
  while (current != NULL) {
    if (strcmp(serial_port_get_path(current->port), port_name) == 0) {
      if (previous == NULL) {
        manager->ports = current->next;
      } else {
        previous->next = current->next;
      }
      current->next = NULL;
      return current;
    }
    previous = current;
    current = current->next;
  }
  return NULL;
}

static void serial_port_manager_fill_description(const char* port_name,
                                                 char* description,
                                                 size_t description_length) {
  const char* label = "Serial port";
  if (strstr(port_name, "/dev/ttyUSB") == port_name) {
    label = "USB serial adapter";
  } else if (strstr(port_name, "/dev/ttyACM") == port_name) {
    label = "USB CDC ACM device";
  } else if (strstr(port_name, "/dev/ttyS") == port_name) {
    label = "System UART";
  }

  snprintf(description, description_length, "%s (%s)", label, port_name);
}

static int32_t serial_port_manager_list_ports_for_pattern(
    serial_port_manager_t* manager,
    const char* pattern,
    serial_port_info_t* ports,
    size_t capacity,
    size_t* index) {
  /* glob(3) keeps enumeration simple and matches the package requirements. */
  glob_t glob_results;
  memset(&glob_results, 0, sizeof(glob_results));

  const int result = glob(pattern, 0, NULL, &glob_results);
  if (result != 0 && result != GLOB_NOMATCH) {
    globfree(&glob_results);
    return -EIO;
  }

  for (size_t i = 0; i < glob_results.gl_pathc; ++i) {
    if (ports != NULL && *index < capacity) {
      serial_port_info_t* info = &ports[*index];
      memset(info, 0, sizeof(*info));
      strncpy(info->port_name, glob_results.gl_pathv[i],
              SERIAL_PORT_PATH_MAX_LENGTH - 1);
      serial_port_manager_fill_description(
          glob_results.gl_pathv[i],
          info->description,
          sizeof(info->description));
      info->is_open =
          serial_port_manager_is_open_locked(manager, glob_results.gl_pathv[i]) ? 1 : 0;
    }
    ++(*index);
  }

  globfree(&glob_results);
  return 0;
}

static int32_t serial_port_manager_with_port_locked(
    serial_port_manager_t* manager,
    int32_t handle,
    int32_t (*callback)(serial_port_t* port, void* context),
    void* context) {
  /*
   * All public operations funnel through this helper to ensure that handle
   * lookup and the ensuing serial-port action observe a consistent lifetime.
   */
  if (manager == NULL || callback == NULL) {
    return -EINVAL;
  }

  pthread_mutex_lock(&manager->mutex);
  serial_port_entry_t* entry =
      serial_port_manager_find_by_handle_locked(manager, handle);
  if (entry == NULL) {
    pthread_mutex_unlock(&manager->mutex);
    return -ENOENT;
  }

  const int32_t result = callback(entry->port, context);
  pthread_mutex_unlock(&manager->mutex);
  return result;
}

serial_port_manager_t* serial_port_manager_create(void) {
  pthread_once(&g_signal_once, serial_port_manager_initialize_signals);

  serial_port_manager_t* manager = calloc(1, sizeof(serial_port_manager_t));
  if (manager == NULL) {
    return NULL;
  }

  if (pthread_mutex_init(&manager->mutex, NULL) != 0) {
    free(manager);
    return NULL;
  }

  manager->next_handle = 1;
  return manager;
}

void serial_port_manager_destroy(serial_port_manager_t* manager) {
  if (manager == NULL) {
    return;
  }

  pthread_mutex_lock(&manager->mutex);
  serial_port_entry_t* current = manager->ports;
  manager->ports = NULL;
  pthread_mutex_unlock(&manager->mutex);

  while (current != NULL) {
    serial_port_entry_t* next = current->next;
    serial_port_destroy(current->port);
    free(current);
    current = next;
  }

  pthread_mutex_destroy(&manager->mutex);
  free(manager);
}

int32_t serial_port_manager_list_ports(serial_port_manager_t* manager,
                                       serial_port_info_t* ports,
                                       size_t capacity,
                                       size_t* port_count) {
  if (manager == NULL || port_count == NULL) {
    return -EINVAL;
  }

  const char* patterns[] = {
      "/dev/ttyS*",
      "/dev/ttyUSB*",
      "/dev/ttyACM*",
  };

  pthread_mutex_lock(&manager->mutex);
  size_t index = 0;
  int32_t error = 0;
  for (size_t i = 0; i < sizeof(patterns) / sizeof(patterns[0]); ++i) {
    error = serial_port_manager_list_ports_for_pattern(
        manager, patterns[i], ports, capacity, &index);
    if (error != 0) {
      break;
    }
  }
  pthread_mutex_unlock(&manager->mutex);

  if (error == 0) {
    *port_count = index;
  }
  return error;
}

int32_t serial_port_manager_open(serial_port_manager_t* manager,
                                 const char* port_name,
                                 const serial_port_config_t* config,
                                 int32_t* handle_out) {
  if (manager == NULL || port_name == NULL || handle_out == NULL) {
    return -EINVAL;
  }

  pthread_mutex_lock(&manager->mutex);
  if (serial_port_manager_find_by_name_locked(manager, port_name) != NULL) {
    pthread_mutex_unlock(&manager->mutex);
    return -EALREADY;
  }
  pthread_mutex_unlock(&manager->mutex);

  /*
   * Open happens outside the mutex so expensive termios work does not block
   * unrelated readers, then the finished port is inserted into the handle table
   * in one short critical section.
   */
  int32_t error = 0;
  serial_port_t* port = serial_port_create(port_name, &error);
  if (port == NULL) {
    return error == 0 ? -ENOMEM : error;
  }

  error = serial_port_open(port, config);
  if (error != 0) {
    serial_port_destroy(port);
    return error;
  }

  serial_port_entry_t* entry = calloc(1, sizeof(serial_port_entry_t));
  if (entry == NULL) {
    serial_port_destroy(port);
    return -ENOMEM;
  }

  pthread_mutex_lock(&manager->mutex);
  if (serial_port_manager_find_by_name_locked(manager, port_name) != NULL) {
    pthread_mutex_unlock(&manager->mutex);
    free(entry);
    serial_port_destroy(port);
    return -EALREADY;
  }
  entry->handle = manager->next_handle++;
  entry->port = port;
  entry->next = manager->ports;
  manager->ports = entry;
  pthread_mutex_unlock(&manager->mutex);

  *handle_out = entry->handle;
  return 0;
}

int32_t serial_port_manager_close(serial_port_manager_t* manager, int32_t handle) {
  if (manager == NULL) {
    return -EINVAL;
  }

  pthread_mutex_lock(&manager->mutex);
  serial_port_entry_t* entry = serial_port_manager_detach_locked(manager, handle);
  pthread_mutex_unlock(&manager->mutex);

  if (entry == NULL) {
    return -ENOENT;
  }

  const int32_t error = serial_port_close(entry->port);
  serial_port_destroy(entry->port);
  free(entry);
  return error == -EBADF ? 0 : error;
}

int32_t serial_port_manager_close_by_name(serial_port_manager_t* manager,
                                          const char* port_name) {
  if (manager == NULL || port_name == NULL) {
    return -EINVAL;
  }

  pthread_mutex_lock(&manager->mutex);
  serial_port_entry_t* entry =
      serial_port_manager_detach_by_name_locked(manager, port_name);
  pthread_mutex_unlock(&manager->mutex);

  if (entry == NULL) {
    return -ENOENT;
  }

  const int32_t error = serial_port_close(entry->port);
  serial_port_destroy(entry->port);
  free(entry);
  return error == -EBADF ? 0 : error;
}

int32_t serial_port_manager_find_handle(serial_port_manager_t* manager,
                                        const char* port_name,
                                        int32_t* handle_out) {
  if (manager == NULL || port_name == NULL || handle_out == NULL) {
    return -EINVAL;
  }

  pthread_mutex_lock(&manager->mutex);
  serial_port_entry_t* entry =
      serial_port_manager_find_by_name_locked(manager, port_name);
  if (entry == NULL) {
    pthread_mutex_unlock(&manager->mutex);
    return -ENOENT;
  }

  *handle_out = entry->handle;
  pthread_mutex_unlock(&manager->mutex);
  return 0;
}

typedef struct read_context {
  uint8_t* buffer;
  size_t length;
  int32_t timeout_ms;
  size_t* bytes_read;
} read_context_t;

static int32_t serial_port_manager_read_callback(serial_port_t* port,
                                                 void* context) {
  read_context_t* read_context = context;
  return serial_port_read_with_timeout(port,
                                       read_context->buffer,
                                       read_context->length,
                                       read_context->timeout_ms,
                                       read_context->bytes_read);
}

int32_t serial_port_manager_read(serial_port_manager_t* manager,
                                 int32_t handle,
                                 uint8_t* buffer,
                                 size_t length,
                                 size_t* bytes_read) {
  return serial_port_manager_read_with_timeout(
      manager, handle, buffer, length, -1, bytes_read);
}

int32_t serial_port_manager_read_with_timeout(serial_port_manager_t* manager,
                                              int32_t handle,
                                              uint8_t* buffer,
                                              size_t length,
                                              int32_t timeout_ms,
                                              size_t* bytes_read) {
  read_context_t context = {
      .buffer = buffer,
      .length = length,
      .timeout_ms = timeout_ms,
      .bytes_read = bytes_read,
  };
  return serial_port_manager_with_port_locked(
      manager, handle, serial_port_manager_read_callback, &context);
}

typedef struct write_context {
  const uint8_t* buffer;
  size_t length;
  int32_t timeout_ms;
  size_t* bytes_written;
} write_context_t;

static int32_t serial_port_manager_write_callback(serial_port_t* port,
                                                  void* context) {
  write_context_t* write_context = context;
  return serial_port_write_with_timeout(port,
                                        write_context->buffer,
                                        write_context->length,
                                        write_context->timeout_ms,
                                        write_context->bytes_written);
}

int32_t serial_port_manager_write(serial_port_manager_t* manager,
                                  int32_t handle,
                                  const uint8_t* buffer,
                                  size_t length,
                                  size_t* bytes_written) {
  return serial_port_manager_write_with_timeout(
      manager, handle, buffer, length, -1, bytes_written);
}

int32_t serial_port_manager_write_with_timeout(serial_port_manager_t* manager,
                                               int32_t handle,
                                               const uint8_t* buffer,
                                               size_t length,
                                               int32_t timeout_ms,
                                               size_t* bytes_written) {
  write_context_t context = {
      .buffer = buffer,
      .length = length,
      .timeout_ms = timeout_ms,
      .bytes_written = bytes_written,
  };
  return serial_port_manager_with_port_locked(
      manager, handle, serial_port_manager_write_callback, &context);
}

typedef struct bytes_available_context {
  int32_t* bytes_available;
} bytes_available_context_t;

static int32_t serial_port_manager_bytes_available_callback(serial_port_t* port,
                                                            void* context) {
  bytes_available_context_t* bytes_context = context;
  return serial_port_bytes_available(port, bytes_context->bytes_available);
}

int32_t serial_port_manager_bytes_available(serial_port_manager_t* manager,
                                            int32_t handle,
                                            int32_t* bytes_available) {
  bytes_available_context_t context = {
      .bytes_available = bytes_available,
  };
  return serial_port_manager_with_port_locked(
      manager,
      handle,
      serial_port_manager_bytes_available_callback,
      &context);
}

static int32_t serial_port_manager_flush_callback(serial_port_t* port,
                                                  void* context) {
  (void)context;
  return serial_port_flush(port);
}

int32_t serial_port_manager_flush(serial_port_manager_t* manager, int32_t handle) {
  return serial_port_manager_with_port_locked(
      manager, handle, serial_port_manager_flush_callback, NULL);
}

static int32_t serial_port_manager_reset_buffers_callback(serial_port_t* port,
                                                          void* context) {
  (void)context;
  return serial_port_reset_buffers(port);
}

int32_t serial_port_manager_reset_buffers(serial_port_manager_t* manager,
                                          int32_t handle) {
  return serial_port_manager_with_port_locked(
      manager,
      handle,
      serial_port_manager_reset_buffers_callback,
      NULL);
}

typedef struct control_signal_context {
  uint32_t* signal_mask;
  uint32_t set_mask;
  uint32_t clear_mask;
} control_signal_context_t;

static int32_t serial_port_manager_get_control_signals_callback(
    serial_port_t* port,
    void* context) {
  control_signal_context_t* signal_context = context;
  return serial_port_get_control_signals(port, signal_context->signal_mask);
}

int32_t serial_port_manager_get_control_signals(serial_port_manager_t* manager,
                                                int32_t handle,
                                                uint32_t* signal_mask) {
  control_signal_context_t context = {
      .signal_mask = signal_mask,
      .set_mask = 0,
      .clear_mask = 0,
  };
  return serial_port_manager_with_port_locked(
      manager,
      handle,
      serial_port_manager_get_control_signals_callback,
      &context);
}

static int32_t serial_port_manager_set_control_signals_callback(
    serial_port_t* port,
    void* context) {
  control_signal_context_t* signal_context = context;
  return serial_port_set_control_signals(
      port, signal_context->set_mask, signal_context->clear_mask);
}

int32_t serial_port_manager_set_control_signals(serial_port_manager_t* manager,
                                                int32_t handle,
                                                uint32_t set_mask,
                                                uint32_t clear_mask) {
  control_signal_context_t context = {
      .signal_mask = NULL,
      .set_mask = set_mask,
      .clear_mask = clear_mask,
  };
  return serial_port_manager_with_port_locked(
      manager,
      handle,
      serial_port_manager_set_control_signals_callback,
      &context);
}

const char* serial_port_manager_error_message(int32_t error_code) {
  if (error_code == 0) {
    return "Success";
  }

  const int32_t normalized = error_code < 0 ? -error_code : error_code;
  return strerror(normalized);
}
