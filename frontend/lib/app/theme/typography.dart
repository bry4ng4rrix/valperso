import 'package:flutter/material.dart';

/// Typographie : tailles raisonnables, lisibles sur mobile comme sur bureau.
TextTheme buildTextTheme(Color primary, Color secondary) {
  return TextTheme(
    headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: primary),
    titleLarge: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: primary),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: primary),
    titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primary),
    bodyLarge: TextStyle(fontSize: 15, color: primary),
    bodyMedium: TextStyle(fontSize: 14, color: primary),
    bodySmall: TextStyle(fontSize: 12.5, color: secondary),
    labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    labelMedium: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: secondary),
    labelSmall: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: secondary),
  );
}
