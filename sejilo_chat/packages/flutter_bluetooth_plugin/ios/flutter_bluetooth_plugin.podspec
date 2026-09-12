#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_bluetooth_plugin.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_bluetooth_plugin'
  s.version          = '0.0.1'
  s.summary          = 'CoreBluetooth-powered iOS Bluetooth APIs for Flutter.'
  s.description      = <<-DESC
Flutter Bluetooth plugin backed by CoreBluetooth on iOS, covering BLE central,
GATT client, peripheral, local GATT server, advertising, notifications, RSSI,
and maximum write-length helpers.
                       DESC
  s.homepage         = 'https://github.com/yuanzhihong1/flutter_bluetooth_plugin'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Yuanzhihong' => '2524422678@qq.com' }
  s.source           = { :path => '.' }
  s.source_files = 'flutter_bluetooth_plugin/Sources/flutter_bluetooth_plugin/**/*.swift'
  s.resource_bundles = {
    'flutter_bluetooth_plugin_privacy' => [
      'flutter_bluetooth_plugin/Sources/flutter_bluetooth_plugin/PrivacyInfo.xcprivacy'
    ]
  }
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
