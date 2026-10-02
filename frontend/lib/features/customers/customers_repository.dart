import '../../core/api/api_client.dart';
import '../../core/api/paged.dart';
import '../../core/utils/json.dart';
import '../../shared/models/refs.dart';
import '../sales/sale_models.dart';
import 'customer_models.dart';

class CustomersRepository {
  CustomersRepository(this._api);

  final ApiClient _api;

  /// Clients avec leurs totaux (achats, payé, reste à payer).
  Future<Paged<CustomerContact>> contacts(PageQuery query) async =>
      Paged.fromJson(await _api.get('/customers/contacts', query: query.toQuery()) as Json, CustomerContact.fromJson);

  /// Recherche rapide (ex. choix du client pendant une vente).
  Future<List<CustomerRef>> search(String term) async {
    final page = Paged.fromJson(
      await _api.get('/customers', query: {'search': term, 'page_size': 10}) as Json,
      CustomerRef.fromJson,
    );
    return page.items;
  }

  Future<CustomerRef> get(int id) async => CustomerRef.fromJson(await _api.get('/customers/$id') as Json);

  Future<CustomerRef> create({required String firstName, required String lastName, String? phone}) async =>
      CustomerRef.fromJson(
        await _api.post('/customers', data: {'first_name': firstName, 'last_name': lastName, 'phone': phone}) as Json,
      );

  Future<CustomerDebts> debts(int id) async => CustomerDebts.fromJson(await _api.get('/customers/$id/debts') as Json);

  Future<Paged<Sale>> sales(int id, PageQuery query) async =>
      Paged.fromJson(await _api.get('/customers/$id/sales', query: query.toQuery()) as Json, Sale.fromJson);
}
