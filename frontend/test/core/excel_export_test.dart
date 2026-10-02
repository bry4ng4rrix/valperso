import 'dart:io';

import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:valmag/core/export/excel_export.dart';

class _Row {
  const _Row(this.name, this.quantity, this.price, this.date);

  final String name;
  final int quantity;
  final double price;
  final DateTime date;
}

void main() {
  final columns = [
    ExportColumn<_Row>('Produit', (row) => row.name),
    ExportColumn<_Row>('Quantité', (row) => row.quantity),
    ExportColumn<_Row>('Prix (Ar)', (row) => row.price),
    ExportColumn<_Row>('Date', (row) => row.date),
    ExportColumn<_Row>('Note', (row) => null),
  ];

  test('le fichier contient les en-têtes puis une ligne par élément, nombres conservés', () {
    final bytes = buildWorkbook(
      sheetName: 'Produits',
      columns: columns,
      rows: [_Row('Stylo', 10, 1000, DateTime(2026, 10, 2, 9, 30)), _Row('Cahier', 3, 2500.5, DateTime(2026, 10, 1))],
    );
    final book = xl.Excel.decodeBytes(bytes);
    expect(book.tables.keys, ['Produits']);
    final sheet = book.tables['Produits']!;
    expect(sheet.maxRows, 3);
    expect(sheet.rows[0].map((cell) => cell?.value.toString()).toList(), [
      'Produit',
      'Quantité',
      'Prix (Ar)',
      'Date',
      'Note',
    ]);
    expect(sheet.rows[1][1]?.value, isA<xl.IntCellValue>());
    expect((sheet.rows[1][1]?.value as xl.IntCellValue).value, 10);
    expect((sheet.rows[2][2]?.value as xl.DoubleCellValue).value, 2500.5);
    expect(sheet.rows[1][3]?.value.toString(), '02/10/2026 09:30');
  });

  test('nom de fichier horodaté', () {
    expect(exportFileName('ventes', now: DateTime(2026, 10, 2, 15, 7)), 'ventes_2026-10-02_1507.xlsx');
  });

  test('enregistrement dans le dossier demandé', () async {
    final directory = await Directory.systemTemp.createTemp('export_test');
    addTearDown(() => directory.delete(recursive: true));
    final path = await saveExportFile([1, 2, 3], 'test.xlsx', directory: directory);
    expect(File(path).existsSync(), isTrue);
    expect(File(path).readAsBytesSync(), [1, 2, 3]);
  });
}
