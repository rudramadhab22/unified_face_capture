import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'unified_face_camera_platform_interface.dart';

/// An implementation of [UnifiedFaceCameraPlatform] that uses method channels.
class MethodChannelUnifiedFaceCamera extends UnifiedFaceCameraPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('unified_face_camera');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<String?> addTimestamp(String path, {double? latitude, double? longitude}) async {
    final timestampedPath = await methodChannel.invokeMethod<String>(
      'addTimestamp',
      {
        'path': path,
        'latitude': latitude,
        'longitude': longitude,
      },
    );
    return timestampedPath;
  }

  @override
  Future<bool> checkCameraPermission() async {
    final granted = await methodChannel.invokeMethod<bool>('checkCameraPermission');
    return granted ?? false;
  }

  @override
  Future<bool> requestCameraPermission() async {
    final granted = await methodChannel.invokeMethod<bool>('requestCameraPermission');
    return granted ?? false;
  }

  @override
  Future<bool> checkLocationPermission() async {
    final granted = await methodChannel.invokeMethod<bool>('checkLocationPermission');
    return granted ?? false;
  }

  @override
  Future<bool> requestLocationPermission() async {
    final granted = await methodChannel.invokeMethod<bool>('requestLocationPermission');
    return granted ?? false;
  }

  @override
  Future<Map<String, double>?> getLocation() async {
    final result = await methodChannel.invokeMapMethod<String, double>('getLocation');
    return result;
  }
}
