import 'package:flutter/material.dart';

class CameraSavingOverlay extends StatelessWidget {
  final bool isSaving;

  const CameraSavingOverlay({super.key, required this.isSaving});

  @override
  Widget build(BuildContext context) {
    if (!isSaving) {
      return const SizedBox.shrink();
    }

    return Container(
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
    );
  }
}
