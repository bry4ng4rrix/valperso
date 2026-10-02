import '../../core/api/api_client.dart';
import '../../core/utils/json.dart';

/// Informations de la société, affichées sur les factures.
class Company {
  const Company({required this.name, this.logoUrl, this.phone, this.email, this.address, this.city});

  factory Company.fromJson(Json json) => Company(
    name: '${json['name'] ?? ''}',
    logoUrl: toStringOrNull(json['logo_url']),
    phone: toStringOrNull(json['phone']),
    email: toStringOrNull(json['email']),
    address: toStringOrNull(json['address']),
    city: toStringOrNull(json['city']),
  );

  final String name;
  final String? logoUrl;
  final String? phone;
  final String? email;
  final String? address;
  final String? city;

  Json toJson() => {
    'name': name,
    'logo_url': logoUrl,
    'phone': phone,
    'email': email,
    'address': address,
    'city': city,
  };
}

class CompanyRepository {
  CompanyRepository(this._api);

  final ApiClient _api;

  Future<Company> get() async => Company.fromJson(await _api.get('/company') as Json);

  Future<Company> update(Company company) async =>
      Company.fromJson(await _api.put('/company', data: company.toJson()) as Json);
}
