import '../../core/api/api_client.dart';
import '../../core/utils/json.dart';

class PermissionItem {
  const PermissionItem({required this.id, required this.name, this.description});

  factory PermissionItem.fromJson(Json json) =>
      PermissionItem(id: toInt(json['id']), name: '${json['name']}', description: toStringOrNull(json['description']));

  final int id;

  /// Code technique, ex. `sale.create`.
  final String name;
  final String? description;

  /// Module de la permission (`sale`, `stock`...), pour les regrouper à l'écran.
  String get module => name.split('.').first;
}

class Role {
  const Role({required this.id, required this.name, required this.permissions, this.description});

  factory Role.fromJson(Json json) => Role(
    id: toInt(json['id']),
    name: '${json['name']}',
    description: toStringOrNull(json['description']),
    permissions: toList(json['permissions'], PermissionItem.fromJson),
  );

  final int id;
  final String name;
  final String? description;
  final List<PermissionItem> permissions;

  bool get isAdmin => name == 'ADMIN';
}

class RolesRepository {
  RolesRepository(this._api);

  final ApiClient _api;

  Future<List<Role>> list() async => toList(await _api.get('/roles'), Role.fromJson);

  Future<List<PermissionItem>> permissions() async => toList(await _api.get('/permissions'), PermissionItem.fromJson);

  /// Remplace la liste complète des permissions du rôle.
  Future<Role> setPermissions(int roleId, Set<int> permissionIds) async => Role.fromJson(
    await _api.put(
          '/roles/$roleId/permissions',
          data: {
            'permission_ids': [...permissionIds]..sort(),
          },
        )
        as Json,
  );
}
