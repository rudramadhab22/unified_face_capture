import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'unified_face_camera_method_channel.dart';

abstract class UnifiedFaceCameraPlatform extends PlatformInterface {
  /// Constructs a UnifiedFaceCameraPlatform.
  UnifiedFaceCameraPlatform() : super(token: _token);

  static final Object _token = Object();

  static UnifiedFaceCameraPlatform _instance = MethodChannelUnifiedFaceCamera();

  /// The default instance of [UnifiedFaceCameraPlatform] to use.
  ///
  /// Defaults to [MethodChannelUnifiedFaceCamera].
  static UnifiedFaceCameraPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [UnifiedFaceCameraPlatform] when
  /// they register themselves.
  static set instance(UnifiedFaceCameraPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Returns the platform version string (e.g. "Android 13").
  Future<String?> getPlatformVersion() {
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }

  /// Embeds a date/time timestamp and location metadata onto the image at [path]
  /// and returns the absolute path of the updated image file.
  Future<String?> addTimestamp(String path, {double? latitude, double? longitude}) {
    throw UnimplementedError('addTimestamp() has not been implemented.');
  }

  /// Checks if the camera permission is granted.
  Future<bool> checkCameraPermission() {
    throw UnimplementedError('checkCameraPermission() has not been implemented.');
  }

  /// Requests the camera permission and returns whether it was granted.
  Future<bool> requestCameraPermission() {
    throw UnimplementedError('requestCameraPermission() has not been implemented.');
  }

  /// Checks if the location permission is granted.
  Future<bool> checkLocationPermission() {
    throw UnimplementedError('checkLocationPermission() has not been implemented.');
  }

  /// Requests the location permission and returns whether it was granted.
  Future<bool> requestLocationPermission() {
    throw UnimplementedError('requestLocationPermission() has not been implemented.');
  }

  /// Fetches the current location (latitude and longitude).
  /// Returns a map with keys 'latitude' and 'longitude', or null if not available/denied.
  Future<Map<String, double>?> getLocation() {
    throw UnimplementedError('getLocation() has not been implemented.');
  }
}
