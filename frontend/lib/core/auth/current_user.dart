import '../../shared/models/refs.dart';
import '../utils/formatters.dart';
import '../utils/json.dart';
import 'permissions.dart';

/// Utilisateur connecté, tel que renvoyé par GET /auth/me.
class CurrentUser {
  const CurrentUser({
    required this.id,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.permissions,
    this.email,
    this.phone,
    this.store,
  });

  factory CurrentUser.fromJson(Json json) => CurrentUser(
    id: toInt(json['id']),
    username: '${json['username']}',
    firstName: '${json['first_name'] ?? ''}',
    lastName: '${json['last_name'] ?? ''}',
    email: toStringOrNull(json['email']),
    phone: toStringOrNull(json['phone']),
    role: RoleRef.fromJson(Json.from(json['role'] as Map)),
    store: toObject(json['store'], StoreRef.fromJson),
    permissions: {...(json['permissions'] as List? ?? const []).map((p) => '$p')},
  );

  final int id;
  final String username;
  final String firstName;
  final String lastName;
  final String? email;
  final String? phone;
  final RoleRef role;
  final StoreRef? store;
  final Set<String> permissions;

  bool get isAdmin => role.isAdmin;

  String get fullName => '${Formats.capitalize(firstName)} ${Formats.capitalize(lastName)}'.trim();

  bool can(String permission) => permissions.contains(permission);

  bool canAny(Iterable<String> codes) => codes.any(permissions.contains);

  /// Un transfert peut être créé avec l'une ou l'autre de ces permissions (équivalentes côté API).
  bool get canCreateTransfer => canAny(const [Perm.transferCreate, Perm.stockTransfer]);

  /// Un ADMIN choisit le magasin ; un VENDEUR travaille toujours dans le sien.
  bool get canChooseStore => isAdmin;
}
