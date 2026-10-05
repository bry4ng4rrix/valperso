import '../../core/utils/formatters.dart';
import '../sales/sale_models.dart';

/// Contenu du ticket de caisse, commun au PDF et à l'aperçu à l'écran.
extension InvoiceReceipt on Invoice {
  /// Coordonnées de la société, centrées sous son nom.
  List<String> get companyLines => [
    if (companyAddress != null) Formats.title(companyAddress),
    if (companyCity != null) Formats.title(companyCity),
    if (companyPhone != null) 'Tél. $companyPhone',
    ?companyEmail,
  ];

  /// Informations de la vente (libellé, valeur). Le téléphone va sur une seconde ligne de la valeur.
  List<(String, String)> get infoRows => [
    ('Facture', number),
    ('Date', Formats.dateTime(date)),
    (
      'Magasin',
      [
        [
          storeName.toLowerCase() == 'stock local' ? 'Stock Local' : Formats.title(storeName),
          if (storeAddress != null) Formats.title(storeAddress),
        ].join(', '),
        if (storePhone != null) 'Tél. $storePhone',
      ].join('\n'),
    ),
    ('Vendeur', seller.fullName),
    ('Client', [customer.fullName, if (customer.phone != null) 'Tél. ${customer.phone}'].join('\n')),
  ];

  /// Nombre d'unités vendues (somme des quantités), comme « NB ARTICLES » en caisse.
  int get articleCount => lines.fold(0, (count, line) => count + line.quantity);

  List<(String, String)> get installmentRows => [
    for (final installment in installments)
      (Formats.date(installment.dueDate), '${Formats.money(installment.amount)}${installment.note}'),
  ];

  List<(String, String)> get paymentRows => [
    for (final payment in payments)
      (
        '${Formats.dateTime(payment.createdAt)}${payment.reference == null ? '' : ' réf. ${payment.reference}'}',
        Formats.money(payment.amount),
      ),
  ];
}

extension ReceiptItem on SaleItem {
  /// Ligne sous le nom de l'article : référence, quantité x prix unitaire.
  String get receiptDetail =>
      '${reference.toUpperCase()}  ${Formats.quantity(quantity)} x ${Formats.amount(unitPrice)}';
}

/// Libellés alignés sur les deux-points (police à chasse fixe) : « Facture : », « Date    : ».
/// Pas d'espace à la fin : le PDF supprime les espaces en fin de texte.
String receiptLabel(String label, Iterable<(String, String)> rows) {
  final width = rows.fold(0, (max, row) => row.$1.length > max ? row.$1.length : max);
  return '${label.padRight(width)} :';
}
