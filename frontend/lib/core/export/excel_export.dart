import 'dart:io';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../web/browser.dart';

/// Une colonne du fichier Excel : un en-tête et la valeur à écrire pour chaque ligne.
/// Les nombres restent des nombres dans Excel (sommes et tris possibles).
class ExportColumn<T> {
  const ExportColumn(this.header, this.value);

  final String header;
  final Object? Function(T item) value;
}

/// Construit un fichier .xlsx (une feuille) à partir des lignes et des colonnes.
List<int> buildWorkbook<T>({required String sheetName, required List<ExportColumn<T>> columns, required List<T> rows}) {
  final excel = xl.Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();
  final sheet = excel[sheetName];
  sheet.appendRow([for (final column in columns) xl.TextCellValue(column.header)]);
  for (final row in rows) {
    sheet.appendRow([for (final column in columns) _cell(column.value(row))]);
  }
  if (defaultSheet != null && defaultSheet != sheetName) excel.delete(defaultSheet);
  excel.setDefaultSheet(sheetName);
  return excel.save() ?? const [];
}

xl.CellValue? _cell(Object? value) => switch (value) {
  null => null,
  final int number => xl.IntCellValue(number),
  final double number => xl.DoubleCellValue(number),
  final DateTime date => xl.TextCellValue(DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal())),
  final bool flag => xl.TextCellValue(flag ? 'Oui' : 'Non'),
  _ => xl.TextCellValue('$value'),
};

/// Nom de fichier horodaté : ventes_2026-10-02_1530.xlsx
String exportFileName(String baseName, {DateTime? now}) =>
    '${baseName}_${DateFormat('yyyy-MM-dd_HHmm').format(now ?? DateTime.now())}.xlsx';

/// Enregistre le fichier : téléchargé par le navigateur (version web), dossier Téléchargements si
/// disponible (Linux), sinon dossier de l'application.
/// Renvoie le chemin complet du fichier (dans le navigateur : son nom).
Future<String> saveExportFile(List<int> bytes, String fileName, {Directory? directory}) async {
  if (kIsWeb) {
    downloadFile(bytes, fileName);
    return fileName;
  }
  final target = directory ?? await _exportDirectory();
  await target.create(recursive: true);
  final file = File('${target.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<Directory> _exportDirectory() async {
  try {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;
  } on UnsupportedError {
    // Plateforme sans dossier Téléchargements accessible : dossier de l'application.
  }
  return getApplicationDocumentsDirectory();
}
