Pod::Spec.new do |s|
  s.name             = 'apple_liquid_glass_accessibility'
  s.version          = '0.1.0-dev.1'
  s.summary          = 'Feeds the iOS and macOS accessibility settings Flutter does not report into apple_liquid_glass.'
  s.description      = <<-DESC
Feeds the iOS and macOS accessibility settings Flutter does not report into apple_liquid_glass.
                       DESC
  s.homepage         = 'https://whynotmake.it'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'whynotmake.it'
  s.source           = { :path => '.' }
  s.source_files = 'apple_liquid_glass_accessibility/Sources/apple_liquid_glass_accessibility/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
