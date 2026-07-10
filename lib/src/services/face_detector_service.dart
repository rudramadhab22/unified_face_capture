import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../models/face_entity.dart';

/// Result of a single face detection pass.
class FaceDetectionResult {
  final List<FaceEntity> faces;
  final InputImageRotation rotation;
  const FaceDetectionResult({required this.faces, required this.rotation});
}

class FaceDetectorService {
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableClassification: true,
      enableLandmarks: true,
      enableContours: true,
      enableTracking: true,
    ),
  );

  /// Detect faces from a [CameraImage] frame using [controller] for metadata.
  /// Returns a [FaceDetectionResult] containing the detected faces and the
  /// computed [InputImageRotation] used for coordinate scaling.
  Future<FaceDetectionResult> detectFaces(
    CameraImage image,
    CameraController controller,
  ) async {
    final result = _toInputImage(image, controller);
    if (result == null) {
      return FaceDetectionResult(
        faces: [],
        rotation: InputImageRotation.rotation0deg,
      );
    }
    final inputImage = result.$1;
    final rotation = result.$2;

    final faces = await _faceDetector.processImage(inputImage);

    final entities = faces.map((face) {
      final nose = face.landmarks[FaceLandmarkType.noseBase];
      final leftEye = face.landmarks[FaceLandmarkType.leftEye];
      final rightEye = face.landmarks[FaceLandmarkType.rightEye];
      final mouth = face.landmarks[FaceLandmarkType.bottomMouth];

      int totalContourPoints = 0;
      for (final contour in face.contours.values) {
        if (contour != null) totalContourPoints += contour.points.length;
      }

      return FaceEntity(
        boundingBox: face.boundingBox,
        noseBase: nose != null
            ? Offset(nose.position.x.toDouble(), nose.position.y.toDouble())
            : null,
        leftEye: leftEye != null
            ? Offset(
                leftEye.position.x.toDouble(),
                leftEye.position.y.toDouble(),
              )
            : null,
        rightEye: rightEye != null
            ? Offset(
                rightEye.position.x.toDouble(),
                rightEye.position.y.toDouble(),
              )
            : null,
        mouthCenter: mouth != null
            ? Offset(mouth.position.x.toDouble(), mouth.position.y.toDouble())
            : null,
        leftEyeOpenProbability: face.leftEyeOpenProbability,
        rightEyeOpenProbability: face.rightEyeOpenProbability,
        smilingProbability: face.smilingProbability,
        headEulerAngleX: face.headEulerAngleX ?? 0.0,
        headEulerAngleY: face.headEulerAngleY ?? 0.0,
        headEulerAngleZ: face.headEulerAngleZ ?? 0.0,
        contourPointsCount: totalContourPoints,
      );
    }).toList();

    return FaceDetectionResult(faces: entities, rotation: rotation);
  }

  void dispose() {
    _faceDetector.close();
  }

  /// Returns a record of (InputImage, InputImageRotation) or null on failure.
  (InputImage, InputImageRotation)? _toInputImage(CameraImage image, CameraController controller) {
    try {
      final sensorOrientation =
          controller.description.sensorOrientation;
      final lensDirection = controller.description.lensDirection;

      int rotationValue = 0;
      if (Platform.isAndroid) {
        final orientations = {
          DeviceOrientation.portraitUp: 0,
          DeviceOrientation.landscapeLeft: 90,
          DeviceOrientation.portraitDown: 180,
          DeviceOrientation.landscapeRight: 270,
        };
        final rotationCompensation =
            orientations[controller.value.deviceOrientation] ?? 0;
        if (lensDirection == CameraLensDirection.front) {
          rotationValue = (sensorOrientation + rotationCompensation) % 360;
        } else {
          rotationValue =
              (sensorOrientation - rotationCompensation + 360) % 360;
        }
      } else {
        rotationValue = sensorOrientation;
      }

      final rotation = InputImageRotationValue.fromRawValue(rotationValue) ??
          InputImageRotation.rotation0deg;

      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null ||
          (Platform.isAndroid &&
              format != InputImageFormat.nv21 &&
              format != InputImageFormat.yuv420) ||
          (Platform.isIOS && format != InputImageFormat.bgra8888)) {
        return null;
      }

      Uint8List bytes;
      if (Platform.isAndroid && image.planes.length == 3) {
        bytes = _convertYUV420ToNV21(image);
      } else {
        final buffer = WriteBuffer();
        for (final plane in image.planes) {
          buffer.putUint8List(plane.bytes);
        }
        final data = buffer.done();
        bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      }

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
      return (inputImage, rotation);
    } catch (e) {
      debugPrint('InputImage conversion error: $e');
      return null;
    }
  }

  Uint8List _convertYUV420ToNV21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yBuffer = yPlane.bytes;
    final uBuffer = uPlane.bytes;
    final vBuffer = vPlane.bytes;

    final numPixels = (width * height * 1.5).toInt();
    final nv21 = Uint8List(numPixels);

    // Copy Y plane
    nv21.setRange(0, yBuffer.length, yBuffer);

    // Interleave V and U (NV21 = YYYY...VUVU...)
    int idUV = width * height;
    final int uLen = uBuffer.length;
    final int pixelStride = uPlane.bytesPerPixel ?? 2;

    for (int i = 0; i < uLen; i += pixelStride) {
      if (idUV + 1 < nv21.length) {
        nv21[idUV++] = vBuffer[i];
        nv21[idUV++] = uBuffer[i];
      }
    }

    return nv21;
  }
}
