import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_exif_rotation/flutter_exif_rotation.dart';
import 'src/providers/face_camera_view_model.dart';
import 'src/services/face_detector_service.dart';
import 'src/widgets/face_overlay.dart';

import 'unified_face_camera_platform_interface.dart';

export 'src/models/camera_aspect_ratio.dart';
export 'src/models/face_entity.dart';
export 'src/providers/face_camera_view_model.dart';
export 'src/services/face_detector_service.dart';
export 'src/widgets/face_overlay.dart';
export 'src/widgets/shutter_button.dart';

import 'src/models/camera_aspect_ratio.dart';
import 'src/widgets/camera_controls_overlay.dart';
import 'src/widgets/camera_saving_overlay.dart';
import 'src/widgets/face_feedback_text.dart';

class UnifiedFaceCamera extends StatefulWidget {
  const UnifiedFaceCamera({
    super.key,
    required this.onCapture,
    this.onError,
    this.useFrontCamera = false,
    this.onClose,
  });

  /// Called with the final (timestamped) image path after a successful capture.
  final Function(String path) onCapture;

  /// Called when an unrecoverable error occurs.
  final Function(String error)? onError;

  /// Whether to use the front-facing camera. Defaults to [false] (back camera).
  final bool useFrontCamera;

  /// Optional callback invoked when the user taps the close button.
  /// If provided, a close button is shown in the bottom controls row.
  final VoidCallback? onClose;

  /// Checks whether the camera permission is granted.
  static Future<bool> checkPermission() {
    return UnifiedFaceCameraPlatform.instance.checkCameraPermission();
  }

  /// Requests the camera permission. Returns `true` if granted.
  static Future<bool> requestPermission() {
    return UnifiedFaceCameraPlatform.instance.requestCameraPermission();
  }

  @override
  State<UnifiedFaceCamera> createState() => _UnifiedFaceCameraState();
}


class _UnifiedFaceCameraState extends State<UnifiedFaceCamera> {
  CameraController? _cameraController;
  late final FaceCameraViewModel _viewModel;
  bool _isSaving = false;
  bool _isSwitching = false;
  bool _isControllerReady = false;

  /// True for 3 seconds after a camera switch to prevent accidental captures
  /// on an unvalidated frame.
  bool _isCooldown = false;

  /// Current UI aspect ratio setting
  CameraAspectRatio _aspectRatio = CameraAspectRatio.ratio16_9;

