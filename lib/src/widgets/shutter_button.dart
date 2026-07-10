import 'package:flutter/material.dart';

class ShutterButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool isEnabled;

  const ShutterButton({super.key, this.onTap, required this.isEnabled});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isEnabled ? Colors.white : Colors.white.withValues(alpha: 0.3),
            width: 4,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isEnabled ? Colors.white : Colors.white.withValues(alpha: 0.1),
            ),
          ),
        ),
      ),
    );
  }
}
