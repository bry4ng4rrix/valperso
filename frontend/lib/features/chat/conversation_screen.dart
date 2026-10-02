import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/dimensions.dart';
import '../../core/api/api_exception.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/notifications.dart';
import '../../shared/models/refs.dart';
import '../../shared/widgets/states.dart';
import 'chat_repository.dart';
import 'chat_screen.dart';

/// Messages d'une conversation (les plus récents en bas), envoi et suppression de ses messages.
class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.conversationId});

  final int conversationId;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  late final int _me = context.read<SessionController>().requireUser.id;
  late final bool _canSend = context.read<SessionController>().requireUser.can(Perm.chatSend);
  final _input = TextEditingController();
  Conversation? _conversation;
  List<ChatMessage> _messages = const [];
  Object? _error;
  bool _loading = true;
  bool _sending = false;
  Timer? _timer;

  ChatRepository get _repository => context.read<ChatRepository>();

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refreshMessages());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final conversation = await _repository.get(widget.conversationId);
      if (!mounted) return;
      setState(() => _conversation = conversation);
      await _refreshMessages();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshMessages() async {
    try {
      final page = await _repository.messages(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _messages = page.items;
        _error = null;
      });
      if (page.items.isNotEmpty) await _repository.markAsRead(widget.conversationId);
    } on ApiException catch (error) {
      if (mounted && _messages.isEmpty) setState(() => _error = error);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _repository.send(widget.conversationId, text);
      _input.clear();
      await _refreshMessages();
    } on ApiException catch (error) {
      if (mounted) Notify.error(context, error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _senderName(int senderId) {
    final member = _conversation?.members.where((user) => user.id == senderId).firstOrNull;
    return member?.fullName ?? 'Utilisateur';
  }

  @override
  Widget build(BuildContext context) {
    final conversation = _conversation;
    return Scaffold(
      appBar: AppBar(
        title: Text(conversation?.titleFor(_me) ?? 'Conversation'),
        actions: [
          if (conversation != null && conversation.isGroup)
            IconButton(
              tooltip: 'Participants',
              icon: const Icon(Icons.group_outlined),
              onPressed: () => _showMembers(conversation.members),
            ),
          IconButton(tooltip: 'Actualiser', onPressed: _refreshMessages, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const LoadingState(lines: 5)
          : _error != null && _messages.isEmpty
          ? ErrorState(message: errorMessageOf(_error), onRetry: _load)
          : Column(
              children: [
                Expanded(
                  child: _messages.isEmpty
                      ? const EmptyState(
                          title: 'Aucun message',
                          message: 'Écrivez le premier message.',
                          icon: Icons.forum_outlined,
                        )
                      : ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.all(Gaps.md),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            return _MessageBubble(
                              message: message,
                              mine: message.senderId == _me,
                              senderName: conversation?.isGroup == true ? _senderName(message.senderId) : null,
                              onDelete: message.senderId == _me && !message.isDeleted && _canSend
                                  ? () async {
                                      final deleted = await confirmDeleteMessage(context, message);
                                      if (deleted) await _refreshMessages();
                                    }
                                  : null,
                            );
                          },
                        ),
                ),
                if (_canSend)
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(Gaps.md, Gaps.xs, Gaps.md, Gaps.md),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _input,
                              minLines: 1,
                              maxLines: 4,
                              maxLength: 2000,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                              decoration: const InputDecoration(hintText: 'Votre message', counterText: ''),
                            ),
                          ),
                          const SizedBox(width: Gaps.sm),
                          IconButton.filled(
                            tooltip: 'Envoyer',
                            onPressed: _sending ? null : _send,
                            icon: _sending
                                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.send),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  void _showMembers(List<UserRef> members) {
    showDialog<void>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Participants'),
        children: [
          for (final member in members)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(member.fullName),
              subtitle: Text(member.role?.name ?? ''),
            ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.mine, this.senderName, this.onDelete});

  final ChatMessage message;
  final bool mine;
  final String? senderName;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = mine ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHigh;
    final foreground = mine ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onDelete,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          margin: const EdgeInsets.symmetric(vertical: Gaps.xs),
          padding: const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.sm),
          decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(Radii.md)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (senderName != null && !mine)
                Text(senderName!, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
              Text(
                message.isDeleted ? 'Message supprimé' : message.content ?? '',
                style: TextStyle(color: foreground, fontStyle: message.isDeleted ? FontStyle.italic : null),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    Formats.dateTime(message.createdAt),
                    style: theme.textTheme.labelSmall?.copyWith(color: foreground.withValues(alpha: 0.7)),
                  ),
                  if (onDelete != null) ...[
                    const SizedBox(width: Gaps.xs),
                    InkWell(
                      onTap: onDelete,
                      child: Icon(Icons.delete_outline, size: 14, color: foreground.withValues(alpha: 0.7)),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
