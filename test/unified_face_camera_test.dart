import 'package:flutter_test/flutter_test.dart';
import 'package:unified_face_camera/unified_face_camera_platform_interface.dart';
import 'package:unified_face_camera/unified_face_camera_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockUnifiedFaceCameraPlatform
    with MockPlatformInterfaceMixin
    implements UnifiedFaceCameraPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<String?> addTimestamp(String path, {double? latitude, double? longitude}) =>
      Future.value('/mock/timestamped_$path');

  @override
  Future<bool> checkCameraPermission() => Future.value(true);

  @override
  Future<bool> requestCameraPermission() => Future.value(true);

  @override
  Future<bool> checkLocationPermission() => Future.value(true);

  @override
  Future<bool> requestLocationPermission() => Future.value(true);

  @override
  Future<Map<String, double>?> getLocation() => Future.value({'latitude': 12.34, 'longitude': 56.78});
}

void main() {
  final UnifiedFaceCameraPlatform initialPlatform =
      UnifiedFaceCameraPlatform.instance;

  test('$MethodChannelUnifiedFaceCamera is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelUnifiedFaceCamera>());
  });

  test('getPlatformVersion returns platform version string', () async {
    final MockUnifiedFaceCameraPlatform fakePlatform =
        MockUnifiedFaceCameraPlatform();
    UnifiedFaceCameraPlatform.instance = fakePlatform;

    expect(await UnifiedFaceCameraPlatform.instance.getPlatformVersion(), '42');

    // Restore default instance
    UnifiedFaceCameraPlatform.instance = initialPlatform;
  });

  test('addTimestamp returns a modified path', () async {
    final MockUnifiedFaceCameraPlatform fakePlatform =
        MockUnifiedFaceCameraPlatform();
    UnifiedFaceCameraPlatform.instance = fakePlatform;

    final result =
        await UnifiedFaceCameraPlatform.instance.addTimestamp('image.jpg');
    expect(result, '/mock/timestamped_image.jpg');

    // Restore default instance
    UnifiedFaceCameraPlatform.instance = initialPlatform;
  });
}
