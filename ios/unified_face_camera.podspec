#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint unified_face_camera.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'unified_face_camera'
  s.version          = '0.0.1'
  s.summary          = 'Flutter camera plugin with face detection and liveness checks.'
  s.description      = <<-DESC
Flutter camera plugin with ML Kit face detection, liveness anti-spoofing,
quality gates, and native timestamp embedding with optional GPS.
                       DESC
  s.homepage         = 'https://github.com/rudramadhab22/unified_face_capture'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'OASYSTSPL' => 'https://github.com/rudramadhab22' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # AVFoundation is needed for camera permission check/request
  s.frameworks = 'AVFoundation'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'unified_face_camera_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
