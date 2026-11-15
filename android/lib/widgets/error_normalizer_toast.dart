import 'package:flutter/material.dart';
import '../theme/tokens.dart';

// Displays a non-intrusive floating toast overlay adhering to the minimal AI design standard.
class ErrorNormalizerToast extends StatelessWidget {
  final String message;

  const ErrorNormalizerToast({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 84,
      left: FlikTokens.screenMargin,
      right: FlikTokens.screenMargin,
      child: Center(
        child: AnimatedOpacity(
          duration: FlikTokens.baseMotion,
          opacity: 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: FlikTokens.surface,
              borderRadius: BorderRadius.circular(FlikTokens.radiusPill),
              border: Border.all(color: FlikTokens.line),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: FlikTokens.text,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
