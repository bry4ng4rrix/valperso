import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app/app.dart';
import 'app/dependencies.dart';
import 'core/web/browser.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'fr';
  await initializeDateFormatting('fr');

  final dependencies = AppDependencies(storage: createAppStore());
  // L'écran de démarrage s'affiche pendant la reprise de la session.
  unawaited(dependencies.start());
  runApp(CommerceApp(dependencies: dependencies));
}
