#include "platform_serial_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cerrno>
#include <cstring>

#include "serial_port_manager.h"

#define platform_serial_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), platform_serial_plugin_get_type(), \
                              FlutterSerialPlugin))

// The Dart package already talks to these generic channels from
// SerialPlatformInterface, so the Linux plugin intentionally uses the shared
// names instead of Linux-specific channel names.

constexpr char kMethodChannelName[] = "dev.flutter/platform_serial";
constexpr char kEventChannelName[] = "dev.flutter/platform_serial_events";
constexpr guint kEventPollIntervalMs = 25;
constexpr size_t kDefaultReadChunkSize = 4096;

struct _FlutterSerialPlugin {
  GObject parent_instance;
  FlMethodChannel* method_channel;
  FlEventChannel* event_channel;
  serial_port_manager_t* manager;
  gchar* active_stream_port;
  guint active_stream_source_id;
};

G_DEFINE_TYPE(FlutterSerialPlugin,
              platform_serial_plugin,
              g_object_get_type())

static FlMethodResponse* create_error_response(const gchar* code,
                                               int32_t error_code,
                                               const gchar* message) {
  g_autoptr(FlValue) details = fl_value_new_map();
  fl_value_set_string_take(details, "errno", fl_value_new_int(-error_code));
  fl_value_set_string_take(details, "osMessage",
                           fl_value_new_string(
                               serial_port_manager_error_message(error_code)));
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new(code, message, details));
}

static FlMethodResponse* create_serial_error_response(int32_t error_code) {
  const int32_t normalized = error_code < 0 ? -error_code : error_code;
  const gchar* code = "ioError";

  switch (normalized) {
    case EALREADY:
      code = "portAlreadyOpen";
      break;
    case ENOENT:
      code = "portNotFound";
      break;
    case EBADF:
      code = "portClosed";
      break;
    case ETIMEDOUT:
      code = "timeout";
      break;
    case ENOTSUP:
      code = "unsupported";
      break;
    default:
      break;
  }

  return create_error_response(
      code, error_code, serial_port_manager_error_message(error_code));
}

static FlMethodResponse* create_bad_args_response(const gchar* message) {
  return create_error_response("invalidArguments", -EINVAL, message);
}

static const gchar* get_required_string_arg(FlValue* args, const gchar* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }

  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return nullptr;
  }

  return fl_value_get_string(value);
}

static int32_t get_required_int_arg(FlValue* args,
                                    const gchar* key,
                                    gboolean* found) {
  *found = FALSE;
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return 0;
  }

  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_INT) {
    return 0;
  }

  *found = TRUE;
  return static_cast<int32_t>(fl_value_get_int(value));
}

static int32_t lookup_handle(FlutterSerialPlugin* self,
                             const gchar* port_name,
                             int32_t* handle_out) {
  return serial_port_manager_find_handle(self->manager, port_name, handle_out);
}

