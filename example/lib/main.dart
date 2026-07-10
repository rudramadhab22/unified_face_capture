import 'dart:io';

import 'package:flutter/material.dart';
import 'package:unified_face_camera/unified_face_camera.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Unified Face Camera Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A5F),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const CaptureScreen(),
    );
  }
}

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  String? _capturedImagePath;
  bool _showCamera = false;

  void _onCapture(String path) {
    setState(() {
      _capturedImagePath = path;
      _showCamera = false;
    });
  }

  void _retakePhoto() {
    setState(() {
      _capturedImagePath = null;
      _showCamera = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: _showCamera
          ? _buildCameraScreen()
          : _capturedImagePath != null
              ? _buildResultScreen()
              : _buildHomeScreen(),
    );
  }

  Widget _buildHomeScreen() {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.face, size: 96, color: Color(0xFF4FC3F7)),
              const SizedBox(height: 24),
              const Text(
                'Unified Face Capture',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Secure, offline face capture with liveness detection '
                'and automatic timestamp embedding.',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white60,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              _featureRow(Icons.security, 'Passive anti-spoofing detector'),
              _featureRow(Icons.center_focus_strong, 'Real-time face alignment'),
              _featureRow(Icons.schedule, 'Automatic timestamp (DD-MM-YYYY hh:mm AM/PM)'),
              _featureRow(Icons.photo_camera, 'Capture only when validation passes'),
              const SizedBox(height: 56),
              FilledButton.icon(
                onPressed: () async {
                  final hasPermission = await UnifiedFaceCamera.checkPermission();
                  if (!mounted) return;
                  if (hasPermission) {
                    setState(() => _showCamera = true);
                    return;
                  }
                  final granted = await UnifiedFaceCamera.requestPermission();
                  if (!mounted) return;
                  if (granted) {
                    setState(() => _showCamera = true);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Camera permission is required to capture face.',
                          style: TextStyle(color: Colors.white),
                        ),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.camera_alt),
                label: const Text('Start Face Capture'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _featureRow(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF4FC3F7)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraScreen() {
    return SafeArea(
      child: UnifiedFaceCamera(
        onCapture: _onCapture,
        onClose: () => setState(() => _showCamera = false),
        onError: (error) {
          if (!mounted) return;
          setState(() => _showCamera = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Camera error: $error',
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        },
      ),
    );
  }

  Widget _buildResultScreen() {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => setState(() => _capturedImagePath = null),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
                const Text(
                  'Captured Image',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  File(_capturedImagePath!),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) => const Center(
                    child: Text(
                      'Could not load image',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(
                  _capturedImagePath!.split('/').last,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _retakePhoto,
                        icon: const Icon(Icons.replay, color: Colors.white70),
                        label: const Text(
                          'Retake',
                          style: TextStyle(color: Colors.white70),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          side: const BorderSide(color: Colors.white30),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Image saved at:\n${_capturedImagePath!}',
                              ),
                              backgroundColor: const Color(0xFF1565C0),
                            ),
                          );
                        },
                        icon: const Icon(Icons.check),
                        label: const Text('Use Photo'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          backgroundColor: const Color(0xFF1565C0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
