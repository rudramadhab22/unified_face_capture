# unified_face_camera

[![pub package](https://img.shields.io/pub/v/unified_face_camera.svg)](https://pub.dev/packages/unified_face_camera)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-lightgrey.svg)](https://flutter.dev)

**Production-ready face capture for Flutter** — a drop-in camera widget with real-time face alignment, liveness anti-spoofing, smart quality gates, and tamper-evident timestamp embedding. Built for KYC, attendance, identity verification, and any workflow that needs trustworthy face photos.

> One widget. Offline ML Kit detection. Native timestamp overlay. No server required for liveness checks.

---

## Why unified_face_camera?

Most camera plugins give you a preview. This one gives you a **validated capture pipeline**:

| Capability | What you get |
|------------|--------------|
| **Face alignment** | Live overlay + guided feedback ("move closer", "look straight", "blink") |
| **Quality gates** | Distance, head pose, eye contour, and blink checks before shutter unlocks |
| **Liveness** | Passive anti-spoofing score on every frame — blocks photo-of-a-photo attacks |
| **Smart capture** | Shutter stays disabled until all checks pass on a fresh frame |
| **Timestamp proof** | Native overlay on the saved image (date, time, optional GPS) |
| **Cross-platform** | Android & iOS with a single Dart API |

---

## Features

- Real-time **ML Kit** face detection with animated overlay
- **Passive liveness** via `face_anti_spoofing_detector`
- **Blink detection** to confirm a live subject
- **Head pose validation** (yaw, pitch, roll limits)
- **Distance checks** — face must fill the frame correctly
- Front / back **camera switch** with cooldown re-validation
- **Flash** modes (off, auto, always, torch)
- Portrait-locked capture with **EXIF rotation** fix
- Optional **GPS geotag** burned into the image via native code
- Static permission helpers — `checkPermission()` / `requestPermission()`

---

## Quick start

### 1. Add the dependency

```yaml
dependencies:
  unified_face_camera: ^0.0.1
```

### 2. Request permission & show the widget

```dart
import 'package:flutter/material.dart';
import 'package:unified_face_camera/unified_face_camera.dart';

class FaceCapturePage extends StatelessWidget {
  const FaceCapturePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: UnifiedFaceCamera(
        useFrontCamera: true,
        onCapture: (path) {
          // Final image path — timestamp (and optional GPS) already applied
          debugPrint('Captured: $path');
          Navigator.of(context).pop(path);
        },
        onError: (error) => debugPrint('Error: $error'),
        onClose: () => Navigator.of(context).pop(),
      ),
    );
  }
}
```

### 3. Check permissions first (recommended)

```dart
final granted = await UnifiedFaceCamera.requestPermission();
if (!granted) {
  // Show a dialog explaining why camera access is needed
  return;
}
```

---

## How it works

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│ Camera feed │ ──► │ ML Kit detection │ ──► │ Quality + blink │
└─────────────┘     └──────────────────┘     │     checks      │
                                              └────────┬────────┘
                                                       │
                       ┌──────────────────┐            ▼
                       │ Anti-spoof score │ ◄── Liveness gate
                       └────────┬─────────┘
                                │ pass
                                ▼
                       ┌──────────────────┐     ┌─────────────────┐
                       │  User taps       │ ──► │ Native timestamp│
                       │  shutter         │     │ + optional GPS  │
                       └──────────────────┘     └─────────────────┘
```

1. Camera streams frames to ML Kit for face detection.
2. The view model validates distance, pose, contours, and blink.
3. Anti-spoofing runs on the face crop — capture unlocks only above threshold.
4. On shutter press, the image is rotated, timestamped natively, and returned via `onCapture`.

---

## Platform setup

### Android

**Minimum SDK 24** in `android/app/build.gradle.kts`:

```kotlin
defaultConfig {
    minSdk = 24
}
```

**ML Kit face model** — add inside `<application>` in `AndroidManifest.xml`:

```xml
<meta-data
    android:name="com.google.mlkit.vision.DEPENDENCIES"
    android:value="face" />
```

Camera and location permissions are merged by the plugin. Request location at runtime if you want GPS on the timestamp.

### iOS

Add to `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>We need camera access to capture your face photo for verification.</string>

<!-- Optional — only if you want GPS on the timestamp -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>We use your location to embed GPS coordinates in captured photos.</string>
```

Minimum iOS version: **13.0**.

---

## API reference

### `UnifiedFaceCamera`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `onCapture` | `Function(String path)` | Yes | Called with the final image file path after timestamp processing |
| `onError` | `Function(String error)?` | No | Called on unrecoverable camera or capture errors |
| `useFrontCamera` | `bool` | No | Use front camera. Default: `false` (back camera) |
| `onClose` | `VoidCallback?` | No | If set, shows a close button that invokes this callback |

### Static methods

| Method | Returns | Description |
|--------|---------|-------------|
| `checkPermission()` | `Future<bool>` | Whether camera permission is already granted |
| `requestPermission()` | `Future<bool>` | Prompts for camera permission |

### Exported types

For advanced integration you can also use:

- `FaceCameraViewModel` — state and validation logic
- `FaceDetectorService` — ML Kit wrapper
- `FaceOverlay` — custom overlay widget
- `FaceEntity`, `CameraAspectRatio`, `ShutterButton`

---

## Use cases

- **KYC / onboarding** — guided selfie with liveness before account creation
- **Attendance & field apps** — geotagged face proof with embedded timestamp
- **Access control** — consistent face framing before backend verification
- **Compliance workflows** — tamper-evident capture metadata on every photo

---

## Example app

A full demo with permission flow, capture preview, and retake is in [`example/lib/main.dart`](example/lib/main.dart).

Run it locally:

```bash
cd example
flutter run
```

---

## Requirements

| | Minimum |
|---|---------|
| Dart SDK | `>=3.0.0` |
| Flutter | `>=3.3.0` |
| Android | API 24+ |
| iOS | 13.0+ |

---

## Contributing

Issues and pull requests are welcome on [GitHub](https://github.com/rudramadhab22/unified_face_capture).

---

## License

MIT © [OASYS TSPL](LICENSE)
