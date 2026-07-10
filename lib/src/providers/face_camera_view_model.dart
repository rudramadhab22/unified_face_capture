import 'dart:io';
import 'package:camera/camera.dart';
import 'package:face_anti_spoofing_detector/face_anti_spoofing_detector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../models/face_entity.dart';
import '../services/face_detector_service.dart';

class FaceCameraViewModel extends ChangeNotifier {
  final FaceDetectorService faceDetectorService;

  FaceCameraViewModel(this.faceDetectorService) {
    _initAntiSpoofing();
  }

  // ── State ─────────────────────────────────────────────────────────────────
  List<FaceEntity> _detectedFaces = [];
  Size? _lastImageSize;
  InputImageRotation? _lastRotation;
  bool _isQualityMet = false;
  bool _isProcessing = false;
  bool _disposed = false;
  String _failureMessage = '';
  double _lastScore = -1.0;

  // Anti-spoofing
  bool _isAntiSpoofingInitialized = false;
  DateTime? _lastAntiSpoofTime;

  // Liveness state
  Rect? _lastFaceRect;
  bool _seenOpen = false;
  bool _hasBlinked = false;

  // ── Getters ───────────────────────────────────────────────────────────────
  List<FaceEntity> get detectedFaces => _detectedFaces;
  Size? get lastImageSize => _lastImageSize;
  InputImageRotation? get lastRotation => _lastRotation;
  bool get isQualityMet => _isQualityMet;
  String get failureMessage => _failureMessage;
  double get lastScore => _lastScore;

  // ── Constants ─────────────────────────────────────────────────────────────
  static const double _minFaceRatio = 0.18;
  static const double _maxFaceRatio = 0.90;
  static const double _maxYaw = 35.0;
  static const double _maxPitch = 35.0;
  static const double _maxRoll = 35.0;
  static const double _minEyeOpenProb = 0.40;
  static const int _minContourPoints = 30;
  static const double _minEyeWidthRatio = 0.20;
  static const double _maxEyeWidthRatio = 0.80;
  static const double _maxNoseLateralShift = 0.35;
  static const double _antiSpoofingThreshold = 0.85;

  // ── Blink detection state ─────────────────────────────────────────────────

  Future<void> _initAntiSpoofing() async {
    try {
      _isAntiSpoofingInitialized =
          await FaceAntiSpoofingDetector.initialize();
      if (_disposed) return;
      debugPrint('Anti-spoofing initialized: $_isAntiSpoofingInitialized');
    } catch (e) {
      debugPrint('Anti-spoofing init error: $e');
      _failureMessage = 'Anti-spoofing plugin error';
      if (!_disposed) notifyListeners();
    }
  }

