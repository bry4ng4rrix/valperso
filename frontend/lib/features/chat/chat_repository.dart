import '../../core/api/api_client.dart';
import '../../core/api/paged.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/json.dart';
import '../../shared/models/refs.dart';

class Conversation {
  const Conversation({
    required this.id,
    required this.type,
    required this.createdBy,
    required this.members,
    required this.unreadCount,
    this.name,
    this.updatedAt,
  });

  factory Conversation.fromJson(Json json) => Conversation(
    id: toInt(json['id']),
    type: '${json['type']}',
    name: toStringOrNull(json['name']),
    createdBy: toInt(json['created_by']),
    members: [
      for (final member in json['members'] as List? ?? const [])
        if (member is Map && member['user'] is Map) UserRef.fromJson(Json.from(member['user'] as Map)),
    ],
    unreadCount: toInt(json['unread_count']),
    updatedAt: toDate(json['updated_at']),
  );

  final int id;
  final String type; // PRIVATE ou GROUP
  final String? name;
  final int createdBy;
  final List<UserRef> members;
  final int unreadCount;
  final DateTime? updatedAt;

  bool get isGroup => type == 'GROUP';

  /// Nom affiché : nom du groupe, sinon l'autre participant.
  String titleFor(int currentUserId) {
    if (isGroup) return Formats.capitalize(name ?? 'Groupe');
    final others = members.where((member) => member.id != currentUserId);
    return others.isEmpty ? 'Conversation' : others.first.fullName;
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.isDeleted,
    required this.createdAt,
    this.content,
  });

  factory ChatMessage.fromJson(Json json) => ChatMessage(
    id: toInt(json['id']),
    conversationId: toInt(json['conversation_id']),
    senderId: toInt(json['sender_id']),
    content: toStringOrNull(json['content']),
    isDeleted: json['is_deleted'] == true,
    createdAt: toDate(json['created_at']) ?? DateTime.now(),
  );

  final int id;
  final int conversationId;
  final int senderId;
  final String? content;
  final bool isDeleted;
  final DateTime createdAt;
}

class ChatRepository {
  ChatRepository(this._api);

  final ApiClient _api;

  Future<List<Conversation>> conversations() async =>
      toList(await _api.get('/chat/conversations'), Conversation.fromJson);

  Future<Conversation> get(int id) async => Conversation.fromJson(await _api.get('/chat/conversations/$id') as Json);

  Future<Conversation> start({required List<int> memberIds, String? groupName}) async => Conversation.fromJson(
    await _api.post(
          '/chat/conversations',
          data: {'type': groupName == null ? 'PRIVATE' : 'GROUP', 'name': groupName, 'member_ids': memberIds},
        )
        as Json,
  );

  /// Messages du plus récent au plus ancien.
  Future<Paged<ChatMessage>> messages(int conversationId, {int page = 1, int pageSize = 50}) async => Paged.fromJson(
    await _api.get('/chat/conversations/$conversationId/messages', query: {'page': page, 'page_size': pageSize})
        as Json,
    ChatMessage.fromJson,
  );

  Future<ChatMessage> send(int conversationId, String content) async => ChatMessage.fromJson(
    await _api.post('/chat/conversations/$conversationId/messages', data: {'content': content}) as Json,
  );

  Future<void> markAsRead(int conversationId) => _api.post('/chat/conversations/$conversationId/read');

  Future<void> deleteMessage(int messageId) => _api.delete('/chat/messages/$messageId');
}
