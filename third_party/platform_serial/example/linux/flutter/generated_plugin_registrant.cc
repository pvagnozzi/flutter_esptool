//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <platform_serial/platform_serial_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) platform_serial_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "PlatformSerialPlugin");
  platform_serial_plugin_register_with_registrar(platform_serial_registrar);
}
