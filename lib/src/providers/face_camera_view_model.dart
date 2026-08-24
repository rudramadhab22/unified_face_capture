import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:face_anti_spoofing_detector/face_anti_spoofing_detector.dart';
import '../models/face_entity.dart';
import '../services/face_detector_service.dart';

class FaceCameraViewModel extends ChangeNotifier {
  final FaceDetectorService faceDetectorService;

  FaceCameraViewModel(this.faceDetectorService) {
    _initAntiSpoofing();
  }

  // ── Public state ─────────────────────────────────────────────────────────────
  bool _isProcessing = false;
  bool _isQualityMet = false;
  bool _isAntiSpoofingInitialized = false;
  bool _isLowLight = false;
  List<FaceEntity> _detectedFaces = [];
  CameraImage? _currentAnalysisImage;
  String _failureMessage = "";
  double _lastScore = 0.0;
  DateTime? _lastAntiSpoofTime;
  DateTime? _lastDetectionTime;
  Rect? _lastFaceRect;
  bool _disposed = false;

  // Stability / anti-flicker (strict gates stay; UI stops bouncing)
  int _goodFrameStreak = 0;
  int _badFrameStreak = 0;
  int _emptyFrameStreak = 0;
  int _multiFaceStreak = 0;
  DateTime? _lastGoodQualityTime;
  DateTime? _messageChangedAt;

  Size? _lastImageSize;
  InputImageRotation? _lastRotation;

  bool get isProcessing => _isProcessing;
  bool get isQualityMet => _isQualityMet;
  bool get isAntiSpoofingInitialized => _isAntiSpoofingInitialized;
  bool get isLowLight => _isLowLight;
  List<FaceEntity> get detectedFaces => _detectedFaces;
  CameraImage? get currentAnalysisImage => _currentAnalysisImage;
  String get failureMessage => _failureMessage;
  double get lastScore => _lastScore;
  DateTime? get lastDetectionTime => _lastDetectionTime;
  Size? get lastImageSize => _lastImageSize;
  InputImageRotation? get lastRotation => _lastRotation;

  /// True when the last face detection completed within [detectionFreshnessMs].
  bool get isDetectionFresh {
    final t = _lastDetectionTime;
    if (t == null) return false;
    // Release builds often have different frame timing than debug — give a bit
    // more headroom so Play Store APKs feel as stable as local debug.
    final base = detectionFreshnessMs;
    final window = _isQualityMet ? base + 500 : base;
    return DateTime.now().difference(t).inMilliseconds <= window;
  }

  void setTransientMessage(String message) {
    _setStableMessage(message, force: true);
    if (!_disposed) notifyListeners();
  }

  // ── Constants ────────────────────────────────────────────────────────────────
  // Blink / eye-open stay hardcoded — do not change.
  static const double _minFaceRatio = 0.22;
  static const double _maxFaceRatio = 0.52;
  static const double _maxYaw = 28.0;
  static const double _maxPitch = 28.0;
  static const double _maxRoll = 30.0;
  static const double _minEyeOpenProb = 0.0; // hardcoded — do not change
  static const int _minContourPoints = 28;
  static const double _minEyeWidthRatio = 0.22;
  static const double _maxEyeWidthRatio = 0.75;
  static const double _maxNoseLateralShift = 0.22;
  static const double _antiSpoofingThreshold = 0.80;

  /// Mean Y/luma below this ≈ low light (0–255).
  static const double _lowLightLuma = 55.0;

  /// Freshness window — longer in release to match Play Store timing.
  static int get detectionFreshnessMs => kReleaseMode ? 1600 : 1200;

  static int get _framesToEnable => 2;
  static int get _framesToDisable => kReleaseMode ? 4 : 3;
  static int get _qualityHoldMs => kReleaseMode ? 1400 : 1000;
  static int get _messageHoldMs => 500;
  static const int _emptyFramesToReset = 2;
  static const int _multiFaceFramesToBlock = 2;
  static const double _readyRatioSlack = 0.04;
  static const double _readyPoseSlack = 3.0;

  // ── Blink Detection state ────────────────────────────────────────────────────
  bool _seenOpen = false;
  bool _hasBlinked = false;

  Future<void> _initAntiSpoofing() async {
    try {
      _isAntiSpoofingInitialized = await FaceAntiSpoofingDetector.initialize();
      if (_disposed) return;
      debugPrint("Anti-spoofing initialized: $_isAntiSpoofingInitialized");
    } catch (e) {
      debugPrint("Anti-spoofing init error: $e");
      _failureMessage = "Anti-spoofing plugin error";
      if (!_disposed) notifyListeners();
    }
  }

