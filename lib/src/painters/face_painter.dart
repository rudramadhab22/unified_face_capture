import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../models/face_entity.dart';

class FacePainter extends CustomPainter {
  final List<FaceEntity> faces;
  final Size? imageSize;
  final InputImageRotation? rotation;
  final bool isQualityMet;
  final bool isFrontCamera;
  final double targetAspectRatio;
  final double previewAspectRatio;

  FacePainter({
    required this.faces,
    required this.imageSize,
    required this.rotation,
    required this.isQualityMet,
    required this.isFrontCamera,
    required this.targetAspectRatio,
    required this.previewAspectRatio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize == null || rotation == null) return;

    final paintBox = Paint()
      ..style = PaintingStyle.stroke
      ..color = isQualityMet ? Colors.green : Colors.orange
      ..strokeWidth = 3.0;

    for (final face in faces) {
      final rect = _scaleRect(face.boundingBox, size);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(10)),
        paintBox,
      );
    }
  }

  Rect _scaleRect(Rect rect, Size widgetSize) {
    final imgSize = imageSize!;
    final rot = rotation!;

    // Find camera preview dimensions in portrait display space
    double previewWidth, previewHeight;
    if (rot == InputImageRotation.rotation90deg ||
        rot == InputImageRotation.rotation270deg) {
      previewWidth = imgSize.height;
      previewHeight = imgSize.width;
    } else {
      previewWidth = imgSize.width;
      previewHeight = imgSize.height;
    }

    final streamRatio = previewWidth / previewHeight;
    final portraitPreviewRatio = 1 / previewAspectRatio;

    // 1. Calculate the native crop (BoxFit.cover) of the stream inside the CameraPreview
    final nativeScale = streamRatio < portraitPreviewRatio
        ? portraitPreviewRatio / streamRatio
        : 1.0;

    final nativeScaledWidth = previewWidth * nativeScale;
    final nativeScaledHeight = previewHeight * nativeScale;

    // Offset of the stream frame within the CameraPreview widget bounds
    final nativeOffsetX = (previewHeight * portraitPreviewRatio - nativeScaledWidth) / 2;
    final nativeOffsetY = (previewHeight - nativeScaledHeight) / 2;

    // 2. Calculate how the CameraPreview widget is scaled to cover the target aspect ratio box
    double previewScale;
    if (portraitPreviewRatio < targetAspectRatio) {
      previewScale = targetAspectRatio / portraitPreviewRatio;
    } else {
      previewScale = portraitPreviewRatio / targetAspectRatio;
    }

    // Find the dimensions of the AspectRatio widget itself before Transform.scale
    double aspectRatioWidth, aspectRatioHeight;
    if (portraitPreviewRatio < targetAspectRatio) {
      aspectRatioHeight = widgetSize.height;
      aspectRatioWidth = widgetSize.height * portraitPreviewRatio;
    } else {
      aspectRatioWidth = widgetSize.width;
      aspectRatioHeight = widgetSize.width / portraitPreviewRatio;
    }

    final scaledPreviewWidth = aspectRatioWidth * previewScale;
    final scaledPreviewHeight = aspectRatioHeight * previewScale;

    // 3. Combine native scale and screen scale
    final screenScaleX = scaledPreviewWidth / (previewHeight * portraitPreviewRatio);
    final screenScaleY = scaledPreviewHeight / previewHeight;

    final scaleX = nativeScale * screenScaleX;
    final scaleY = nativeScale * screenScaleY;

    final offsetX = nativeOffsetX * screenScaleX + (widgetSize.width - scaledPreviewWidth) / 2;
    final offsetY = nativeOffsetY * screenScaleY + (widgetSize.height - scaledPreviewHeight) / 2;

    final left = rect.left * scaleX + offsetX;
    final right = rect.right * scaleX + offsetX;
    final top = rect.top * scaleY + offsetY;
    final bottom = rect.bottom * scaleY + offsetY;

    if (isFrontCamera) {
      final flippedLeft = widgetSize.width - right;
      final flippedRight = widgetSize.width - left;
      return Rect.fromLTRB(flippedLeft, top, flippedRight, bottom);
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  bool shouldRepaint(covariant FacePainter oldDelegate) => true;
}