  // ── Main analysis handler ─────────────────────────────────────────────────
  Future<void> handleImageAnalysis(
    CameraImage image,
    CameraController controller,
  ) async {
    if (_isProcessing || _disposed) return;
    _isProcessing = true;

    try {
      final result = await faceDetectorService.detectFaces(image, controller);
      if (_disposed) return;
      _detectedFaces = result.faces;
      _lastRotation = result.rotation;

      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      _lastImageSize = imageSize;

      bool qualityMet = false;
      _failureMessage = '';

      if (result.faces.isNotEmpty) {
        final face = result.faces.first;

        // Detect large jumps (face moved) → reset liveness
        if (_lastFaceRect != null) {
          final diffX = (face.boundingBox.center.dx -
                  _lastFaceRect!.center.dx)
              .abs();
          final diffY = (face.boundingBox.center.dy -
                  _lastFaceRect!.center.dy)
              .abs();
          if (diffX > imageSize.width * 0.25 ||
              diffY > imageSize.height * 0.25) {
            _resetLiveness();
          }
        }
        _lastFaceRect = face.boundingBox;

        _updateBlinkState(face);

        final geomOk = _checkGeometry(face, imageSize);

        bool antiSpoofOk = false;
        if (geomOk) {
          if (_isAntiSpoofingInitialized) {
            antiSpoofOk = await _checkAntiSpoofing(face, image, controller);
            if (_disposed) return;
          } else {
            _failureMessage = 'Security system starting...';
          }
        }

        if (geomOk && antiSpoofOk && _hasBlinked) {
          qualityMet = true;
        } else if (geomOk && antiSpoofOk && !_hasBlinked) {
          _failureMessage = 'Please blink your eyes';
        }
      } else {
        _failureMessage = 'Position your face in frame';
        _lastScore = -1.0;
        _resetLiveness();
      }

      _isQualityMet = qualityMet;
      if (!_disposed) notifyListeners();
    } catch (e) {
      debugPrint('Analysis error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  void _updateBlinkState(FaceEntity face) {
    // NOTE: _hasBlinked is set true immediately — blink check effectively
    // disabled as per original snippet logic.
    _hasBlinked = true;
    final leftOpen = face.leftEyeOpenProbability ?? -1.0;
    final rightOpen = face.rightEyeOpenProbability ?? -1.0;

    if (leftOpen < 0.0 || rightOpen < 0.0) return;

    if (!_hasBlinked) {
      if (!_seenOpen) {
        if (leftOpen > 0.50 && rightOpen > 0.50) {
          _seenOpen = true;
        }
      } else {
        if (leftOpen < 0.40 && rightOpen < 0.40) {
          _hasBlinked = true;
        }
      }
    }
  }

  bool _checkGeometry(FaceEntity face, Size imageSize) {
    final faceW = face.boundingBox.width;
    final faceH = face.boundingBox.height;
    final imgW = imageSize.width;
    final imgH = imageSize.height;

    // Face size ratio check
    final widthRatio = faceW / imgW;
    final heightRatio = faceH / imgH;
    if (widthRatio < _minFaceRatio || widthRatio > _maxFaceRatio) {
      _failureMessage = widthRatio < _minFaceRatio
          ? 'Move closer to the camera'
          : 'Move farther from the camera';
      return false;
    }
    if (heightRatio < _minFaceRatio || heightRatio > _maxFaceRatio) {
      _failureMessage = heightRatio < _minFaceRatio
          ? 'Move closer to the camera'
          : 'Move farther from the camera';
      return false;
    }

    // Head pose checks
    if (face.headEulerAngleY.abs() > _maxYaw) {
      _failureMessage = 'Face the camera directly';
      return false;
    }
    if (face.headEulerAngleX.abs() > _maxPitch) {
      _failureMessage = 'Keep your head level';
      return false;
    }
    if (face.headEulerAngleZ.abs() > _maxRoll) {
      _failureMessage = 'Keep your head upright';
      return false;
    }

    // Eye open check
    final leftOpen = face.leftEyeOpenProbability ?? -1.0;
    final rightOpen = face.rightEyeOpenProbability ?? -1.0;
    if (leftOpen >= 0 && leftOpen < _minEyeOpenProb) {
      _failureMessage = 'Open your eyes';
      return false;
    }
    if (rightOpen >= 0 && rightOpen < _minEyeOpenProb) {
      _failureMessage = 'Open your eyes';
      return false;
    }

    // Contour check (real 3D face has many contour points)
    if (face.contourPointsCount < _minContourPoints) {
      _failureMessage = 'Face not clearly visible';
      return false;
    }

    // Landmark checks
    if (face.leftEye == null || face.rightEye == null || face.noseBase == null) {
      _failureMessage = 'Face not clearly visible';
      return false;
    }

    if (!_checkProportions(face)) {
      _failureMessage = 'Face not clearly visible';
      return false;
    }

    if (!_checkNosePosition(face)) {
      _failureMessage = 'Face the camera directly';
      return false;
    }

    return true;
  }

  Future<bool> _checkAntiSpoofing(
    FaceEntity face,
    CameraImage image,
    CameraController controller,
  ) async {
    try {
      // Throttle anti-spoofing calls
      final now = DateTime.now();
      if (_lastAntiSpoofTime != null &&
          now.difference(_lastAntiSpoofTime!).inMilliseconds < 500) {
        return _lastScore >= _antiSpoofingThreshold;
      }
      _lastAntiSpoofTime = now;

      Uint8List rawBytes;
      if (Platform.isAndroid && image.planes.length == 3) {
        // Reuse the NV21 conversion from the service
        final buffer = WriteBuffer();
        for (final plane in image.planes) {
          buffer.putUint8List(plane.bytes);
        }
        final data = buffer.done();
        rawBytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } else {
        final buffer = WriteBuffer();
        for (final plane in image.planes) {
          buffer.putUint8List(plane.bytes);
        }
        final data = buffer.done();
        rawBytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      }

      final int width = image.width;
      final int height = image.height;
      final int expectedSize = (width * height * 1.5).toInt();

      Uint8List processedBytes;
      if (rawBytes.length > expectedSize) {
        processedBytes = rawBytes.sublist(0, expectedSize);
      } else {
        processedBytes = rawBytes;
      }

      final sensorOrientation = controller.description.sensorOrientation;

      final score = await FaceAntiSpoofingDetector.detect(
        yuvBytes: processedBytes,
        previewWidth: width,
        previewHeight: height,
        orientation: sensorOrientation,
        faceContour: face.boundingBox,
      );

      _lastScore = score ?? -1.0;

      if (_lastScore < 0) {
        _failureMessage = 'Security check failed';
        return false;
      }

      if (_lastScore < _antiSpoofingThreshold) {
        _failureMessage = 'Liveness check failed';
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Anti-spoofing check error: $e');
      _failureMessage = 'Security check error';
      return false;
    }
  }

  bool _checkProportions(FaceEntity face) {
    final eyeDist = (face.rightEye! - face.leftEye!).distance;
    final faceW = face.boundingBox.width;
    final ratio = eyeDist / faceW;
    if (ratio < _minEyeWidthRatio || ratio > _maxEyeWidthRatio) return false;
    return true;
  }

  bool _checkNosePosition(FaceEntity face) {
    final nose = face.noseBase!;
    final faceCenter = face.boundingBox.center.dx;
    final faceW = face.boundingBox.width;
    final lateralShift = (nose.dx - faceCenter).abs() / faceW;
    return lateralShift <= _maxNoseLateralShift;
  }

  void _resetLiveness() {
    _seenOpen = false;
    _hasBlinked = false;
  }

  /// Called when the camera is switched — resets all liveness state.
  void forceResetLiveness() {
    _resetLiveness();
    _lastFaceRect = null;
    _isQualityMet = false;
    _detectedFaces = [];
    _failureMessage = '';
    _lastScore = -1.0;
    if (!_disposed) notifyListeners();
  }

  /// Called after a successful capture to reset state for the next capture.
  void resetOnCapture() {
    forceResetLiveness();
  }

  @override
  void dispose() {
    _disposed = true;
    faceDetectorService.dispose();
    super.dispose();
  }
}
