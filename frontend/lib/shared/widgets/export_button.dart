import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme/dimensions.dart';
import '../../core/api/paged_controller.dart';
import '../../core/export/excel_export.dart';
import '../../core/widgets/notifications.dart';

/// Bouton « Exporter » d'une liste, avec deux choix :
/// - les résultats filtrés (exactement les filtres affichés à l'écran) ;
/// - tout (sans filtre).
class ExportButton<T> extends StatelessWidget {
  const ExportButton({
    super.key,
    required this.controller,
    required this.columns,
    required this.fileBaseName,
    required this.sheetName,
  });

  final PagedController<T> controller;
  final List<ExportColumn<T>> columns;
  final String fileBaseName;
  final String sheetName;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<bool>(
      tooltip: 'Exporter en Excel',
      icon: const Icon(Icons.file_download_outlined),
      onSelected: (useFilters) => exportList(context, useFilters: useFilters),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: true,
          child: ListTile(leading: Icon(Icons.filter_alt_outlined), title: Text('Exporter les résultats filtrés')),
        ),
        PopupMenuItem(
          value: false,
          child: ListTile(leading: Icon(Icons.select_all), title: Text('Exporter tout')),
        ),
      ],
    );
  }

  Future<void> exportList(BuildContext context, {required bool useFilters}) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
            SizedBox(width: Gaps.lg),
            Text('Export en cours...'),
          ],
        ),
      ),
    );
    try {
      final rows = await controller.fetchAll(useFilters: useFilters);
      final bytes = buildWorkbook(sheetName: sheetName, columns: columns, rows: rows);
      final path = await saveExportFile(bytes, exportFileName(fileBaseName));
      navigator.pop();
      if (!context.mounted) return;
      Notify.success(context, 'Export terminé : ${rows.length} ligne(s) — $path');
      // Sur mobile, le fichier est proposé au partage (enregistrer, envoyer par message...).
      if (defaultTargetPlatform == TargetPlatform.android) {
        await SharePlus.instance.share(ShareParams(files: [XFile(path)], title: sheetName));
      }
    } catch (error) {
      navigator.pop();
      if (context.mounted) Notify.error(context, error);
    }
  }
}
