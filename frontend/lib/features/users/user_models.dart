import '../../core/utils/formatters.dart';
import '../../core/utils/json.dart';
import '../../shared/models/refs.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.isActive,
    this.email,
    this.phone,
    this.store,
    this.createdAt,
  });

  factory AppUser.fromJson(Json json) => AppUser(
    id: toInt(json['id']),
    username: '${json['username']}',
    firstName: '${json['first_name'] ?? ''}',
    lastName: '${json['last_name'] ?? ''}',
    email: toStringOrNull(json['email']),
    phone: toStringOrNull(json['phone']),
    role: RoleRef.fromJson(Json.from(json['role'] as Map)),
    store: toObject(json['store'], StoreRef.fromJson),
    isActive: json['is_active'] != false,
    createdAt: toDate(json['created_at']),
  );

  final int id;
  final String username;
  final String firstName;
  final String lastName;
  final String? email;
  final String? phone;
  final RoleRef role;
  final StoreRef? store;
  final bool isActive;
  final DateTime? createdAt;

  String get fullName => '${Formats.capitalize(firstName)} ${Formats.capitalize(lastName)}'.trim();

  String get storeLabel => store?.label ?? (role.isAdmin ? 'Tous les magasins' : 'Aucun magasin');
}
