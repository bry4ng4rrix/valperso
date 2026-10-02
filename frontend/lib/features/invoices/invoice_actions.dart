import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/export/excel_export.dart';
import '../../core/widgets/notifications.dart';
import '../sales/sale_models.dart';
import '../sales/sales_repository.dart';
import 'invoice_pdf.dart';

/// Adresse complète du logo : une adresse web, ou un chemin servi par le serveur de l'API.
String? resolveLogoUrl(String? logoUrl, String apiBaseUrl) {
  if (logoUrl == null || logoUrl.isEmpty) return null;
  if (logoUrl.startsWith('http://') || logoUrl.startsWith('https://')) return logoUrl;
  return '$apiBaseUrl$logoUrl';
}

/// Télécharge le logo pour le PDF. Sans logo (ou s'il est inaccessible), la facture reste valide.
Future<Uint8List?> _loadLogo(ApiClient api, Invoice invoice) async {
  final url = resolveLogoUrl(invoice.logoUrl, api.baseUrl);
  if (url == null) return null;
  try {
    return Uint8List.fromList(await api.getBytes(url));
  } on ApiException {
    return null;
  }
}

String invoiceFileName(Invoice invoice) => 'facture_${invoice.number}.pdf';

Future<Uint8List> _pdfFor(BuildContext context, Invoice invoice) async {
  final api = context.read<ApiClient>();
  final logo = await _loadLogo(api, invoice);
  return buildInvoicePdf(invoice, logo: logo);
}

/// Partage la facture en PDF (WhatsApp, email, impression via le menu de partage d'Android...).
/// Sur ordinateur, le PDF est enregistré dans le dossier Téléchargements.
Future<void> shareInvoice(BuildContext context, int saleId, {Invoice? invoice}) async {
  try {
    final data = invoice ?? await context.read<SalesRepository>().invoice(saleId);
    if (!context.mounted) return;
    final bytes = await _pdfFor(context, data);
    if (defaultTargetPlatform != TargetPlatform.android) {
      final path = await saveExportFile(bytes, invoiceFileName(data));
      if (context.mounted) Notify.success(context, 'Facture enregistrée : $path');
      return;
    }
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}${invoiceFileName(data)}');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        title: 'Facture ${data.number}',
        text: data.thankYouMessage.join(' '),
      ),
    );
  } on ApiException catch (error) {
    if (context.mounted) Notify.error(context, error);
  } on Exception catch (error) {
    if (context.mounted) Notify.error(context, error);
  }
}

/// Enregistre la facture en PDF (dossier Téléchargements, sinon dossier de l'application).
Future<void> saveInvoice(BuildContext context, Invoice invoice) async {
  try {
    final bytes = await _pdfFor(context, invoice);
    final path = await saveExportFile(bytes, invoiceFileName(invoice));
    if (context.mounted) Notify.success(context, 'Facture enregistrée : $path');
  } on Exception catch (error) {
    if (context.mounted) Notify.error(context, error);
  }
}
