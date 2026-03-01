import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// Stat display for profile metrics (e.g. MADE, SHARED, FOLLOWERS).
class StatItem extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;

  const StatItem({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: kMutedGold, size: 24),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: kDeepForestGreen,
            ),
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            color: kSoftSlateGray,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }
}
