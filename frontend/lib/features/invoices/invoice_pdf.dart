import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/formatters.dart';
import '../sales/sale_models.dart';

/// Construit le PDF d'une facture (format A4).
///
/// Les polices standard du PDF couvrent le français (accents, espaces insécables) ;
/// les montants n'utilisent donc pas l'espace fine U+202F.
Future<Uint8List> buildInvoicePdf(Invoice invoice, {Uint8List? logo}) async {
  final document = pw.Document(title: 'Facture ${invoice.number}', author: Formats.title(invoice.companyName));
  final primary = PdfColor.fromHex('#1E3A8A');
  final muted = PdfColor.fromHex('#4B5563');
  final small = pw.TextStyle(fontSize: 9, color: muted);
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);

  pw.Widget row(String label, String value, {bool strong = false, PdfColor? color}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      children: [
        pw.Expanded(child: pw.Text(label, style: strong ? bold : null)),
        pw.Text(
          value,
          style: pw.TextStyle(fontWeight: strong ? pw.FontWeight.bold : null, color: color),
        ),
      ],
    ),
  );

  final companyLines = [
    if (invoice.companyAddress != null) Formats.title(invoice.companyAddress),
    if (invoice.companyCity != null) Formats.title(invoice.companyCity),
    if (invoice.companyPhone != null) 'Tél. ${invoice.companyPhone}',
    if (invoice.companyEmail != null) invoice.companyEmail!,
  ];

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        // En-tête : société et facture.
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logo != null)
              pw.Container(
                width: 64,
                height: 64,
                margin: const pw.EdgeInsets.only(right: 12),
                child: pw.Image(pw.MemoryImage(logo), fit: pw.BoxFit.contain),
              ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    Formats.title(invoice.companyName),
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: primary),
                  ),
                  for (final line in companyLines) pw.Text(line, style: small),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'FACTURE',
                  style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: primary),
                ),
                pw.Text(invoice.number, style: bold),
                pw.Text(Formats.dateTime(invoice.date), style: small),
                if (invoice.status == 'CANCELLED')
                  pw.Text(
                    'ANNULÉE',
                    style: pw.TextStyle(color: PdfColors.red, fontWeight: pw.FontWeight.bold),
                  ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Magasin', style: small),
                  pw.Text(
                    invoice.storeName.toLowerCase() == 'stock local' ? 'Stock Local' : Formats.title(invoice.storeName),
                    style: bold,
                  ),
                  if (invoice.storeAddress != null) pw.Text(Formats.title(invoice.storeAddress)),
                  if (invoice.storePhone != null) pw.Text('Tél. ${invoice.storePhone}'),
                  pw.SizedBox(height: 6),
                  pw.Text('Vendeur : ${invoice.seller.fullName}', style: small),
                ],
              ),
            ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Client', style: small),
                  pw.Text(invoice.customer.fullName, style: bold),
                  if (invoice.customer.phone != null) pw.Text('Tél. ${invoice.customer.phone}'),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headers: ['Réf.', 'Désignation', 'Qté', 'Prix unitaire', 'Total'],
          data: [
            for (final line in invoice.lines)
              [
                line.reference.toUpperCase(),
                Formats.capitalize(line.name),
                Formats.quantity(line.quantity),
                Formats.money(line.unitPrice),
                Formats.money(line.total),
              ],
          ],
          headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
          headerDecoration: pw.BoxDecoration(color: primary),
          cellStyle: const pw.TextStyle(fontSize: 10),
          cellAlignments: {2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight},
          columnWidths: {
            0: const pw.FlexColumnWidth(1.4),
            1: const pw.FlexColumnWidth(3.2),
            2: const pw.FlexColumnWidth(0.8),
            3: const pw.FlexColumnWidth(1.6),
            4: const pw.FlexColumnWidth(1.6),
          },
        ),
        pw.SizedBox(height: 12),
        pw.Row(
          children: [
            pw.Spacer(),
            pw.SizedBox(
              width: 240,
              child: pw.Column(
                children: [
                  row('Sous-total', Formats.money(invoice.subtotal)),
                  if (invoice.discountAmount > 0) row('Remise', '- ${Formats.money(invoice.discountAmount)}'),
                  pw.Divider(),
                  row('Total', Formats.money(invoice.total), strong: true),
                  row('Payé', Formats.money(invoice.amountPaid)),
                  if (invoice.remainingAmount > 0) ...[
                    row('Reste à payer', Formats.money(invoice.remainingAmount), strong: true, color: PdfColors.red),
                    if (invoice.dueDate != null) row('Échéance', Formats.date(invoice.dueDate)),
                  ],
                  row('Statut', invoice.paymentStatus.label),
                ],
              ),
            ),
          ],
        ),
        if (invoice.payments.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          pw.Text('Paiements', style: bold),
          pw.SizedBox(height: 4),
          for (final payment in invoice.payments)
            pw.Text(
              '${Formats.dateTime(payment.createdAt)} — ${payment.method.label} — ${Formats.money(payment.amount)}'
              '${payment.reference == null ? '' : ' (réf. ${payment.reference})'}',
              style: small,
            ),
        ],
        pw.SizedBox(height: 28),
        pw.Center(
          child: pw.Column(
            children: [for (final line in invoice.thankYouMessage) pw.Text(line, style: pw.TextStyle(color: primary))],
          ),
        ),
      ],
    ),
  );
  return document.save();
}
