import 'package:flutter/material.dart';

// Design system colors
const Color kBoneCreame = Color.fromARGB(255, 239, 229, 203);
const Color kDarkerCreame = Color.fromARGB(255, 233, 228, 207);
const Color kDeepForestGreen = Color.fromARGB(255, 51, 93, 80);
const Color kMutedGold = Color.fromARGB(255, 203, 179, 98);
const Color kSoftSlateGray = Color(0xFF4F6D7A);
const Color kSageGreen = kDeepForestGreen;
const Color kSoftTerracotta = Color(0xFFE2725B);
const Color kCharcoal = Color(0xFF333333);

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }

  String capitalizeWords() {
    if (isEmpty) return this;
    return split(' ')
        .map((word) => word.isEmpty ? word : word.capitalize())
        .join(' ');
  }
}
