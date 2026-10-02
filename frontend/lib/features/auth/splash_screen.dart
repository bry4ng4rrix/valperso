import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../app/theme/dimensions.dart';

/// Affiché pendant la reprise de la session au démarrage.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(Radii.lg),
              ),
              child: Icon(Icons.storefront, color: Theme.of(context).colorScheme.onPrimary, size: 36),
            ),
            const SizedBox(height: Gaps.lg),
            Text(AppInfo.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Gaps.xl),
            const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          ],
        ),
      ),
    );
  }
}
