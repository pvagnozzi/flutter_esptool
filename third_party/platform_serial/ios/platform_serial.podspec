Pod::Spec.new do |s|
  s.name = 'platform_serial'
  s.version = '0.1.0'
  s.summary = 'iOS serial-port implementation for the platform_serial plugin.'
  s.description = <<-DESC
Swift-based iOS implementation for platform_serial. It exposes MethodChannel and
EventChannel APIs to Flutter, enumerates ports with IOKit when available,
provides simulator mock ports, and performs asynchronous I/O with Network.
  DESC
  s.homepage = 'https://example.com/platform_serial'
  s.license = { :type => 'MIT' }
  s.author = { 'GitHub Copilot' => 'noreply@github.com' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*.{swift,h}'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.static_framework = true
  s.frameworks = 'Foundation', 'Network'
  s.swift_version = '5.9'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => '$(inherited)'
  }
end
