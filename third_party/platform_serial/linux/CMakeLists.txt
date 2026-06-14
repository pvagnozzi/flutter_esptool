# The Flutter tooling requires CMake 3.10+ for Linux plugins.
cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "platform_serial")
project(${PROJECT_NAME} LANGUAGES C CXX)

set(PLUGIN_NAME "platform_serial_plugin")
set(NATIVE_LIBRARY_NAME "platform_serial_native")

find_package(Threads REQUIRED)

add_library(${NATIVE_LIBRARY_NAME} SHARED
  "serial_port.c"
  "serial_port_manager.c"
)

target_compile_definitions(${NATIVE_LIBRARY_NAME} PRIVATE
  _DEFAULT_SOURCE
  _GNU_SOURCE
)
target_compile_features(${NATIVE_LIBRARY_NAME} PRIVATE c_std_11)
set_target_properties(${NATIVE_LIBRARY_NAME} PROPERTIES
  C_VISIBILITY_PRESET hidden
  OUTPUT_NAME "${NATIVE_LIBRARY_NAME}"
)
target_include_directories(${NATIVE_LIBRARY_NAME}
  PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_link_libraries(${NATIVE_LIBRARY_NAME} PRIVATE Threads::Threads)

add_library(${PLUGIN_NAME} SHARED
  "platform_serial_plugin.cc"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME}
  PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
  INTERFACE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${PLUGIN_NAME} PRIVATE ${NATIVE_LIBRARY_NAME})

set(${PROJECT_NAME}_bundled_libraries
  $<TARGET_FILE:${NATIVE_LIBRARY_NAME}>
  PARENT_SCOPE
)
