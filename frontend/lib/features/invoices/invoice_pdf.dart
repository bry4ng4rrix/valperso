import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/formatters.dart';
import '../sales/sale_models.dart';
import 'receipt.dart';

/// Rouleau de 80 mm des imprimantes de caisse ; la hauteur suit la longueur du ticket.
const receiptPageFormat = PdfPageFormat(
  80 * PdfPageFormat.mm,
  double.infinity,
  marginTop: 6 * PdfPageFormat.mm,
  marginBottom: 10 * PdfPageFormat.mm,
  marginLeft: 4 * PdfPageFormat.mm,
  marginRight: 4 * PdfPageFormat.mm,
);

/// Construit la facture au format ticket de caisse, comme en supermarché.
///
/// Une seule page étroite, imprimée d'un bloc sur une imprimante thermique.
/// La police Courier (standard du PDF) couvre le français (accents, espaces insécables) ;
/// les montants n'utilisent donc pas l'espace fine U+202F.
Future<Uint8List> buildInvoicePdf(Invoice invoice, {Uint8List? logo}) async {
  final document = pw.Document(title: 'Facture ${invoice.number}', author: Formats.title(invoice.companyName));
  final base = pw.ThemeData.withFont(base: pw.Font.courier(), bold: pw.Font.courierBold());
  final theme = base.copyWith(defaultTextStyle: base.defaultTextStyle.copyWith(fontSize: 8, color: PdfColors.black));
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);

  pw.Widget centered(String text, {pw.TextStyle? style}) => pw.Text(text, style: style, textAlign: pw.TextAlign.center);

  pw.Widget row(String label, String value, {pw.TextStyle? style}) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(child: pw.Text(label, style: style)),
      pw.SizedBox(width: 6),
      pw.Text(value, style: style),
    ],
  );

  pw.Widget dashes() =>
      pw.Divider(height: 12, thickness: 0.5, color: PdfColors.black, borderStyle: pw.BorderStyle.dashed);

  pw.Widget doubleRule() => pw.Container(
    height: 2.5,
    margin: const pw.EdgeInsets.symmetric(vertical: 3),
    decoration: const pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(width: 0.5), bottom: pw.BorderSide(width: 0.5)),
    ),
  );

  final barcode = pw.Barcode.code128();

  document.addPage(
    pw.Page(
      pageFormat: receiptPageFormat,
      theme: theme,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // En-tête : logo, société et coordonnées, centrés.
          if (logo != null)
            pw.Center(
              child: pw.Container(
                width: 48,
                height: 48,
                margin: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Image(pw.MemoryImage(logo), fit: pw.BoxFit.contain),
              ),
            ),
          centered(
            invoice.companyName.toUpperCase(),
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          for (final line in invoice.companyLines) centered(line),
          dashes(),
          for (final (label, value) in invoice.infoRows)
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(receiptLabel(label, invoice.infoRows)),
                pw.Expanded(
                  child: pw.Padding(padding: const pw.EdgeInsets.only(left: 5), child: pw.Text(value)),
                ),
              ],
            ),
          if (invoice.status == 'CANCELLED') ...[
            pw.SizedBox(height: 6),
            centered('*** VENTE ANNULÉE ***', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ],
          dashes(),
          // Articles : nom, puis référence, quantité x prix et total de la ligne.
          for (final line in invoice.lines) ...[
            pw.Text(line.name.toUpperCase()),
            if (line.description != null) pw.Text('  ${Formats.capitalize(line.description)}'),
            row('  ${line.receiptDetail}', Formats.amount(line.total)),
            pw.SizedBox(height: 2),
          ],
          dashes(),
          row('NB ARTICLES', Formats.quantity(invoice.articleCount)),
          if (invoice.discountAmount > 0) ...[
            row('SOUS-TOTAL', Formats.amount(invoice.subtotal)),
            row('REMISE', '-${Formats.amount(invoice.discountAmount)}'),
          ],
          doubleRule(),
          row('TOTAL', Formats.money(invoice.total), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          doubleRule(),
          row('PAYÉ', Formats.money(invoice.amountPaid)),
          if (invoice.remainingAmount > 0) ...[
            row('RESTE À PAYER', Formats.money(invoice.remainingAmount), style: bold),
            if (invoice.installments.isEmpty && invoice.dueDate != null) row('ÉCHÉANCE', Formats.date(invoice.dueDate)),
          ],
          row('STATUT', invoice.paymentStatus.label.toUpperCase()),
          if (invoice.installments.isNotEmpty) ...[
            dashes(),
            pw.Text('ÉCHÉANCIER', style: bold),
            for (final (date, amount) in invoice.installmentRows) row(date, amount),
          ],
          if (invoice.payments.isNotEmpty) ...[
            dashes(),
            pw.Text('PAIEMENTS', style: bold),
            for (final (date, amount) in invoice.paymentRows) row(date, amount),
          ],
          dashes(),
          for (final line in invoice.thankYouMessage) centered(line),
          if (barcode.isValid(invoice.number)) ...[
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.BarcodeWidget(barcode: barcode, data: invoice.number, width: 170, height: 32, drawText: false),
            ),
            pw.SizedBox(height: 2),
            centered(invoice.number),
          ],
        ],
      ),
    ),
  );
  return document.save();
}
