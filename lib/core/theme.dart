import 'package:flutter/material.dart';

import 'constants.dart';

/// No-op page transition (instant switch, no animation).
class ZeroTransitionsBuilder extends PageTransitionsBuilder {
  const ZeroTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

/// App-wide text theme (Lora + Inter, Potluck colors).
class AppTextTheme {
  AppTextTheme._();

  static const TextTheme theme = TextTheme(
    displayLarge: TextStyle(
      fontFamily: 'Lora',
      fontSize: 32,
      fontWeight: FontWeight.bold,
      color: kDeepForestGreen,
      letterSpacing: 0.5,
    ),
    displayMedium: TextStyle(
      fontFamily: 'Lora',
      fontSize: 28,
      fontWeight: FontWeight.bold,
      color: kDeepForestGreen,
      letterSpacing: 0.5,
    ),
    headlineSmall: TextStyle(
      fontFamily: 'Lora',
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: kDeepForestGreen,
      letterSpacing: 0.5,
    ),
    titleLarge: TextStyle(
      fontFamily: 'Inter',
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: kDeepForestGreen,
      letterSpacing: 0.5,
    ),
    titleMedium: TextStyle(
      fontFamily: 'Inter',
      fontSize: 16,
      fontWeight: FontWeight.w500,
      color: kDeepForestGreen,
      letterSpacing: 0.5,
    ),
    bodyLarge: TextStyle(
      fontFamily: 'Inter',
      fontSize: 16,
      fontWeight: FontWeight.normal,
      color: kDeepForestGreen,
      letterSpacing: 0.5,
    ),
    bodyMedium: TextStyle(
      fontFamily: 'Inter',
      fontSize: 14,
      fontWeight: FontWeight.normal,
      color: kSoftSlateGray,
      letterSpacing: 0.5,
    ),
    labelMedium: TextStyle(
      fontFamily: 'Inter',
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: kSoftSlateGray,
      letterSpacing: 0.5,
    ),
  );
}
