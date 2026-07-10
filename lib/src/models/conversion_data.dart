import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class ConversionData {
  final InputImage inputImage;
  final Uint8List fullYuvBytes;

  ConversionData({
    required this.inputImage,
    required this.fullYuvBytes,
  });
}
