# Keep plugin classes for release / Play Store minify (R8).
-keep class com.oasystspl.unified_face_camera.** { *; }
-dontwarn com.oasystspl.unified_face_camera.**

# ML Kit face detection (common release-mode stripping issue)
-keep class com.google.mlkit.vision.face.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_face.** { *; }
-dontwarn com.google.mlkit.**
