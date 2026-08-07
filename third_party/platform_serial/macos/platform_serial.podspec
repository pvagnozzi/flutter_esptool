Pod::Spec.new do |s|
  s.name = 'platform_serial'
  s.version = '0.1.0'
  s.summary = 'FFI-backed macOS serial-port support for platform_serial.'
  s.description = <<-DESC
Objective-C++ macOS serial-port implementation for the platform_serial
package. It exposes a stable C ABI for Dart FFI, enumerates ports with IOKit,
and configures ports with termios.
  DESC
  s.homepage = 'https://example.com/platform_serial'
  s.license = { :type => 'MIT' }
  s.author = { 'GitHub Copilot' => 'noreply@github.com' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*.{h,m,mm,swift}'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'
  s.static_framework = true
  s.frameworks = 'Foundation', 'IOKit'
  s.libraries = 'c++'
  s.swift_version = '5.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'gnu++17',
  }
  # The serial_* C ABI functions are only referenced from Dart via FFI
  # (DynamicLibrary.process()), never from native code.  Without this the
  # linker dead-strips them out of the final app and DynamicLibrary lookups
  # fail with "symbol not found".  Mark each exported FFI symbol as required
  # (-u) so the linker keeps it from the plugin's static framework.
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '-Wl,-u,_serial_get_available_ports_json ' \
      '-Wl,-u,_serial_open_port -Wl,-u,_serial_close_port ' \
      '-Wl,-u,_serial_read -Wl,-u,_serial_write ' \
      '-Wl,-u,_serial_bytes_available -Wl,-u,_serial_wait_readable ' \
      '-Wl,-u,_serial_flush -Wl,-u,_serial_reset_buffers ' \
      '-Wl,-u,_serial_get_last_error_code -Wl,-u,_serial_copy_last_error_message ' \
      '-Wl,-u,_serial_set_dtr -Wl,-u,_serial_set_rts -Wl,-u,_serial_free_memory',
  }
end
