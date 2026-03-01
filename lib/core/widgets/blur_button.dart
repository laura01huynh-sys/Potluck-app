import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../constants.dart';

/// Generic blurred pill button used in app bars (e.g. \"Select\" / \"Cancel\").
class PotluckBlurButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const PotluckBlurButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.rectangle,
            color: Colors.white.withOpacity(0.75),
            border: Border.all(
              color: Colors.white.withOpacity(0.85),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: TextButton(
            onPressed: onPressed,
            child: Text(
              label,
              style: const TextStyle(
                color: kDeepForestGreen,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

