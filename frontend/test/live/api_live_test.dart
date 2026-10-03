// Test d'intégration contre une vraie API FastAPI (base de test dédiée, jamais la base de travail).
//
// Lancé seulement si LIVE_API_URL est défini, par exemple :
//   LIVE_API_URL=http://127.0.0.1:8002 LIVE_PASSWORD=... flutter test test/live
// L'API doit contenir les données de démonstration (python -m app.seed_demo).
//
// Pas de testWidgets ici : sans « binding » de test Flutter, les requêtes HTTP sont réelles.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:valmag/core/api/api_client.dart';
import 'package:valmag/core/api/api_exception.dart';
import 'package:valmag/core/api/paged.dart';
import 'package:valmag/core/api/paged_controller.dart';
import 'package:valmag/core/auth/auth_repository.dart';
import 'package:valmag/core/auth/permissions.dart';
import 'package:valmag/core/export/excel_export.dart';
import 'package:valmag/core/storage/key_value_store.dart';
import 'package:valmag/core/utils/media.dart';
import 'package:valmag/core/utils/periods.dart';
import 'package:valmag/features/audit/audit_repository.dart';
import 'package:valmag/features/chat/chat_repository.dart';
import 'package:valmag/features/company/company_repository.dart';
import 'package:valmag/features/customers/customers_repository.dart';
import 'package:valmag/features/dashboard/dashboard_repository.dart';
import 'package:valmag/features/invoices/invoice_pdf.dart';
import 'package:valmag/features/payments/payments_repository.dart';
import 'package:valmag/features/products/products_repository.dart';
import 'package:valmag/features/roles/roles_repository.dart';
import 'package:valmag/features/sales/cart_controller.dart';
import 'package:valmag/features/sales/sale_models.dart';
import 'package:valmag/features/sales/sales_repository.dart';
import 'package:valmag/features/sales/sale_widgets.dart';
import 'package:valmag/features/stock/stock_repository.dart';
import 'package:valmag/features/stores/stores_repository.dart';
import 'package:valmag/features/transfers/transfers_repository.dart';
import 'package:valmag/features/users/users_repository.dart';

final _url = Platform.environment['LIVE_API_URL'];
final _password = Platform.environment['LIVE_PASSWORD'] ?? '';

