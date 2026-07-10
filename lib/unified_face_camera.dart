import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'src/providers/face_camera_view_model.dart';
import 'src/services/face_detector_service.dart';
import 'src/widgets/face_overlay.dart';
import 'src/widgets/shutter_button.dart';
import 'unified_face_camera_platform_interface.dart';

export 'src/models/face_entity.dart';
export 'src/providers/face_camera_view_model.dart';
export 'src/services/face_detector_service.dart';
export 'src/widgets/face_overlay.dart';
export 'src/widgets/shutter_button.dart';

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

enum CameraAspectRatio {
  ratio16_9,
  ratio4_3,
  ratio1_1,
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

      _cameraController = CameraController(
        target,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      // Sync default flash mode
      try {
        await _cameraController!.setFlashMode(_flashMode);
      } catch (e) {
        debugPrint('Flash mode initial sync failed: $e');
      }

      _cameraController!.startImageStream(_onFrameAvailable);
      setState(() => _isControllerReady = true);
    } catch (e) {
      widget.onError?.call('Failed to initialize camera: $e');
    }
  }

  void _onFrameAvailable(CameraImage image) {
    if (_cameraController == null || !_isControllerReady) return;
    _viewModel.handleImageAnalysis(image, _cameraController!);
  }

  /// Stops the image stream only if the camera is actually streaming.
  /// Guards against the CameraException thrown when stopImageStream() is
  /// called while isStreamingImages == false.
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

    // Capture the current description BEFORE disposing so we can find the other camera.
    final previousDescription = _cameraController?.description;

    try {
      await _safeStopStream(_cameraController);
      final oldController = _cameraController;
      _cameraController = null;
      // Dispose the old controller first, THEN build the new one.
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

      _cameraController = CameraController(
        next,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      // Sync flash mode to the newly initialized controller
      try {
        await _cameraController!.setFlashMode(_flashMode);
      } catch (e) {
        debugPrint('Flash mode switch sync failed: $e');
      }

      setState(() => _isControllerReady = true);
      _cameraController!.startImageStream(_onFrameAvailable);

      // 3-second cooldown: shutter stays disabled so liveness re-validates
      // on a fresh set of frames from the new camera.
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

  IconData _getFlashIcon() {
    switch (_flashMode) {
      case FlashMode.off:
        return Icons.flash_off;
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.always:
        return Icons.flash_on;
      case FlashMode.torch:
        return Icons.flashlight_on;
    }
  }

  String _getAspectRatioLabel() {
    switch (_aspectRatio) {
      case CameraAspectRatio.ratio16_9:
        return '16:9';
      case CameraAspectRatio.ratio4_3:
        return '4:3';
      case CameraAspectRatio.ratio1_1:
        return '1:1';
    }
  }

  Future<void> _capture() async {
    if (!_viewModel.isQualityMet || _isSaving || _isSwitching) return;

    setState(() => _isSaving = true);
    try {
      // 1. Check and request location permission using Method Channel
      try {
        final hasLocPermission =
            await UnifiedFaceCameraPlatform.instance.checkLocationPermission();
        if (!hasLocPermission) {
          await UnifiedFaceCameraPlatform.instance.requestLocationPermission();
        }
      } catch (e) {
        debugPrint('Location permission request failed: $e');
      }

      // 2. Fetch current Location using Method Channel
      double? latitude;
      double? longitude;
      try {
        final loc = await UnifiedFaceCameraPlatform.instance.getLocation();
        if (loc != null) {
          latitude = loc['latitude'];
          longitude = loc['longitude'];
        }
      } catch (e) {
        debugPrint('Failed to fetch location from Method Channel: $e');
      }

      await _safeStopStream(_cameraController);
      final XFile file = await _cameraController!.takePicture();

      debugPrint('Picture taken: ${file.path}');
      debugPrint('Adding native timestamp with lat: $latitude, lng: $longitude...');

      final String? timestampedPath = await UnifiedFaceCameraPlatform.instance
          .addTimestamp(file.path, latitude: latitude, longitude: longitude);

      debugPrint('Timestamped path: $timestampedPath');

      _viewModel.resetOnCapture();
      widget.onCapture(timestampedPath ?? file.path);
    } catch (e) {
      debugPrint('Capture failed: $e');
      widget.onError?.call('Capture failed: $e');
      // Restart stream so the camera stays live after a failed capture
      if (mounted &&
          _cameraController != null &&
          _cameraController!.value.isInitialized &&
          !_cameraController!.value.isStreamingImages) {
        _cameraController!.startImageStream(_onFrameAvailable);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _safeStopStream(_cameraController);
    _cameraController?.dispose();
    _viewModel.dispose();
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

    double targetRatio;
    switch (_aspectRatio) {
      case CameraAspectRatio.ratio16_9:
        targetRatio = 9 / 16;
        break;
      case CameraAspectRatio.ratio4_3:
        targetRatio = 3 / 4;
        break;
      case CameraAspectRatio.ratio1_1:
        targetRatio = 1 / 1;
        break;
    }

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
                      final previewAspectRatio = _cameraController?.value.aspectRatio ?? 1.0;
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

        // ── Top Controls ──────────────────────────────────────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          right: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Flash Toggle Button
              GestureDetector(
                onTap: _toggleFlash,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black54,
                  ),
                  child: Icon(
                    _getFlashIcon(),
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),

              // Aspect Ratio Toggle Button
              GestureDetector(
                onTap: _toggleAspectRatio,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.black54,
                  ),
                  child: Text(
                    _getAspectRatioLabel(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Status Message ────────────────────────────────────────────────
        ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            final msg = _viewModel.failureMessage;
            if (msg.isEmpty) return const SizedBox.shrink();
            return Positioned(
              top: MediaQuery.of(context).padding.top + 70,
              left: 16,
              right: 16,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    msg,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
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
            if (score < 0) return const SizedBox.shrink();
            return Positioned(
              bottom: 130,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'Liveness: ${score.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: score >= 0.88 ? Colors.greenAccent : Colors.orange,
                    fontSize: 12,
                  ),
                ),
              ),
            );
          },
        ),

        // ── Cooldown Banner ───────────────────────────────────────────────
        if (_isCooldown)
          Positioned(
            bottom: 110,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Validating new camera…',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),

        // ── Bottom Controls ───────────────────────────────────────────────
        Positioned(
          bottom: 36,
          left: 0,
          right: 0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Switch camera
                GestureDetector(
                  onTap: (_isSwitching || _isCooldown) ? null : _switchCamera,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                    child: Icon(
                      Icons.flip_camera_ios,
                      color: (_isSwitching || _isCooldown) ? Colors.white38 : Colors.white,
                      size: 26,
                    ),
                  ),
                ),

                // Shutter
                ListenableBuilder(
                  listenable: _viewModel,
                  builder: (context, _) {
                    final enabled = _viewModel.isQualityMet &&
                        !_isSwitching &&
                        !_isSaving &&
                        !_isCooldown;
                    return ShutterButton(
                      isEnabled: enabled,
                      onTap: enabled ? _capture : null,
                    );
                  },
                ),

                // Close Button or Spacer
                if (widget.onClose != null)
                  GestureDetector(
                    onTap: widget.onClose,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 52),
              ],
            ),
          ),
        ),

        // ── Saving overlay ────────────────────────────────────────────────
        if (_isSaving)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Processing Verification...',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
