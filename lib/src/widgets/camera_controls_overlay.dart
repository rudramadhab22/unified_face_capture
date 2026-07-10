import 'package:flutter/material.dart';
import '../models/camera_aspect_ratio.dart';
import 'shutter_button.dart';

class CameraControlsOverlay extends StatelessWidget {
  final bool flashOn;
  final VoidCallback onToggleFlash;
  final CameraAspectRatio aspectRatio;
  final VoidCallback onToggleAspectRatio;
  final bool isSwitching;
  final bool isCooldown;
  final VoidCallback onSwitchCamera;
  final bool isQualityMet;
  final bool isSaving;
  final VoidCallback onCapture;
  final VoidCallback? onClose;

  const CameraControlsOverlay({
    super.key,
    required this.flashOn,
    required this.onToggleFlash,
    required this.aspectRatio,
    required this.onToggleAspectRatio,
    required this.isSwitching,
    required this.isCooldown,
    required this.onSwitchCamera,
    required this.isQualityMet,
    required this.isSaving,
    required this.onCapture,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Top Controls ──────────────────────────────────────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          right: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Flash Button
              GestureDetector(
                onTap: onToggleFlash,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.5),
                  ),
                  child: Icon(
                    flashOn ? Icons.flash_on : Icons.flash_off,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              // Aspect Ratio Button
              GestureDetector(
                onTap: onToggleAspectRatio,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.black.withValues(alpha: 0.5),
                  ),
                  child: Text(
                    _getAspectRatioString(aspectRatio),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
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
                  onTap: (isSwitching || isCooldown) ? null : onSwitchCamera,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                    child: Icon(
                      Icons.flip_camera_ios,
                      color: (isSwitching || isCooldown)
                          ? Colors.white38
                          : Colors.white,
                      size: 26,
                    ),
                  ),
                ),

                // Shutter
                ShutterButton(
                  isEnabled: isQualityMet && !isSwitching && !isSaving && !isCooldown,
                  onTap: (isQualityMet && !isSwitching && !isSaving && !isCooldown)
                      ? onCapture
                      : null,
                ),

                // Close Button or Spacer
                if (onClose != null)
                  GestureDetector(
                    onTap: onClose,
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
      ],
    );
  }

  String _getAspectRatioString(CameraAspectRatio ratio) {
    switch (ratio) {
      case CameraAspectRatio.ratio16_9:
        return '16:9';
      case CameraAspectRatio.ratio4_3:
        return '4:3';
      case CameraAspectRatio.ratio1_1:
        return '1:1';
    }
  }
}
