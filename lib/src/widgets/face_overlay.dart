import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../models/face_entity.dart';
import '../painters/face_painter.dart';

/// Draws a colored bounding box over each detected face, scaled from the
/// ML Kit image coordinate space into the widget's display space.
class FaceOverlay extends StatelessWidget {
  final List<FaceEntity> faces;
  final Size? imageSize;
  final InputImageRotation? rotation;
  final bool isQualityMet;
  final bool isFrontCamera;
  final double targetAspectRatio;
  final double previewAspectRatio;

  const FaceOverlay({
    super.key,
    required this.faces,
    required this.imageSize,
    required this.rotation,
    required this.isQualityMet,
    required this.targetAspectRatio,
    required this.previewAspectRatio,
    this.isFrontCamera = true,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: FacePainter(
        faces: faces,
        imageSize: imageSize,
        rotation: rotation,
        isQualityMet: isQualityMet,
        isFrontCamera: isFrontCamera,
        targetAspectRatio: targetAspectRatio,
        previewAspectRatio: previewAspectRatio,
      ),
    );
  }
}