  /// Current camera flash mode
  FlashMode _flashMode = FlashMode.off;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _viewModel = FaceCameraViewModel(FaceDetectorService());
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        widget.onError?.call('No cameras found');
        return;
      }

      final target = widget.useFrontCamera
          ? cameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.front,
              orElse: () => cameras.first,
            )
          : cameras.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.back,
              orElse: () => cameras.first,
            );

      _cameraController = await _openCamera(target);
      if (_cameraController == null) {
        widget.onError?.call('Failed to initialize camera: unsupported resolution');
        return;
      }
      if (!mounted) return;

      try {
        await _cameraController!.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (e) {
        debugPrint('Lock orientation failed: $e');
      }

      try {
        await _cameraController!.setFlashMode(_flashMode);
      } catch (e) {
        debugPrint('Flash mode initial sync failed: $e');
      }

      // Prefer auto exposure — helps low-light stability on release builds.
      try {
        await _cameraController!.setExposureMode(ExposureMode.auto);
      } catch (e) {
        debugPrint('Exposure mode failed: $e');
      }

      try {
        await _cameraController!.startImageStream(_onFrameAvailable);
      } catch (e) {
        debugPrint('startImageStream failed: $e');
        widget.onError?.call('Failed to start camera stream: $e');
        return;
      }
      if (!mounted) return;
      setState(() => _isControllerReady = true);
    } catch (e) {
      widget.onError?.call('Failed to initialize camera: $e');
    }
  }

  /// Tries high → medium → low so older / low-memory devices still open a camera.
  Future<CameraController?> _openCamera(CameraDescription target) async {
    const presets = [
      ResolutionPreset.high,
      ResolutionPreset.medium,
      ResolutionPreset.low,
    ];
    for (final preset in presets) {
      final controller = CameraController(
        target,
        preset,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      try {
        await controller.initialize();
        return controller;
      } catch (e) {
        debugPrint('Camera init failed at $preset: $e');
        try {
          await controller.dispose();
        } catch (_) {}
      }
    }
    return null;
  }

  void _onFrameAvailable(CameraImage image) {
    if (_cameraController == null || !_isControllerReady) return;
    _viewModel.handleImageAnalysis(image, _cameraController!);
  }

  /// Stops the image stream only if the camera is actually streaming.
  Future<void> _safeStopStream(CameraController? controller) async {
    if (controller == null) return;
    try {
      if (controller.value.isInitialized && controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (e) {
      debugPrint('stopImageStream guard: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (_isSwitching) return;
    setState(() {
      _isSwitching = true;
      _isControllerReady = false;
    });
    _viewModel.forceResetLiveness();

    final previousDescription = _cameraController?.description;

    try {
      await _safeStopStream(_cameraController);
      final oldController = _cameraController;
      _cameraController = null;
      await oldController?.dispose();

      final cameras = await availableCameras();
      CameraDescription next;
      if (cameras.length > 1 && previousDescription != null) {
        next = cameras.firstWhere(
          (c) => c != previousDescription,
          orElse: () => cameras.first,
        );
      } else {
        next = cameras.first;
      }

      _cameraController = await _openCamera(next);
      if (_cameraController == null || !mounted) {
        widget.onError?.call('Failed to switch camera: could not open camera');
        return;
      }

      try {
        await _cameraController!.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (e) {
        debugPrint('Lock orientation failed: $e');
      }

      try {
        await _cameraController!.setFlashMode(_flashMode);
      } catch (e) {
        debugPrint('Flash mode switch sync failed: $e');
      }

      try {
        await _cameraController!.setExposureMode(ExposureMode.auto);
      } catch (_) {}

      try {
        await _cameraController!.startImageStream(_onFrameAvailable);
      } catch (e) {
        debugPrint('startImageStream after switch failed: $e');
        widget.onError?.call('Failed to switch camera: $e');
        return;
      }

      setState(() => _isControllerReady = true);

      setState(() => _isCooldown = true);
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) setState(() => _isCooldown = false);
    } catch (e) {
      widget.onError?.call('Failed to switch camera: $e');
    } finally {
      if (mounted) setState(() => _isSwitching = false);
    }
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null || !_isControllerReady) return;
    FlashMode nextMode;
    switch (_flashMode) {
      case FlashMode.off:
        nextMode = FlashMode.auto;
        break;
      case FlashMode.auto:
        nextMode = FlashMode.always;
        break;
      case FlashMode.always:
        nextMode = FlashMode.torch;
        break;
      case FlashMode.torch:
        nextMode = FlashMode.off;
        break;
    }
    try {
      await _cameraController!.setFlashMode(nextMode);
      setState(() {
        _flashMode = nextMode;
      });
    } catch (e) {
      debugPrint('Failed to set flash mode: $e');
    }
  }

  void _toggleAspectRatio() {
    setState(() {
      switch (_aspectRatio) {
        case CameraAspectRatio.ratio16_9:
          _aspectRatio = CameraAspectRatio.ratio4_3;
          break;
        case CameraAspectRatio.ratio4_3:
          _aspectRatio = CameraAspectRatio.ratio1_1;
          break;
        case CameraAspectRatio.ratio1_1:
          _aspectRatio = CameraAspectRatio.ratio16_9;
          break;
      }
    });
  }



  Future<void> _capture() async {
    final controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        !_isControllerReady) {
      return;
    }

    if (!_viewModel.isQualityMet || _isSaving || _isSwitching || _isCooldown) {
      return;
    }

    if (!_viewModel.isDetectionFresh) {
      _viewModel.setTransientMessage('Hold steady and try again');
      debugPrint('Capture blocked: detection is stale');
      return;
    }

    setState(() => _isSaving = true);

    try {
      // MUST stop the image stream before takePicture (required on many Androids).
      await _safeStopStream(controller);

      if (!controller.value.isInitialized) {
        throw StateError('Camera disposed before capture');
      }

      final XFile file = await controller.takePicture();

      _cameraController = null;
      if (mounted) {
        setState(() {
          _isControllerReady = false;
        });
      }
      try {
        await controller.dispose();
      } catch (e) {
        debugPrint('Controller dispose after capture: $e');
      }

      double? latitude;
      double? longitude;
      try {
        final hasLocPermission =
            await UnifiedFaceCameraPlatform.instance.checkLocationPermission();
        if (!hasLocPermission) {
          await UnifiedFaceCameraPlatform.instance.requestLocationPermission();
        }
        final loc = await UnifiedFaceCameraPlatform.instance.getLocation();
        if (loc != null) {
          latitude = loc['latitude'];
          longitude = loc['longitude'];
        }
      } catch (e) {
        debugPrint('Background location fetch failed: $e');
      }

      File fixedFile = await FlutterExifRotation.rotateImage(path: file.path);

      String? timestampedPath;
      try {
        timestampedPath = await UnifiedFaceCameraPlatform.instance
            .addTimestamp(fixedFile.path, latitude: latitude, longitude: longitude);
      } catch (e) {
        debugPrint('Timestamp overlay failed, returning raw capture: $e');
      }

      _viewModel.resetOnCapture();
      widget.onCapture(timestampedPath ?? fixedFile.path);
    } catch (e) {
      debugPrint('Capture failed: $e');
      widget.onError?.call('Capture failed: $e');
      if (mounted && _cameraController == null) {
        await _initCamera();
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    final controller = _cameraController;
    _cameraController = null;
    _viewModel.dispose();
    Future<void>(() async {
      await _safeStopStream(controller);
      try {
        await controller?.dispose();
      } catch (_) {}
    });
    super.dispose();
  }

  Widget _buildCameraPreview(double targetRatio) {
    if (_cameraController == null || !_isControllerReady) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewAspectRatio = _cameraController!.value.aspectRatio;
        final portraitPreviewRatio = 1 / previewAspectRatio;

        double previewScale;
        if (portraitPreviewRatio < targetRatio) {
          previewScale = targetRatio / portraitPreviewRatio;
        } else {
          previewScale = portraitPreviewRatio / targetRatio;
        }

        return Transform.scale(
          scale: previewScale,
          child: Center(
            child: AspectRatio(
              aspectRatio: portraitPreviewRatio,
              child: CameraPreview(_cameraController!),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_isControllerReady) {
      return const Center(child: CircularProgressIndicator());
    }

    final isFront =
        _cameraController!.description.lensDirection == CameraLensDirection.front;

    const targetRatio = 3 / 4; // Strictly 4:3

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Camera Preview + Face Overlay ──────────────────────────────────
        Center(
          child: ClipRect(
            child: AspectRatio(
              aspectRatio: targetRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCameraPreview(targetRatio),
                  ListenableBuilder(
                    listenable: _viewModel,
                    builder: (context, _) {
                      final previewAspectRatio =
                          _cameraController?.value.aspectRatio ?? 1.0;
                      return FaceOverlay(
                        faces: _viewModel.detectedFaces,
                        imageSize: _viewModel.lastImageSize,
                        rotation: _viewModel.lastRotation,
                        isQualityMet: _viewModel.isQualityMet,
                        isFrontCamera: isFront,
                        targetAspectRatio: targetRatio,
                        previewAspectRatio: previewAspectRatio,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Camera Controls (Top & Bottom) ────────────────────────────────
        ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            return CameraControlsOverlay(
              flashOn: _flashMode == FlashMode.torch || _flashMode == FlashMode.always,
              onToggleFlash: _toggleFlash,
              aspectRatio: _aspectRatio,
              onToggleAspectRatio: _toggleAspectRatio,
              isSwitching: _isSwitching,
              isCooldown: _isCooldown,
              onSwitchCamera: _switchCamera,
              isQualityMet: _viewModel.isQualityMet && _viewModel.isDetectionFresh,
              isSaving: _isSaving,
              onCapture: _capture,
              onClose: widget.onClose,
              showAspectRatioOption: false, // Hide aspect ratio option
            );
          },
        ),

        // ── Status Message / Feedback Text ────────────────────────────────
        ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            return Positioned(
              bottom: 110,
              left: 16,
              right: 16,
              child: Center(
                child: FaceFeedbackText(
                  message: _isCooldown
                      ? 'Validating new camera…'
                      : _viewModel.failureMessage,
                  isQualityMet: _viewModel.isQualityMet &&
                      _viewModel.isDetectionFresh &&
                      !_isCooldown,
                ),
              ),
            );
          },
        ),

        // ── Score Debug ───────────────────────────────────────────────────
        ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            final score = _viewModel.lastScore;
            if (score < 0 || _isCooldown) return const SizedBox.shrink();
            return Positioned(
              bottom: 160,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'Liveness: ${score.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: score >= 0.80 ? Colors.greenAccent : Colors.orange,
                    fontSize: 12,
                  ),
                ),
              ),
            );
          },
        ),

        // ── Saving overlay ────────────────────────────────────────────────
        CameraSavingOverlay(isSaving: _isSaving),
      ],
    );
  }
}
