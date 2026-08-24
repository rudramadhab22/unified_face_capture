## 0.0.2

* More stable capture UX: shutter hysteresis, calm guidance, primary-face lock.
* Fix multi-face tracking jumping that blocked capture.
* Stop image stream before `takePicture` (Android reliability).
* Low-light support: luma detection, exposure nudge, torch guidance, softer geometry in dim light.
* Release / Play Store parity: longer freshness/hold windows in `kReleaseMode`, consumer ProGuard rules.
* Camera resolution fallback (high → medium → low) and OOM-safe watermarking.
* Capture recovery when photo fails; watermark failure no longer drops the image.
* Blink logic and `_minEyeOpenProb` unchanged.

## 0.0.1

* Initial release.
* `UnifiedFaceCamera` widget with real-time face detection overlay.
* Face quality gates (distance, pose, blink, contour checks).
* Passive liveness anti-spoofing via `face_anti_spoofing_detector`.
* Camera switch, flash modes, and portrait-locked capture.
* Native timestamp embedding with optional GPS coordinates (Android & iOS).
* Permission helpers for camera and location.