  // ── Main analysis handler ─────────────────────────────────────────────────────
  Future<void> handleImageAnalysis(CameraImage image, CameraController controller) async {
    if (_isProcessing || _disposed) return;
    _isProcessing = true;
    _currentAnalysisImage = image;

    try {
      _isLowLight = _estimateLuma(image) < _lowLightLuma;

      // Nudge exposure up in dim scenes (best-effort; ignored if unsupported).
      if (_isLowLight) {
        try {
          await controller.setExposureOffset(0.7);
        } catch (_) {}
      }

      final result = await faceDetectorService.detectFaces(image, controller);
      if (_disposed) return;
      final faces = result.faces;
      _detectedFaces = faces;
      _lastRotation = result.rotation;

      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      _lastImageSize = imageSize;

      final isRotated = result.rotation == InputImageRotation.rotation90deg ||
          result.rotation == InputImageRotation.rotation270deg;
      final logicalSize = Size(
        isRotated ? imageSize.height : imageSize.width,
        isRotated ? imageSize.width : imageSize.height,
      );

      if (faces.isEmpty) {
        _emptyFrameStreak++;
        _goodFrameStreak = 0;
        _multiFaceStreak = 0;
        _lastScore = -1.0;

        final emptyMsg = _isLowLight
            ? "Too dark — turn on flash or move to light"
            : "Position your face in frame";

        if (_emptyFrameStreak >= _emptyFramesToReset) {
          _resetLiveness();
          _applyQualityDecision(
            frameOk: false,
            message: emptyMsg,
            hardFail: true,
          );
        } else {
          _applyQualityDecision(
            frameOk: false,
            message: _failureMessage.isEmpty ? "Hold still" : _failureMessage,
            hardFail: false,
          );
        }
        return;
      }

      _emptyFrameStreak = 0;

      if (_hasMultipleSignificantFaces(faces, logicalSize)) {
        _multiFaceStreak++;
        _goodFrameStreak = 0;
        _lastDetectionTime = DateTime.now();
        if (_multiFaceStreak >= _multiFaceFramesToBlock) {
          _resetLiveness();
          _applyQualityDecision(
            frameOk: false,
            message: "Only one face should be visible",
            hardFail: true,
          );
        } else if (!_disposed) {
          notifyListeners();
        }
        return;
      }
      _multiFaceStreak = 0;

      final face = _selectPrimaryFace(faces, logicalSize);
      if (face == null) {
        _applyQualityDecision(
          frameOk: false,
          message: "Position your face in frame",
          hardFail: true,
        );
        return;
      }

      _detectedFaces = [face];
      _lastDetectionTime = DateTime.now();

      if (_lastFaceRect != null) {
        final diffX = (face.boundingBox.center.dx - _lastFaceRect!.center.dx).abs();
        final diffY = (face.boundingBox.center.dy - _lastFaceRect!.center.dy).abs();
        if (diffX > imageSize.width * 0.22 || diffY > imageSize.height * 0.22) {
          _resetLiveness();
        }
      }
      _lastFaceRect = face.boundingBox;

      _updateBlinkState(face);

      final geomOk = _checkGeometry(face, logicalSize);

      bool antiSpoofOk = false;
      var frameMessage = _failureMessage;
      if (geomOk) {
        if (_isAntiSpoofingInitialized) {
          antiSpoofOk = await _checkAntiSpoofing(face, image, result.rotation);
          if (_disposed) return;
          if (!antiSpoofOk && frameMessage.isEmpty) {
            frameMessage = _failureMessage;
          }
        } else {
          frameMessage = "Security system starting...";
        }
      } else {
        frameMessage = _failureMessage;
      }

      final frameOk = geomOk && antiSpoofOk && _hasBlinked;
      if (geomOk && antiSpoofOk && !_hasBlinked) {
        frameMessage = "Please blink your eyes";
      } else if (!frameOk &&
          _isLowLight &&
          frameMessage.isNotEmpty &&
          !frameMessage.toLowerCase().contains("dark") &&
          !frameMessage.toLowerCase().contains("flash")) {
        // Soft hint when gates fail under dim lighting.
        if (frameMessage == "Face details low" ||
            frameMessage == "Landmarks missing" ||
            frameMessage == "Hold still") {
          frameMessage = "Low light — turn on torch for better capture";
        }
      }

      _applyQualityDecision(
        frameOk: frameOk,
        message: frameOk ? "" : frameMessage,
        hardFail: false,
      );
    } catch (e) {
      debugPrint('Analysis error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Average luma from Y plane (Android NV21) or BGRA green-ish sample (iOS).
  double _estimateLuma(CameraImage image) {
    try {
      if (image.planes.isEmpty) return 128;
      final bytes = image.planes.first.bytes;
      if (bytes.isEmpty) return 128;

      // Subsample for speed — enough for a stable low-light signal.
      final step = (bytes.length / 800).ceil().clamp(1, 64);
      var sum = 0;
      var count = 0;
      for (var i = 0; i < bytes.length; i += step) {
        sum += bytes[i];
        count++;
      }
      if (count == 0) return 128;
      return sum / count;
    } catch (_) {
      return 128;
    }
  }

  void _applyQualityDecision({
    required bool frameOk,
    required String message,
    required bool hardFail,
  }) {
    if (frameOk) {
      _goodFrameStreak++;
      _badFrameStreak = 0;
      _lastGoodQualityTime = DateTime.now();
      if (_goodFrameStreak >= _framesToEnable) {
        _isQualityMet = true;
      }
      _setStableMessage("");
    } else {
      _goodFrameStreak = 0;
      _badFrameStreak++;

      final holdActive = !hardFail &&
          _lastGoodQualityTime != null &&
          DateTime.now().difference(_lastGoodQualityTime!).inMilliseconds <
              _qualityHoldMs;

      if (_isQualityMet && holdActive) {
        _setStableMessage("");
      } else if (hardFail || _badFrameStreak >= _framesToDisable) {
        _isQualityMet = false;
        _setStableMessage(message);
      } else {
        _setStableMessage(message.isNotEmpty ? message : _failureMessage);
      }
    }

    if (!_disposed) notifyListeners();
  }

  void _setStableMessage(String message, {bool force = false}) {
    final now = DateTime.now();
    if (!force &&
        message != _failureMessage &&
        message.isNotEmpty &&
        _messageChangedAt != null &&
        now.difference(_messageChangedAt!).inMilliseconds < _messageHoldMs) {
      return;
    }
    if (message != _failureMessage) {
      _failureMessage = message;
      _messageChangedAt = now;
    }
  }

  void _updateBlinkState(FaceEntity face) {
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

  void forceResetLiveness() {
    _resetLiveness();
    _isQualityMet = false;
    _detectedFaces = [];
    _failureMessage = "";
    _lastScore = -1.0;
    _goodFrameStreak = 0;
    _badFrameStreak = 0;
    _emptyFrameStreak = 0;
    _multiFaceStreak = 0;
    _lastGoodQualityTime = null;
    if (!_disposed) notifyListeners();
  }

  void _resetLiveness() {
    _seenOpen = false;
    _hasBlinked = false;
    _lastFaceRect = null;
  }

  bool _hasMultipleSignificantFaces(List<FaceEntity> faces, Size logicalSize) {
    if (faces.length < 2 || logicalSize.width <= 0) return false;
    var significant = 0;
    for (final face in faces) {
      final ratio = face.boundingBox.width / logicalSize.width;
      if (ratio >= 0.12) {
        significant++;
        if (significant > 1) return true;
      }
    }
    return false;
  }

  FaceEntity? _selectPrimaryFace(List<FaceEntity> faces, Size logicalSize) {
    if (faces.isEmpty) return null;
    if (faces.length == 1) return faces.first;

    final center = Offset(logicalSize.width / 2, logicalSize.height / 2);
    FaceEntity? best;
    var bestScore = -1.0;
    for (final face in faces) {
      final box = face.boundingBox;
      final area = box.width * box.height;
      final dist = (box.center - center).distance;
      final score = area / (1.0 + dist);
      if (score > bestScore) {
        bestScore = score;
        best = face;
      }
    }
    return best;
  }

  int _getExifOrientation(InputImageRotation rotation) {
    switch (rotation) {
      case InputImageRotation.rotation0deg:
        return 1;
      case InputImageRotation.rotation90deg:
        return 6;
      case InputImageRotation.rotation180deg:
        return 3;
      case InputImageRotation.rotation270deg:
        return 8;
    }
  }

  Future<bool> _checkAntiSpoofing(
    FaceEntity face,
    CameraImage image,
    InputImageRotation rotation,
  ) async {
    try {
      final buffer = WriteBuffer();
      for (final plane in image.planes) {
        buffer.putUint8List(plane.bytes);
      }
      final data = buffer.done();
      final Uint8List rawBytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      final width = image.width;
      final height = image.height;

      final expectedSize = Platform.isAndroid
          ? (width * height * 1.5).toInt()
          : (width * height * 4);

      final Uint8List processedBytes = rawBytes.length > expectedSize
          ? rawBytes.sublist(0, expectedSize)
          : rawBytes;

      final orientation = _getExifOrientation(rotation);

      final now = DateTime.now();
      // Longer reuse in release / when already ready — cuts jitter.
      final reuseMs = _isQualityMet
          ? (kReleaseMode ? 160 : 120)
          : (kReleaseMode ? 80 : 50);
      if (_lastAntiSpoofTime != null &&
          now.difference(_lastAntiSpoofTime!).inMilliseconds < reuseMs) {
        return _lastScore >= _antiSpoofingThreshold;
      }
      _lastAntiSpoofTime = now;

      var maxScore = -1.0;
      final double? s = await FaceAntiSpoofingDetector.detect(
        yuvBytes: processedBytes,
        previewWidth: width,
        previewHeight: height,
        orientation: orientation,
        faceContour: face.boundingBox,
      );

      if (s != null) {
        maxScore = s;
      }

      _lastScore = maxScore;
      // Keep anti-spoof strict at 0.80 even in low light.
      final isReal = maxScore >= _antiSpoofingThreshold;

      if (maxScore >= 0) {
        if (!isReal) {
          _failureMessage = _isLowLight
              ? "Low light — turn on torch and try again"
              : "Spoofing detected.";
        }
      } else {
        _failureMessage = "Plugin returned no score";
      }
      return isReal;
    } catch (e) {
      debugPrint("Anti-spoof error: $e");
      final errStr = e.toString();
      if (errStr.contains("invalid yuv data size")) {
        _failureMessage = "YUV Size mismatch";
      } else {
        _failureMessage = "Anti-spoof error";
      }
      return false;
    }
  }

  bool _checkGeometry(FaceEntity face, Size logicalSize) {
    // Entry stays strict; once ready (and in low light) allow a little slack.
    final lowLightSlack = _isLowLight ? 0.03 : 0.0;
    final minRatio =
        (_isQualityMet ? _minFaceRatio - _readyRatioSlack : _minFaceRatio) -
            lowLightSlack;
    final maxRatio =
        (_isQualityMet ? _maxFaceRatio + _readyRatioSlack : _maxFaceRatio) +
            lowLightSlack;
    final poseSlack = _readyPoseSlack + (_isLowLight ? 4.0 : 0.0);
    final maxYaw = _isQualityMet ? _maxYaw + poseSlack : _maxYaw + (_isLowLight ? 2.0 : 0.0);
    final maxPitch =
        _isQualityMet ? _maxPitch + poseSlack : _maxPitch + (_isLowLight ? 2.0 : 0.0);
    final maxRoll =
        _isQualityMet ? _maxRoll + poseSlack : _maxRoll + (_isLowLight ? 2.0 : 0.0);
    final minContours = _isLowLight ? 20 : _minContourPoints;

    final faceRatio = face.boundingBox.width / logicalSize.width;
    if (faceRatio < minRatio) {
      _failureMessage = "Move closer";
      return false;
    }
    if (faceRatio > maxRatio) {
      _failureMessage = "Move farther away";
      return false;
    }

    if (face.headEulerAngleY.abs() > maxYaw ||
        face.headEulerAngleX.abs() > maxPitch ||
        face.headEulerAngleZ.abs() > maxRoll) {
      _failureMessage = "Please look straight";
      return false;
    }

    if (face.noseBase == null ||
        face.leftEye == null ||
        face.rightEye == null ||
        face.mouthCenter == null) {
      _failureMessage =
          _isLowLight ? "Low light — turn on torch" : "Landmarks missing";
      return false;
    }

    // Eye-open threshold stays hardcoded at 0.0.
    if ((face.leftEyeOpenProbability ?? 0.0) < _minEyeOpenProb ||
        (face.rightEyeOpenProbability ?? 0.0) < _minEyeOpenProb) {
      _failureMessage = "Eyes closed";
      return false;
    }

    if (face.contourPointsCount < minContours) {
      _failureMessage =
          _isLowLight ? "Low light — turn on torch" : "Face details low";
      return false;
    }

    if (!_checkProportions(face)) {
      _failureMessage = "Hold still";
      return false;
    }

    return true;
  }

  bool _checkProportions(FaceEntity face) {
    final eyeDist = (face.rightEye! - face.leftEye!).distance;
    final faceW = face.boundingBox.width;
    final ratio = eyeDist / faceW;
    final minEye = _isLowLight ? _minEyeWidthRatio - 0.03 : _minEyeWidthRatio;
    final maxEye = _isLowLight ? _maxEyeWidthRatio + 0.05 : _maxEyeWidthRatio;
    if (ratio < minEye || ratio > maxEye) return false;

    final eyeMidX = (face.leftEye!.dx + face.rightEye!.dx) / 2;
    final noseOffset = (face.noseBase!.dx - eyeMidX).abs() / faceW;
    final maxNose =
        _isLowLight ? _maxNoseLateralShift + 0.04 : _maxNoseLateralShift;
    return noseOffset <= maxNose;
  }

  void resetOnCapture() {
    _isQualityMet = false;
    _goodFrameStreak = 0;
    _badFrameStreak = 0;
    _lastGoodQualityTime = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    FaceAntiSpoofingDetector.destroy();
    faceDetectorService.dispose();
    super.dispose();
  }
}
