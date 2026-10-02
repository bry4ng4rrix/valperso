import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/dimensions.dart';
import '../../core/api/paged.dart';
import '../../core/auth/current_user.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../shared/utils/api_form.dart';
import '../../shared/widgets/adaptive_page.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/states.dart';
import '../users/user_models.dart';
import '../users/users_repository.dart';
import 'chat_repository.dart';
import '../../core/widgets/app_dialog.dart';

/// Conversations de l'utilisateur, avec le nombre de messages non lus.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final CurrentUser _user = context.read<SessionController>().requireUser;
  late Future<List<Conversation>> _future = context.read<ChatRepository>().conversations();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Rafraîchissement léger tant que l'écran est ouvert (pas de temps réel côté API).
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _reload() {
    if (mounted) {
      setState(() {
        _future = context.read<ChatRepository>().conversations();
      });
    }
  }

  Future<void> _open(Conversation conversation) async {
    await context.push('/chat/${conversation.id}');
    _reload();
  }

  Future<void> _newConversation() async {
    final conversation = await showDialog<Conversation>(
      context: context,
      builder: (_) => const _NewConversationDialog(),
    );
    if (conversation != null && mounted) await _open(conversation);
  }

  @override
  Widget build(BuildContext context) {
    final canStart = _user.can(Perm.chatSend) && _user.can(Perm.userView);
    return AdaptivePage(
      title: 'Messages',
      actions: [IconButton(tooltip: 'Actualiser', onPressed: _reload, icon: const Icon(Icons.refresh))],
      primaryAction: canStart
          ? PrimaryAction(label: 'Nouvelle conversation', icon: Icons.add_comment_outlined, onPressed: _newConversation)
          : null,
      body: FutureBuilder<List<Conversation>>(
        future: _future,
        builder: (context, snapshot) {
          final conversations = snapshot.data;
          if (snapshot.hasError && conversations == null) {
            return ErrorState(message: errorMessageOf(snapshot.error), onRetry: _reload);
          }
          if (conversations == null) return const LoadingState(lines: 5);
          if (conversations.isEmpty) {
            return EmptyState(
              title: 'Aucune conversation',
              message: canStart ? 'Démarrez une conversation avec un collègue.' : null,
              icon: Icons.chat_bubble_outline,
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _future;
            },
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: Gaps.sm),
              itemCount: conversations.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, index) {
                final conversation = conversations[index];
                final title = conversation.titleFor(_user.id);
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: conversation.isGroup
                        ? Icon(Icons.groups, color: Theme.of(context).colorScheme.primary)
                        : Text(title.isEmpty ? '?' : title[0].toUpperCase()),
                  ),
                  title: Text(
                    title,
                    style: conversation.unreadCount > 0 ? const TextStyle(fontWeight: FontWeight.w700) : null,
                  ),
                  subtitle: Text(
                    conversation.isGroup
                        ? '${conversation.members.length} participants'
                        : Formats.dateTime(conversation.updatedAt),
                  ),
                  trailing: conversation.unreadCount > 0
                      ? Badge(label: Text('${conversation.unreadCount}'))
                      : const Icon(Icons.chevron_right),
                  onTap: () => _open(conversation),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Choix des participants : un seul = conversation privée ; plusieurs = groupe (nom obligatoire).
class _NewConversationDialog extends StatefulWidget {
  const _NewConversationDialog();

  @override
  State<_NewConversationDialog> createState() => _NewConversationDialogState();
}

class _NewConversationDialogState extends State<_NewConversationDialog> {
  late final int _me = context.read<SessionController>().requireUser.id;
  final Map<int, AppUser> _selected = {};
  final _groupName = TextEditingController();
  late Future<Paged<AppUser>> _users = _search('');

  Future<Paged<AppUser>> _search(String term) =>
      context.read<UsersRepository>().list(PageQuery(pageSize: 20, filters: {'search': term, 'is_active': true}));

  @override
  void dispose() {
    _groupName.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_selected.isEmpty) return;
    final group = _selected.length > 1;
    if (group && _groupName.text.trim().isEmpty) return;
    Conversation? conversation;
    await runApiAction(context, () async {
      conversation = await context.read<ChatRepository>().start(
        memberIds: _selected.keys.toList(),
        groupName: group ? _groupName.text.trim() : null,
      );
    });
    if (conversation != null && mounted) Navigator.of(context).pop(conversation);
  }

  @override
  Widget build(BuildContext context) {
    final group = _selected.length > 1;
    return AppDialog(
      title: 'Nouvelle conversation',
      content: SizedBox(
        // Hauteur fixe pour la liste des collègues, réduite sur les petits écrans.
        height: math.min(460, MediaQuery.sizeOf(context).height * 0.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSearchField(
              hint: 'Rechercher un collègue',
              onChanged: (term) => setState(() {
                _users = _search(term);
              }),
            ),
            if (_selected.isNotEmpty) ...[
              const SizedBox(height: Gaps.sm),
              Wrap(
                spacing: Gaps.xs,
                runSpacing: Gaps.xs,
                children: [
                  for (final user in _selected.values)
                    InputChip(label: Text(user.fullName), onDeleted: () => setState(() => _selected.remove(user.id))),
                ],
              ),
            ],
            if (group) ...[
              const SizedBox(height: Gaps.sm),
              TextField(
                controller: _groupName,
                decoration: const InputDecoration(labelText: 'Nom du groupe *'),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: Gaps.sm),
            Expanded(
              child: FutureBuilder<Paged<AppUser>>(
                future: _users,
                builder: (context, snapshot) {
                  if (snapshot.hasError) return const Text('Recherche impossible.');
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final users = snapshot.data!.items.where((user) => user.id != _me).toList();
                  return ListView(
                    children: [
                      for (final user in users)
                        CheckboxListTile(
                          value: _selected.containsKey(user.id),
                          onChanged: (checked) => setState(() {
                            checked == true ? _selected[user.id] = user : _selected.remove(user.id);
                          }),
                          title: Text(user.fullName),
                          subtitle: Text(user.storeLabel),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: _selected.isEmpty || (group && _groupName.text.trim().isEmpty) ? null : _start,
          child: Text(group ? 'Créer le groupe' : 'Démarrer'),
        ),
      ],
    );
  }
}

/// Supprimer un de ses messages, après confirmation. Renvoie true si supprimé.
Future<bool> confirmDeleteMessage(BuildContext context, ChatMessage message) async {
  final confirmed = await showConfirmation(
    context,
    title: 'Supprimer ce message ?',
    message: '« ${message.content ?? ''} »\nIl sera remplacé par « Message supprimé » pour tous les participants.',
    confirmLabel: 'Supprimer',
    type: ConfirmationType.danger,
  );
  if (!confirmed || !context.mounted) return false;
  return runApiAction(context, () => context.read<ChatRepository>().deleteMessage(message.id));
}
