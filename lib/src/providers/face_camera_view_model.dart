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
  List<FaceEntity> _detectedFaces = [];
  CameraImage? _currentAnalysisImage;
  String _failureMessage = "";
  double _lastScore = 0.0;
  DateTime? _lastAntiSpoofTime;
  Rect? _lastFaceRect;
  bool _disposed = false;

  Size? _lastImageSize;
  InputImageRotation? _lastRotation;

  bool get isProcessing           => _isProcessing;
  bool get isQualityMet           => _isQualityMet;
  bool get isAntiSpoofingInitialized => _isAntiSpoofingInitialized;
  List<FaceEntity> get detectedFaces        => _detectedFaces;
  CameraImage?   get currentAnalysisImage => _currentAnalysisImage;
  String get failureMessage       => _failureMessage;
  double get lastScore            => _lastScore;
  Size? get lastImageSize         => _lastImageSize;
  InputImageRotation? get lastRotation => _lastRotation;

  // ── Constants ────────────────────────────────────────────────────────────────
  static const double _minFaceRatio       = 0.25; // > 3.0 ft (90 cm) -> Move closer
  static const double _maxFaceRatio       = 0.45; // < 2.0 ft (60 cm) -> Move farther away
  static const double _maxYaw             = 25.0;
  static const double _maxPitch           = 25.0;
  static const double _maxRoll            = 27.0;
  static const double _minEyeOpenProb     = 0.0;
  static const int    _minContourPoints   = 40;
  static const double _minEyeWidthRatio   = 0.25; 
  static const double _maxEyeWidthRatio   = 0.70; 
  static const double _maxNoseLateralShift = 0.20; 
  static const double _antiSpoofingThreshold = 0.88;

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

      bool qualityMet = false;
      _failureMessage = "";

      if (faces.isNotEmpty) {
        final face = faces.first;

        if (_lastFaceRect != null) {
          final diffX = (face.boundingBox.center.dx - _lastFaceRect!.center.dx).abs();
          final diffY = (face.boundingBox.center.dy - _lastFaceRect!.center.dy).abs();
          if (diffX > imageSize.width * 0.1 || diffY > imageSize.height * 0.1) {
             _resetLiveness();
          }
        }
        _lastFaceRect = face.boundingBox;

        _updateBlinkState(face);

        final geomOk = _checkGeometry(face, logicalSize);

        bool antiSpoofOk = false;
        if (geomOk) {
          if (_isAntiSpoofingInitialized) {
            antiSpoofOk = await _checkAntiSpoofing(face, image, result.rotation);
            if (_disposed) return;
          } else {
            _failureMessage = "Security system starting...";
          }
        }

        if (geomOk && antiSpoofOk && _hasBlinked) {
          qualityMet = true;
        } else if (geomOk && antiSpoofOk && !_hasBlinked) {
          _failureMessage = "Please blink your eyes";
        }
      } else {
        _failureMessage = "Position your face in frame";
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
    _hasBlinked=true;
    final leftOpen  = face.leftEyeOpenProbability  ?? -1.0;
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
    if (!_disposed) notifyListeners();
  }

  void _resetLiveness() {
    _seenOpen   = false;
    _hasBlinked = false;
    _lastFaceRect = null;
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

  Future<bool> _checkAntiSpoofing(FaceEntity face, CameraImage image, InputImageRotation rotation) async {
    try {
      final buffer = WriteBuffer();
      for (final plane in image.planes) {
        buffer.putUint8List(plane.bytes);
      }
      final data = buffer.done();
      Uint8List rawBytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      final int width = image.width;
      final int height = image.height;
      final int expectedSize = (width * height * 1.5).toInt();
      
      Uint8List processedBytes;
      if (rawBytes.length > expectedSize) {
        processedBytes = rawBytes.sublist(0, expectedSize);
      } else {
        processedBytes = rawBytes;
      }

      final orientation = _getExifOrientation(rotation);
      
      final now = DateTime.now();
      if (_lastAntiSpoofTime != null && 
          now.difference(_lastAntiSpoofTime!).inMilliseconds < 50) {
        return _lastScore >= _antiSpoofingThreshold;
      }
      _lastAntiSpoofTime = now;

      double maxScore = -1.0;
      
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
      final isReal = maxScore >= _antiSpoofingThreshold;
      
      if (maxScore >= 0) {
        if (!isReal) {
          _failureMessage = "Spoofing detected.";
        }
      } else {
        _failureMessage = "Plugin returned no score";
      }
      return isReal;
    } catch (e) {
      debugPrint("Anti-spoof error: $e");
      String errStr = e.toString();
      if (errStr.contains("invalid yuv data size")) {
        _failureMessage = "YUV Size mismatch";
      } else {
        _failureMessage = "Anti-spoof error";
      }
      return false;
    }
  }

  bool _checkGeometry(FaceEntity face, Size logicalSize) {
    final faceRatio = face.boundingBox.width / logicalSize.width;
    if (faceRatio < _minFaceRatio) {
      _failureMessage = "Move closer (Range: 2-3 ft)";
      return false;
    }
    if (faceRatio > _maxFaceRatio) {
      _failureMessage = "Move farther away (Range: 2-3 ft)";
      return false;
    }

    if (face.headEulerAngleY.abs() > _maxYaw || 
        face.headEulerAngleX.abs() > _maxPitch || 
        face.headEulerAngleZ.abs() > _maxRoll) {
      _failureMessage = "Please look straight";
      return false;
    }

    if (face.noseBase == null || face.leftEye == null || face.rightEye == null || face.mouthCenter == null) {
      _failureMessage = "Landmarks missing";
      return false;
    }

    if ((face.leftEyeOpenProbability ?? 0.0) < _minEyeOpenProb || (face.rightEyeOpenProbability ?? 0.0) < _minEyeOpenProb) {
      _failureMessage = "Eyes closed";
      return false;
    }

    if (face.contourPointsCount < _minContourPoints) {
      _failureMessage = "Face details low";
      return false;
    }

    if (!_checkProportions(face)) {
      _failureMessage = "Proportions invalid";
      return false;
    }

    return true;
  }

  bool _checkProportions(FaceEntity face) {
    final eyeDist = (face.rightEye! - face.leftEye!).distance;
    final faceW   = face.boundingBox.width;
    final ratio   = eyeDist / faceW;
    if (ratio < _minEyeWidthRatio || ratio > _maxEyeWidthRatio) return false;

    final eyeMidX    = (face.leftEye!.dx + face.rightEye!.dx) / 2;
    final noseOffset = (face.noseBase!.dx - eyeMidX).abs() / faceW;
    return noseOffset <= _maxNoseLateralShift;
  }

  void resetOnCapture() {
    _isQualityMet = false;
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
