cmake_minimum_required(VERSION 3.14)

project(platform_serial_library VERSION 0.0.1 LANGUAGES CXX)

add_library(platform_serial SHARED
  "platform_serial_plugin.cpp"
  "platform_serial_plugin.h"
  "serial_port.cpp"
  "serial_port.h"
  "serial_port_manager.cpp"
  "serial_port_manager.h"
)

set_target_properties(platform_serial PROPERTIES
  OUTPUT_NAME "platform_serial"
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED ON
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON
)

target_compile_definitions(platform_serial PRIVATE
  UNICODE
  _UNICODE
  NOMINMAX
  WIN32_LEAN_AND_MEAN
)

target_link_libraries(platform_serial PRIVATE setupapi)

if(CMAKE_CURRENT_SOURCE_DIR STREQUAL CMAKE_SOURCE_DIR)
  set(platform_serial_bundled_libraries $<TARGET_FILE:platform_serial>)
else()
  set(platform_serial_bundled_libraries
    $<TARGET_FILE:platform_serial>
    PARENT_SCOPE
  )
endif()
