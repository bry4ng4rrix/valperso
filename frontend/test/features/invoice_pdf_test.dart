import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:valmag/features/invoices/invoice_actions.dart';
import 'package:valmag/features/invoices/invoice_pdf.dart';
import 'package:valmag/features/invoices/receipt.dart';
import 'package:valmag/features/sales/sale_models.dart';

import '../support/test_app.dart';

void main() {
  setUpAll(initFrenchDates);

  final invoice = Invoice.fromJson({
    'company': {
      'name': 'allsafe',
      'logo_url': null,
      'address': 'boutique h101',
      'city': 'antananarivo',
      'phone': '034 00 000 00',
      'email': 'contact@allsafe.mg',
    },
    'invoice_number': 'FAC-2026-000125',
    'date': '2026-10-02T09:30:00Z',
    'store': {'name': 'h109', 'address': 'behoririka', 'phone': null},
    'user': {'id': 2, 'username': 'vendeur1', 'first_name': 'jean', 'last_name': 'rakoto'},
    'customer': {'id': 7, 'first_name': 'rasoa', 'last_name': 'be', 'phone': '0341234567'},
    'lines': [
      {
        'id': 1,
        'product_id': 10,
        'product_reference': 'p-10',
        'product_name': 'stylo bleu',
        'quantity': 3,
        'unit_price': 1000,
        'total': 3000,
      },
      {
        'id': 2,
        'product_id': 11,
        'product_reference': 'c-1',
        'product_name': 'cahier à spirale',
        'description': 'grand format',
        'quantity': 1,
        'unit_price': 2500,
        'total': 2500,
      },
    ],
    'subtotal': 5500,
    'discount_type': 'PERCENTAGE',
    'discount_value': 10,
    'discount_amount': 550,
    'total': 4950,
    'payments': [
      {
        'id': 1,
        'sale_id': 125,
        'method': 'CASH',
        'amount': 2000,
        'reference': null,
        'created_at': '2026-10-02T09:30:00Z',
      },
    ],
    'amount_paid': 2000,
    'remaining_amount': 2950,
    'payment_status': 'PARTIAL',
    'payment_due_date': '2026-10-30',
    'installments': [
      {
        'due_date': '2026-10-30',
        'amount': 2950,
        'paid_amount': 0,
        'remaining_amount': 2950,
        'status': 'UNPAID',
        'is_overdue': false,
      },
    ],
    'status': 'COMPLETED',
    'thank_you_message': ['Merci pour votre achat !', 'À bientôt chez allsafe.'],
  });

  test('lecture de la facture renvoyée par l\'API', () {
    expect(invoice.number, 'FAC-2026-000125');
    expect(invoice.companyName, 'allsafe');
    expect(invoice.lines, hasLength(2));
    expect(invoice.discountType, DiscountType.percentage);
    expect(invoice.remainingAmount, 2950);
    expect(invoice.lines.last.description, 'grand format');
    expect(installmentsText(invoice.installments), '30/10/2026 : 2\u00A0950 Ar');
    expect(invoice.paymentStatus, PaymentStatus.partial);
    expect(invoice.thankYouMessage.last, 'À bientôt chez allsafe.');
  });

  test('contenu du ticket : informations alignées, articles, échéancier, paiements', () {
    expect(invoice.infoRows.first, ('Facture', 'FAC-2026-000125'));
    expect(invoice.infoRows, contains(('Magasin', 'H109, Behoririka')));
    expect(invoice.infoRows.last, ('Client', 'Rasoa Be\nTél. 0341234567'));
    expect(receiptLabel('Date', invoice.infoRows), 'Date    :');
    expect(invoice.articleCount, 4);
    expect(invoice.lines.first.receiptDetail, 'P-10  3 x 1\u00A0000');
    expect(invoice.installmentRows.single, ('30/10/2026', '2\u00A0950 Ar'));
    expect(invoice.paymentRows.single.$2, '2\u00A0000 Ar');
  });

  test('le PDF est un ticket de 80 mm (accents, montants, remise, reste à payer)', () async {
    final bytes = await buildInvoicePdf(invoice);
    expect(bytes.length, greaterThan(1000));
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    final mediaBox = RegExp(r'/MediaBox ?\[0 0 ([\d.]+) ([\d.]+)\]').firstMatch(latin1.decode(bytes))!;
    expect(double.parse(mediaBox[1]!), closeTo(226.77, 0.01));
    expect(double.parse(mediaBox[2]!), greaterThan(300));
  });

  test('adresse du logo : web ou chemin du serveur', () {
    expect(resolveLogoUrl(null, 'http://api.local'), isNull);
    expect(resolveLogoUrl('https://cdn.mg/logo.png', 'http://api.local'), 'https://cdn.mg/logo.png');
    expect(resolveLogoUrl('/media/logo.png', 'http://api.local'), 'http://api.local/media/logo.png');
    expect(invoiceFileName(invoice), 'facture_FAC-2026-000125.pdf');
  });
}
