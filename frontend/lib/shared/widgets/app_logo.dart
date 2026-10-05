import 'package:flutter/material.dart';

import '../../app/theme/dimensions.dart';

/// Logo Valheri Wear (doré sur fond noir), aux coins arrondis comme une icône d'application.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 64});

  static const asset = 'assets/images/logo.jpg';

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size >= 64 ? Radii.lg : Radii.md),
      child: Image.asset(asset, width: size, height: size, fit: BoxFit.cover, semanticLabel: 'Logo Valheri Wear'),
    );
  }
}
