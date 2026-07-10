import 'package:flutter/material.dart';

class FaceFeedbackText extends StatelessWidget {
  final String message;
  final bool isQualityMet;

  const FaceFeedbackText({
    super.key,
    required this.message,
    required this.isQualityMet,
  });

  @override
  Widget build(BuildContext context) {
    if (isQualityMet) {
      return const SizedBox.shrink();
    }

    if (message.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
