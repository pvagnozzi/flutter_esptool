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
end
