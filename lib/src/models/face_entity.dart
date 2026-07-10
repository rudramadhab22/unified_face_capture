import 'dart:ui';

class FaceEntity {
  final Rect boundingBox;
  final Offset? noseBase;
  final Offset? leftEye;
  final Offset? rightEye;
  final Offset? mouthCenter;
  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;
  final double? smilingProbability;

  /// Head pose angles from ML Kit (degrees).
  /// eulerX = pitch (positive = looking up)
  /// eulerY = yaw   (positive = turning right)
  /// eulerZ = roll  (positive = tilting right)
  final double headEulerAngleX;
  final double headEulerAngleY;
  final double headEulerAngleZ;

  /// Total face-contour points returned by ML Kit.
  /// A real 3D face with enableContours:true yields 130+ points.
  /// Flat images (screens / prints) produce far fewer reliable points.
  final int contourPointsCount;

  FaceEntity({
    required this.boundingBox,
    this.noseBase,
    this.leftEye,
    this.rightEye,
    this.mouthCenter,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
    this.smilingProbability,
    required this.headEulerAngleX,
    required this.headEulerAngleY,
    required this.headEulerAngleZ,
    required this.contourPointsCount,
  });
}
