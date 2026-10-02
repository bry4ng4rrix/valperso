import '../../core/api/api_client.dart';
import '../../core/api/paged.dart';
import '../../core/utils/json.dart';

class AuditLog {
  const AuditLog({
    required this.id,
    required this.action,
    required this.entityType,
    required this.createdAt,
    this.userId,
    this.entityId,
    this.oldData,
    this.newData,
    this.ipAddress,
  });

  factory AuditLog.fromJson(Json json) => AuditLog(
    id: toInt(json['id']),
    userId: json['user_id'] == null ? null : toInt(json['user_id']),
    action: '${json['action']}',
    entityType: '${json['entity_type']}',
    entityId: json['entity_id'] == null ? null : toInt(json['entity_id']),
    oldData: json['old_data'] is Map ? Json.from(json['old_data'] as Map) : null,
    newData: json['new_data'] is Map ? Json.from(json['new_data'] as Map) : null,
    ipAddress: toStringOrNull(json['ip_address']),
    createdAt: toDate(json['created_at']) ?? DateTime.now(),
  );

  final int id;
  final int? userId;
  final String action;
  final String entityType;
  final int? entityId;
  final Json? oldData;
  final Json? newData;
  final String? ipAddress;
  final DateTime createdAt;
}

class AuditRepository {
  AuditRepository(this._api);

  final ApiClient _api;

  Future<Paged<AuditLog>> list(PageQuery query) async =>
      Paged.fromJson(await _api.get('/audit', query: query.toQuery()) as Json, AuditLog.fromJson);
}
