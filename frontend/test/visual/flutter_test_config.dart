import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:valmag/app/theme/theme.dart';

/// Tests visuels : les captures utilisent les vraies polices (Roboto et les icônes Material),
/// sinon le texte s'affiche en blocs. Elles sont fournies par le SDK Flutter.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  _VisualTestBinding();
  final fonts = _materialFonts();
  await _load(fonts, 'Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Italic.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Light.ttf',
  ]);
  await _load(fonts, 'MaterialIcons', ['MaterialIcons-Regular.otf']);
  // Police de secours pour les symboles absents de Roboto (« → »), comme sur les appareils réels.
  final dejaVu = Directory('/usr/share/fonts/TTF');
  if (File('${dejaVu.path}/DejaVuSans.ttf').existsSync()) {
    await _load(dejaVu, 'DejaVu Sans', ['DejaVuSans.ttf']);
    AppTheme.testFontFallback = const ['DejaVu Sans'];
  }
  // Police à chasse fixe du ticket de caisse, embarquée dans l'application.
  await _load(Directory('assets/fonts'), 'ReceiptMono', ['DejaVuSansMono.ttf', 'DejaVuSansMono-Bold.ttf']);
  await testMain();
}

/// Dossier `bin/cache/artifacts/material_fonts` du SDK, retrouvé depuis le moteur de test
/// (`<sdk>/bin/cache/artifacts/engine/<plateforme>/flutter_tester`) ou FLUTTER_ROOT.
Directory _materialFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  final candidates = [
    if (root != null) Directory('$root/bin/cache/artifacts/material_fonts'),
    for (var dir = File(Platform.resolvedExecutable).parent; dir.parent.path != dir.path; dir = dir.parent)
      Directory('${dir.path}/material_fonts'),
  ];
  return candidates.firstWhere(
    (dir) => dir.existsSync(),
    orElse: () =>
        throw StateError('Polices Material introuvables dans le SDK Flutter (lancez une fois `flutter precache`).'),
  );
}

Future<void> _load(Directory dir, String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final name in files) {
    final file = File('${dir.path}/$name');
    if (file.existsSync()) {
      loader.addFont(file.readAsBytes().then((bytes) => ByteData.sublistView(Uint8List.fromList(bytes))));
    }
  }
  await loader.load();
}

/// Les tests remplacent normalement les ombres par un trait noir (visible en thème clair) :
/// les captures gardent ici les vraies ombres, comme sur l'appareil.
class _VisualTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get disableShadows => false;
}