Future<(ApiClient, MemoryKeyValueStore)> _login(String identifier) async {
  final storage = MemoryKeyValueStore();
  final api = ApiClient(baseUrl: _url!, tokens: TokenStore(storage));
  await AuthRepository(api).login(identifier, _password);
  return (api, storage);
}

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'fr';
    await initializeDateFormatting('fr');
  });

  group('API réelle', skip: _url == null ? 'LIVE_API_URL non défini' : null, () {
    test('connexion : mauvais mot de passe refusé avec un message clair', () async {
      final api = ApiClient(baseUrl: _url!, tokens: TokenStore(MemoryKeyValueStore()));
      await expectLater(
        AuthRepository(api).login('vendeur1', 'mauvais-mot-de-passe'),
        throwsA(isA<ApiException>().having((error) => error.isUnauthorized, 'isUnauthorized', isTrue)),
      );
    });

    test('vendeur : profil, magasin, stock de son magasin, pas d\'accès au tableau de bord', () async {
      final (api, storage) = await _login('vendeur1@local.mg');
      final me = await AuthRepository(api).me();
      expect(me.isAdmin, isFalse);
      expect(me.store?.label, 'H109');
      expect(me.can(Perm.saleCreate), isTrue);
      expect(me.can(Perm.dashboardView), isFalse);
      expect(storage.values.values, isNot(contains(_password)), reason: 'le mot de passe n\'est jamais stocké');

      final lines = await StockRepository(api).lines(const PageQuery(pageSize: 100));
      expect(lines.items.every((line) => line.store.id == me.store!.id), isTrue);

      await expectLater(
        DashboardRepository(api).summary(),
        throwsA(isA<ApiException>().having((error) => error.isForbidden, 'isForbidden', isTrue)),
      );
    });

    test('administrateur : parcours complet (transfert, vente avec avance, facture, paiement, export)', () async {
      final (api, _) = await _login('valenciaraza@local.mg');
      final me = await AuthRepository(api).me();
      expect(me.isAdmin, isTrue);

      // Magasins : Stock Local en premier, puis H109 et C209.
      final stores = await StoresRepository(api).active();
      expect(stores.first.isCentral, isTrue);
      expect(stores.first.label, 'Stock Local');
      final h109 = stores.firstWhere((store) => store.label == 'H109');

      // Produits et stock du Stock Local (données de démonstration).
      final products = await ProductsRepository(api).list(const PageQuery(pageSize: 100));
      expect(products.total, greaterThan(0));
      final stock = StockRepository(api);
      final localLines = await stock.lines(PageQuery(pageSize: 100, filters: {'store_id': stores.first.id}));
      final line = localLines.items.firstWhere((item) => item.quantity >= 5);

      // Transfert de 2 unités vers H109 : stocks renvoyés pour les deux magasins.
      final transfer = await TransfersRepository(
        api,
      ).create(sourceStoreId: stores.first.id, destinationStoreId: h109.id, lines: {line.product.id: 2});
      expect(transfer.reference, startsWith('TRF-'));
      expect(transfer.stockLevels.single.sourceQuantity, line.quantity - 2);

      // Vente au Stock Local : 1 article, dette avec avance, nouveau client avec téléphone.
      final cart = CartController()..setStore(stores.first.ref);
      cart.add(line.product, available: line.quantity - 2);
      cart.setCustomer(const CartCustomer.create(firstName: 'Client', lastName: 'Test', phone: '034 11 222 33'));
      final advance = (line.product.sellingPrice / 2).floorToDouble();
      cart.setPayment(inFull: false, advance: advance);
      cart.setInstallmentDate(cart.installments.single.id, DateTime.now().add(const Duration(days: 10)));
      expect(cart.isReady, isTrue, reason: cart.allErrors.join(', '));
      final sales = SalesRepository(api);
      final sale = await sales.create(cart.toNewSale(includeStore: true));
      expect(sale.number, startsWith('FAC-'));
      expect(sale.total, cart.total, reason: 'l\'aperçu du panier correspond au calcul du serveur');
      expect(sale.amountPaid, advance);
      expect(sale.paymentStatus, PaymentStatus.partial);
      expect(sale.paymentDueDate, isNotNull);

      // Facture (avec le message de remerciement de la société) et PDF.
      final invoice = await sales.invoice(sale.id);
      expect(invoice.thankYouMessage, hasLength(2));
      final pdf = await buildInvoicePdf(invoice);
      expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');

      // Le client apparaît dans les contacts avec dette.
      final debts = await CustomersRepository(
        api,
      ).contacts(const PageQuery(filters: {'has_debt': true, 'search': 'test'}));
      expect(debts.items.any((contact) => contact.remainingAmount > 0), isTrue);

      // Solde de la dette.
      await PaymentsRepository(api).create(saleId: sale.id, amount: sale.remainingAmount);
      final paid = await sales.get(sale.id);
      expect(paid.paymentStatus, PaymentStatus.paid);
      expect(paid.payments, hasLength(2));

      // Historique du jour + export Excel de toutes les pages.
      final history = PagedController<Sale>(sales.history, filters: rangeFor(Period.today).toQuery());
      final rows = await history.fetchAll();
      expect(rows.any((item) => item.id == sale.id), isTrue);
      final workbook = buildWorkbook(sheetName: 'Ventes', columns: saleExportColumns, rows: rows);
      expect(workbook, isNotEmpty);

      // Tableau de bord, valeur du stock, mouvements.
      final summary = await DashboardRepository(api).summary(range: rangeFor(Period.today).toQuery());
      expect(summary.salesCount, greaterThan(0));
      final value = await stock.value();
      expect(value.stores, isNotEmpty);
      final movements = await stock.movements(PageQuery(filters: {'product_id': line.product.id}));
      expect(movements.items.map((movement) => movement.type.code), containsAll(['TRANSFER_OUT', 'SALE']));
    });

    test('nouveautés : vente sans client, échéancier, descriptions, transferts, tableau de bord, photos', () async {
      final (api, _) = await _login('valenciaraza@local.mg');
      final stores = await StoresRepository(api).active();
      final local = stores.first;
      final h109 = stores.firstWhere((store) => store.label == 'H109');
      final stock = StockRepository(api);
      final localLines = await stock.lines(PageQuery(pageSize: 100, filters: {'store_id': local.id}));
      final line = localLines.items.firstWhere((item) => item.quantity >= 6);
      final sales = SalesRepository(api);

      // Vente payée sans client : enregistrée au nom de « Client comptant ».
      final cashCart = CartController()..setStore(local.ref);
      cashCart.add(line.product, available: line.quantity);
      expect(cashCart.isReady, isTrue, reason: cashCart.allErrors.join(', '));
      final cashSale = await sales.create(cashCart.toNewSale(includeStore: true));
      expect(cashSale.customer.fullName, 'Client Comptant');
      expect(cashSale.paymentStatus, PaymentStatus.paid);

      // Dette : description de l'article, avance, deux dates de remboursement.
      final cart = CartController()..setStore(local.ref);
      cart.add(line.product, available: line.quantity - 1);
      cart.setQuantity(line.product.id, 2);
      cart.setDescription(line.product.id, 'Taille M, noir');
      cart.setCustomer(const CartCustomer.create(firstName: 'Echeance', lastName: 'Test', phone: '034 99 888 77'));
      cart.setPayment(inFull: false, advance: (cart.total / 4).floorToDouble());
      cart.addInstallment();
      final [first, second] = cart.installments;
      final today = DateTime.now();
      cart.setInstallmentDate(first.id, today.add(const Duration(days: 10)));
      cart.setInstallmentDate(second.id, today.add(const Duration(days: 40)));
      expect(cart.isReady, isTrue, reason: cart.allErrors.join(', '));
      final sale = await sales.create(cart.toNewSale(includeStore: true));
      expect(sale.items.single.description, 'taille m, noir');
      expect(sale.installments, hasLength(2));
      expect(sale.installments.map((i) => i.status), everyElement(PaymentStatus.unpaid));
      expect(sale.paymentDueDate, sale.installments.first.dueDate, reason: 'prochaine échéance');

      // Paiement de la première date : elle est soldée, la prochaine échéance passe à la seconde.
      await PaymentsRepository(api).create(saleId: sale.id, amount: sale.installments.first.amount);
      final after = await sales.get(sale.id);
      expect(after.installments.first.status, PaymentStatus.paid);
      expect(after.paymentDueDate, after.installments.last.dueDate);
      final invoice = await sales.invoice(sale.id);
      expect(invoice.installments, hasLength(2));
      expect(invoice.lines.single.description, 'taille m, noir');
      expect(String.fromCharCodes((await buildInvoicePdf(invoice)).sublist(0, 5)), '%PDF-');

      // Transfert : les deux mouvements s'affichent « Transfert » avec l'origine et la destination.
      final transfer = await TransfersRepository(
        api,
      ).create(sourceStoreId: local.id, destinationStoreId: h109.id, lines: {line.product.id: 1});
      final movements = await stock.movements(PageQuery(filters: {'reference': transfer.reference}));
      expect(movements.items, hasLength(2));
      for (final movement in movements.items) {
        expect(movement.typeLabel, 'Transfert');
        expect((movement.sourceStore?.id, movement.destinationStore?.id), (local.id, h109.id));
      }

      // Tableau de bord : marge du stock, marge des ventes, moins vendus, performance des magasins.
      final summary = await DashboardRepository(api).summary(range: rangeFor(Period.today).toQuery());
      expect(summary.estimatedProfit, greaterThan(0));
      expect(summary.leastSoldProducts, isNotEmpty);
      expect(summary.storesPerformance.map((performance) => performance.store.id), containsAll([local.id, h109.id]));
      final localPerformance = summary.storesPerformance.firstWhere((p) => p.store.id == local.id);
      expect(localPerformance.salesCount, greaterThanOrEqualTo(2));

      // Photo : envoyée, servie sous /media, puis supprimée.
      final products = ProductsRepository(api);
      final png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...List.filled(32, 0)];
      final withPhoto = await products.addImage(line.product.id, png, 'photo.png');
      final photo = withPhoto.images.last;
      final client = HttpClient();
      final served = await (await client.getUrl(Uri.parse(resolveMediaUrl(photo.url, api.baseUrl)!))).close();
      client.close();
      expect(served.statusCode, 200);
      final withoutPhoto = await products.deleteImage(line.product.id, photo.id);
      expect(withoutPhoto.images.map((image) => image.id), isNot(contains(photo.id)));
    });

    test('administrateur : écrans de gestion (utilisateurs, rôles, société, audit, chat)', () async {
      final (api, _) = await _login('valenciaraza');
      final users = await UsersRepository(api).list(const PageQuery(pageSize: 100));
      expect(users.items.map((user) => user.username.toLowerCase()), containsAll(['vendeur1', 'vendeur2', 'vendeur3']));
      final roles = await RolesRepository(api).list();
      expect(roles.map((role) => role.name), containsAll(['ADMIN', 'VENDEUR']));
      expect(await RolesRepository(api).permissions(), isNotEmpty);
      final company = await CompanyRepository(api).get();
      expect(company.name, isNotEmpty);
      final audit = await AuditRepository(api).list(const PageQuery());
      expect(audit.total, greaterThan(0));
      await ChatRepository(api).conversations();
    });

    test('jeton d\'accès invalide : renouvelé automatiquement avec le refresh token', () async {
      final (api, storage) = await _login('valenciaraza');
      api.tokens.accessToken = 'jeton-invalide';
      final me = await AuthRepository(api).me();
      expect(me.isAdmin, isTrue);
      expect(api.tokens.accessToken, isNot('jeton-invalide'));
      expect(storage.values[StorageKeys.accessToken], api.tokens.accessToken);
    });
  });
}