static FlMethodResponse* handle_get_available_ports(FlutterSerialPlugin* self) {
  size_t port_count = 0;
  int32_t error =
      serial_port_manager_list_ports(self->manager, nullptr, 0, &port_count);
  if (error != 0) {
    return create_serial_error_response(error);
  }

  g_autoptr(FlValue) result = fl_value_new_list();
  if (port_count == 0) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  }

  g_autofree serial_port_info_t* ports =
      g_new0(serial_port_info_t, port_count);
  error = serial_port_manager_list_ports(
      self->manager, ports, port_count, &port_count);
  if (error != 0) {
    return create_serial_error_response(error);
  }

  for (size_t i = 0; i < port_count; ++i) {
    g_autoptr(FlValue) port = fl_value_new_map();
    fl_value_set_string_take(
        port, "portName", fl_value_new_string(ports[i].port_name));
    fl_value_set_string_take(
        port, "description", fl_value_new_string(ports[i].description));
    fl_value_set_string_take(
        port, "isOpen", fl_value_new_bool(ports[i].is_open != 0));
    fl_value_set_string_take(port, "platform", fl_value_new_string("linux"));
    fl_value_append_take(result, g_steal_pointer(&port));
  }

  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* handle_open_port(FlutterSerialPlugin* self,
                                          FlValue* args) {
  const gchar* port_name = get_required_string_arg(args, "portName");
  if (port_name == nullptr) {
    return create_bad_args_response("Missing required argument: portName");
  }

  gboolean found = FALSE;
  const int32_t baud_rate = get_required_int_arg(args, "baudRate", &found);
  if (!found) {
    return create_bad_args_response("Missing required argument: baudRate");
  }

  const int32_t data_bits = get_required_int_arg(args, "dataBits", &found);
  if (!found) {
    return create_bad_args_response("Missing required argument: dataBits");
  }

  const int32_t stop_bits = get_required_int_arg(args, "stopBits", &found);
  if (!found) {
    return create_bad_args_response("Missing required argument: stopBits");
  }

  const int32_t parity = get_required_int_arg(args, "parity", &found);
  if (!found) {
    return create_bad_args_response("Missing required argument: parity");
  }

  const int32_t flow_control =
      get_required_int_arg(args, "flowControl", &found);
  if (!found) {
    return create_bad_args_response("Missing required argument: flowControl");
  }

  const int32_t read_timeout =
      get_required_int_arg(args, "readTimeout", &found);
  if (!found) {
    return create_bad_args_response("Missing required argument: readTimeout");
  }

  const int32_t write_timeout =
      get_required_int_arg(args, "writeTimeout", &found);
  if (!found) {
    return create_bad_args_response("Missing required argument: writeTimeout");
  }

  const serial_port_config_t config = {
      .baud_rate = baud_rate,
      .data_bits = data_bits,
      .stop_bits = stop_bits,
      .parity = parity,
      .flow_control = flow_control,
      .read_timeout_ms = read_timeout,
      .write_timeout_ms = write_timeout,
  };

  int32_t handle = 0;
  const int32_t error = serial_port_manager_open(
      self->manager, port_name, &config, &handle);
  if (error != 0) {
    return create_serial_error_response(error);
  }

  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* handle_close_port(FlutterSerialPlugin* self,
                                           FlValue* args) {
  const gchar* port_name = get_required_string_arg(args, "portName");
  if (port_name == nullptr) {
    return create_bad_args_response("Missing required argument: portName");
  }

  const int32_t error =
      serial_port_manager_close_by_name(self->manager, port_name);
  if (error != 0) {
    return create_serial_error_response(error);
  }

  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* handle_read_data(FlutterSerialPlugin* self,
                                          FlValue* args) {
  const gchar* port_name = get_required_string_arg(args, "portName");
  if (port_name == nullptr) {
    return create_bad_args_response("Missing required argument: portName");
  }

  gboolean found = FALSE;
  const int32_t length = get_required_int_arg(args, "length", &found);
  if (!found || length < 0) {
    return create_bad_args_response("Missing or invalid argument: length");
  }

  int32_t handle = 0;
  int32_t error = lookup_handle(self, port_name, &handle);
  if (error != 0) {
    return create_serial_error_response(error);
  }

  const size_t buffer_length =
      length > 0 ? static_cast<size_t>(length) : static_cast<size_t>(1);
  g_autofree uint8_t* buffer =
      static_cast<uint8_t*>(g_malloc0(buffer_length));
  size_t bytes_read = 0;
  error = serial_port_manager_read(
      self->manager, handle, buffer, static_cast<size_t>(length), &bytes_read);
  if (error != 0) {
    return create_serial_error_response(error);
  }

  g_autoptr(FlValue) result = fl_value_new_uint8_list(buffer, bytes_read);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* handle_write_data(FlutterSerialPlugin* self,
                                           FlValue* args) {
  const gchar* port_name = get_required_string_arg(args, "portName");
  if (port_name == nullptr) {
    return create_bad_args_response("Missing required argument: portName");
  }

  FlValue* data_value =
      args == nullptr ? nullptr : fl_value_lookup_string(args, "data");
  if (data_value == nullptr ||
      fl_value_get_type(data_value) != FL_VALUE_TYPE_UINT8_LIST) {
    return create_bad_args_response("Missing required argument: data");
  }

  int32_t handle = 0;
  int32_t error = lookup_handle(self, port_name, &handle);
  if (error != 0) {
    return create_serial_error_response(error);
  }

  size_t bytes_written = 0;
  error = serial_port_manager_write(
      self->manager,
      handle,
      fl_value_get_uint8_list(data_value),
      fl_value_get_length(data_value),
      &bytes_written);
  if (error != 0) {
    return create_serial_error_response(error);
  }

  g_autoptr(FlValue) result =
      fl_value_new_int(static_cast<int64_t>(bytes_written));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* handle_bytes_available(FlutterSerialPlugin* self,
                                                FlValue* args) {
  const gchar* port_name = get_required_string_arg(args, "portName");
  if (port_name == nullptr) {
    return create_bad_args_response("Missing required argument: portName");
  }

  int32_t handle = 0;
  int32_t error = lookup_handle(self, port_name, &handle);
  if (error != 0) {
    return create_serial_error_response(error);
  }

  int32_t bytes_available = 0;
  error = serial_port_manager_bytes_available(
      self->manager, handle, &bytes_available);
  if (error != 0) {
    return create_serial_error_response(error);
  }

  g_autoptr(FlValue) result = fl_value_new_int(bytes_available);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* handle_flush(FlutterSerialPlugin* self, FlValue* args) {
  const gchar* port_name = get_required_string_arg(args, "portName");
  if (port_name == nullptr) {
    return create_bad_args_response("Missing required argument: portName");
  }

  int32_t handle = 0;
  int32_t error = lookup_handle(self, port_name, &handle);
  if (error != 0) {
    return create_serial_error_response(error);
  }

  error = serial_port_manager_flush(self->manager, handle);
  if (error != 0) {
    return create_serial_error_response(error);
  }

  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* handle_reset_buffers(FlutterSerialPlugin* self,
                                              FlValue* args) {
  const gchar* port_name = get_required_string_arg(args, "portName");
  if (port_name == nullptr) {
    return create_bad_args_response("Missing required argument: portName");
  }

  int32_t handle = 0;
  int32_t error = lookup_handle(self, port_name, &handle);
  if (error != 0) {
    return create_serial_error_response(error);
  }

  error = serial_port_manager_reset_buffers(self->manager, handle);
  if (error != 0) {
    return create_serial_error_response(error);
  }

  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* handle_get_control_signals(FlutterSerialPlugin* self,
                                                    FlValue* args) {
  const gchar* port_name = get_required_string_arg(args, "portName");
  if (port_name == nullptr) {
    return create_bad_args_response("Missing required argument: portName");
  }

  int32_t handle = 0;
  int32_t error = lookup_handle(self, port_name, &handle);
  if (error != 0) {
    return create_serial_error_response(error);
  }

  uint32_t signal_mask = 0;
  error = serial_port_manager_get_control_signals(
      self->manager, handle, &signal_mask);
  if (error != 0) {
    return create_serial_error_response(error);
  }

  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "mask", fl_value_new_int(signal_mask));
  fl_value_set_string_take(
      result, "rts", fl_value_new_bool((signal_mask & SERIAL_SIGNAL_RTS) != 0));
  fl_value_set_string_take(
      result, "cts", fl_value_new_bool((signal_mask & SERIAL_SIGNAL_CTS) != 0));
  fl_value_set_string_take(
      result, "dtr", fl_value_new_bool((signal_mask & SERIAL_SIGNAL_DTR) != 0));
  fl_value_set_string_take(
      result, "dsr", fl_value_new_bool((signal_mask & SERIAL_SIGNAL_DSR) != 0));
  fl_value_set_string_take(
      result, "dcd", fl_value_new_bool((signal_mask & SERIAL_SIGNAL_DCD) != 0));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* handle_set_control_signals(FlutterSerialPlugin* self,
                                                    FlValue* args) {
  const gchar* port_name = get_required_string_arg(args, "portName");
  if (port_name == nullptr) {
    return create_bad_args_response("Missing required argument: portName");
  }

  gboolean found = FALSE;
  const int32_t set_mask = get_required_int_arg(args, "setMask", &found);
  if (!found) {
    return create_bad_args_response("Missing required argument: setMask");
  }

  const int32_t clear_mask = get_required_int_arg(args, "clearMask", &found);
  if (!found) {
    return create_bad_args_response("Missing required argument: clearMask");
  }

  int32_t handle = 0;
  int32_t error = lookup_handle(self, port_name, &handle);
  if (error != 0) {
    return create_serial_error_response(error);
  }

  error = serial_port_manager_set_control_signals(
      self->manager,
      handle,
      static_cast<uint32_t>(set_mask),
      static_cast<uint32_t>(clear_mask));
  if (error != 0) {
    return create_serial_error_response(error);
  }

  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* platform_serial_plugin_handle_method_call(
    FlutterSerialPlugin* self,
    FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (strcmp(method, "getAvailablePorts") == 0) {
    return handle_get_available_ports(self);
  }
  if (strcmp(method, "openPort") == 0) {
    return handle_open_port(self, args);
  }
  if (strcmp(method, "closePort") == 0) {
    return handle_close_port(self, args);
  }
  if (strcmp(method, "readData") == 0) {
    return handle_read_data(self, args);
  }
  if (strcmp(method, "writeData") == 0) {
    return handle_write_data(self, args);
  }
  if (strcmp(method, "bytesAvailable") == 0) {
    return handle_bytes_available(self, args);
  }
  if (strcmp(method, "flush") == 0) {
    return handle_flush(self, args);
  }
  if (strcmp(method, "resetBuffers") == 0) {
    return handle_reset_buffers(self, args);
  }
  if (strcmp(method, "getControlSignals") == 0) {
    return handle_get_control_signals(self, args);
  }
  if (strcmp(method, "setControlSignals") == 0) {
    return handle_set_control_signals(self, args);
  }

  return FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
}

static gboolean emit_read_event(FlutterSerialPlugin* self) {
  if (self->active_stream_port == nullptr) {
    return G_SOURCE_REMOVE;
  }

  int32_t handle = 0;
  int32_t error =
      serial_port_manager_find_handle(self->manager, self->active_stream_port, &handle);
  if (error != 0) {
    g_autoptr(FlValue) details = fl_value_new_map();
    fl_value_set_string_take(
        details, "portName", fl_value_new_string(self->active_stream_port));
    fl_event_channel_send_error(self->event_channel,
                                "portClosed",
                                serial_port_manager_error_message(error),
                                details,
                                nullptr,
                                nullptr);
    self->active_stream_source_id = 0;
    return G_SOURCE_REMOVE;
  }

  g_autofree uint8_t* buffer =
      static_cast<uint8_t*>(g_malloc0(kDefaultReadChunkSize));
  size_t bytes_read = 0;
  error = serial_port_manager_read_with_timeout(self->manager,
                                                handle,
                                                buffer,
                                                kDefaultReadChunkSize,
                                                0,
                                                &bytes_read);
  if (error != 0) {
    g_autoptr(FlValue) details = fl_value_new_map();
    fl_value_set_string_take(
        details, "portName", fl_value_new_string(self->active_stream_port));
    fl_value_set_string_take(details, "errno", fl_value_new_int(-error));
    fl_event_channel_send_error(self->event_channel,
                                "ioError",
                                serial_port_manager_error_message(error),
                                details,
                                nullptr,
                                nullptr);
    self->active_stream_source_id = 0;
    return G_SOURCE_REMOVE;
  }

  if (bytes_read == 0) {
    return G_SOURCE_CONTINUE;
  }

  g_autoptr(FlValue) event = fl_value_new_map();
  fl_value_set_string_take(event, "type", fl_value_new_string("data"));
  fl_value_set_string_take(
      event, "portName", fl_value_new_string(self->active_stream_port));
  fl_value_set_string_take(
      event, "data", fl_value_new_uint8_list(buffer, bytes_read));
  fl_event_channel_send(self->event_channel, event, nullptr, nullptr);
  return G_SOURCE_CONTINUE;
}

static gboolean emit_read_event_cb(gpointer user_data) {
  return emit_read_event(platform_serial_PLUGIN(user_data));
}

static FlMethodErrorResponse* event_listen_cb(FlEventChannel* channel,
                                              FlValue* args,
                                              gpointer user_data) {
  auto* self = platform_serial_PLUGIN(user_data);
  const gchar* port_name = get_required_string_arg(args, "portName");
  if (port_name == nullptr) {
    return fl_method_error_response_new("invalidArguments",
                                        "Missing required argument: portName",
                                        nullptr);
  }

  int32_t handle = 0;
  const int32_t error =
      serial_port_manager_find_handle(self->manager, port_name, &handle);
  if (error != 0) {
    return fl_method_error_response_new("portNotFound",
                                        serial_port_manager_error_message(error),
                                        nullptr);
  }

  g_clear_pointer(&self->active_stream_port, g_free);
  if (self->active_stream_source_id != 0) {
    g_source_remove(self->active_stream_source_id);
    self->active_stream_source_id = 0;
  }

  self->active_stream_port = g_strdup(port_name);
  self->active_stream_source_id =
      g_timeout_add(kEventPollIntervalMs, emit_read_event_cb, self);
  return nullptr;
}

static FlMethodErrorResponse* event_cancel_cb(FlEventChannel* channel,
                                              FlValue* args,
                                              gpointer user_data) {
  auto* self = platform_serial_PLUGIN(user_data);
  if (self->active_stream_source_id != 0) {
    g_source_remove(self->active_stream_source_id);
    self->active_stream_source_id = 0;
  }
  g_clear_pointer(&self->active_stream_port, g_free);
  return nullptr;
}

static void method_call_cb(FlMethodChannel* channel,
                           FlMethodCall* method_call,
                           gpointer user_data) {
  auto* plugin = platform_serial_PLUGIN(user_data);
  g_autoptr(FlMethodResponse) response =
      platform_serial_plugin_handle_method_call(plugin, method_call);

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("platform_serial: failed to send method response: %s",
              error->message);
  }
}

static void platform_serial_plugin_dispose(GObject* object) {
  auto* self = platform_serial_PLUGIN(object);
  if (self->active_stream_source_id != 0) {
    g_source_remove(self->active_stream_source_id);
    self->active_stream_source_id = 0;
  }

  g_clear_pointer(&self->active_stream_port, g_free);
  g_clear_object(&self->method_channel);
  g_clear_object(&self->event_channel);

  if (self->manager != nullptr) {
    serial_port_manager_destroy(self->manager);
    self->manager = nullptr;
  }

  G_OBJECT_CLASS(platform_serial_plugin_parent_class)->dispose(object);
}

static void platform_serial_plugin_class_init(FlutterSerialPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = platform_serial_plugin_dispose;
}

static void platform_serial_plugin_init(FlutterSerialPlugin* self) {
  self->manager = serial_port_manager_create();
  self->method_channel = nullptr;
  self->event_channel = nullptr;
  self->active_stream_port = nullptr;
  self->active_stream_source_id = 0;
}

void platform_serial_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  auto* plugin = platform_serial_PLUGIN(
      g_object_new(platform_serial_plugin_get_type(), nullptr));
  if (plugin->manager == nullptr) {
    g_warning("platform_serial: failed to create serial port manager");
    g_object_unref(plugin);
    return;
  }

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(registrar);

  plugin->method_channel =
      fl_method_channel_new(messenger, kMethodChannelName, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(plugin->method_channel,
                                            method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  plugin->event_channel =
      fl_event_channel_new(messenger, kEventChannelName, FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(plugin->event_channel,
                                       event_listen_cb,
                                       event_cancel_cb,
                                       g_object_ref(plugin),
                                       g_object_unref);

  g_object_unref(plugin);
}
