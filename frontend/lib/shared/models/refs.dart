import '../../core/utils/formatters.dart';
import '../../core/utils/json.dart';

/// Références courtes renvoyées par l'API à l'intérieur d'autres objets.

class StoreRef {
  const StoreRef({required this.id, required this.name, this.isCentral = false});

  factory StoreRef.fromJson(Json json) =>
      StoreRef(id: toInt(json['id']), name: '${json['name']}', isCentral: json['is_central'] == true);

  final int id;
  final String name;
  final bool isCentral;

  String get label => isCentral ? 'Stock Local' : Formats.capitalize(name);
}

class CategoryRef {
  const CategoryRef({required this.id, required this.name});

  factory CategoryRef.fromJson(Json json) => CategoryRef(id: toInt(json['id']), name: '${json['name']}');

  final int id;
  final String name;
}

class RoleRef {
  const RoleRef({required this.id, required this.name});

  factory RoleRef.fromJson(Json json) => RoleRef(id: toInt(json['id']), name: '${json['name']}');

  final int id;
  final String name; // ADMIN ou VENDEUR

  bool get isAdmin => name == 'ADMIN';
}

class UserRef {
  const UserRef({
    required this.id,
    required this.username,
    required this.firstName,
    required this.lastName,
    this.role,
  });

  factory UserRef.fromJson(Json json) => UserRef(
        id: toInt(json['id']),
        username: '${json['username']}',
        firstName: '${json['first_name'] ?? ''}',
        lastName: '${json['last_name'] ?? ''}',
        role: toObject(json['role'], RoleRef.fromJson),
      );

  final int id;
  final String username;
  final String firstName;
  final String lastName;
  final RoleRef? role;

  String get fullName => '${Formats.capitalize(firstName)} ${Formats.capitalize(lastName)}'.trim();
}

class ProductRef {
  const ProductRef({required this.id, required this.reference, required this.name});

  factory ProductRef.fromJson(Json json) =>
      ProductRef(id: toInt(json['id']), reference: '${json['reference']}', name: '${json['name']}');

  final int id;
  final String reference;
  final String name;
}

class CustomerRef {
  const CustomerRef({required this.id, required this.firstName, required this.lastName, this.phone});

  factory CustomerRef.fromJson(Json json) => CustomerRef(
        id: toInt(json['id']),
        firstName: '${json['first_name'] ?? ''}',
        lastName: '${json['last_name'] ?? ''}',
        phone: toStringOrNull(json['phone']),
      );

  final int id;
  final String firstName;
  final String lastName;
  final String? phone;

  String get fullName => '${Formats.capitalize(firstName)} ${Formats.capitalize(lastName)}'.trim();
}
