import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/dimensions.dart';
import '../../core/auth/session_controller.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../core/widgets/notifications.dart';
import '../../shared/utils/api_form.dart';
import '../../shared/utils/validators.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/store_selector.dart';
import 'user_models.dart';
import 'users_repository.dart';
import '../../shared/widgets/responsive_grid.dart';

/// Création d'un utilisateur, ou modification de ses informations
/// (le rôle, le magasin et le statut se changent depuis la fiche).
class UserFormScreen extends StatefulWidget {
  const UserFormScreen({super.key, this.userId});

  final int? userId;

  @override
  State<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends State<UserFormScreen> with ApiFormState {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();
  String _role = 'VENDEUR';
  int? _storeId;
  bool _hidePassword = true;
  AppUser? _user;
  late Future<void> _ready = _load();

  bool get _isEdit => widget.userId != null;

  Future<void> _load() async {
    final id = widget.userId;
    if (id == null) return;
    final user = await context.read<UsersRepository>().get(id);
    _user = user;
    _firstName.text = _cap(user.firstName);
    _lastName.text = _cap(user.lastName);
    _username.text = user.username.toLowerCase();
    _email.text = user.email ?? '';
    _phone.text = user.phone ?? '';
  }

  String _cap(String value) => value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

  @override
  void dispose() {
    for (final controller in [_firstName, _lastName, _username, _email, _phone, _password, _passwordConfirm]) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, Object?> get _identity => {
    'first_name': _firstName.text.trim(),
    'last_name': _lastName.text.trim(),
    'username': _username.text.trim(),
    'email': trimOrNull(_email.text),
    'phone': trimOrNull(_phone.text),
  };

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return Notify.warning(context, 'Corrigez les champs signalés.');
    final repository = context.read<UsersRepository>();
    final existing = _user;
    AppUser? saved;
    if (existing == null) {
      final confirmed = await showConfirmation(
        context,
        title: 'Créer cet utilisateur ?',
        message:
            '${_firstName.text.trim()} ${_lastName.text.trim()} — $_role'
            '${_role == 'VENDEUR' && _storeId == null ? '\nAttention : aucun magasin affecté.' : ''}',
        confirmLabel: 'Créer',
        type: _role == 'ADMIN' ? ConfirmationType.warning : ConfirmationType.normal,
      );
      if (!confirmed || !mounted) return;
      saved = await submitToApi(
        () => repository.create({
          ..._identity,
          'password': _password.text,
          'role': _role,
          'store_id': _storeId,
          'is_active': true,
        }),
      );
    } else {
      String norm(String? value) => (value ?? '').trim().toUpperCase();
      final identity = _identity;
      final diff = <FieldChange>[
        if (norm(identity['first_name'] as String) != norm(existing.firstName))
          FieldChange('Prénom', _cap(existing.firstName), '${identity['first_name']}'),
        if (norm(identity['last_name'] as String) != norm(existing.lastName))
          FieldChange('Nom', _cap(existing.lastName), '${identity['last_name']}'),
        if (norm(identity['username'] as String) != norm(existing.username))
          FieldChange('Identifiant', existing.username.toLowerCase(), '${identity['username']}'),
        if (norm(identity['email'] as String?) != norm(existing.email))
          FieldChange('Email', existing.email ?? '—', '${identity['email'] ?? '—'}'),
        if ((identity['phone'] ?? '') != (existing.phone ?? ''))
          FieldChange('Téléphone', existing.phone ?? '—', '${identity['phone'] ?? '—'}'),
        if (_password.text.isNotEmpty) const FieldChange('Mot de passe', '••••••••', 'nouveau mot de passe'),
      ];
      if (diff.isEmpty) return Notify.info(context, 'Aucune modification à enregistrer.');
      final confirmed = await showConfirmation(
        context,
        title: 'Enregistrer les modifications ?',
        changes: diff,
        message: _password.text.isNotEmpty
            ? 'Le changement de mot de passe ferme les sessions en cours de ce compte.'
            : null,
        confirmLabel: 'Enregistrer',
        type: _password.text.isNotEmpty ? ConfirmationType.warning : ConfirmationType.normal,
      );
      if (!confirmed || !mounted) return;
      saved = await submitToApi(
        () => repository.update(existing.id, {...identity, if (_password.text.isNotEmpty) 'password': _password.text}),
      );
    }
    if (saved == null || !mounted) return;
    _password.clear();
    _passwordConfirm.clear();
    final session = context.read<SessionController>();
    if (session.user?.id == saved.id) await session.reloadProfile();
    if (!mounted) return;
    Notify.success(context, existing == null ? 'Utilisateur créé.' : 'Utilisateur modifié.');
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    return DetailPage(
      title: _isEdit ? 'Modifier l\'utilisateur' : 'Nouvel utilisateur',
      child: FutureBuilder<void>(
        future: _ready,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(
              message: errorMessageOf(snapshot.error),
              onRetry: () => setState(() {
                _ready = _load();
              }),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) return const LoadingState(lines: 4);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(Gaps.lg),
              children: [
                TwoColumns(
                  breakpoint: 860,
                  left: SectionCard(
                    title: 'Identité',
                    icon: Icons.person_outline,
                    child: ResponsiveGrid(
                      minItemWidth: 300,
                      maxColumns: 3,
                      children: [
                        AppTextField(
                          label: 'Prénom',
                          controller: _firstName,
                          required: true,
                          errorText: errorFor('first_name'),
                          validator: Validators.text(required: true, max: 100),
                        ),
                        AppTextField(
                          label: 'Nom',
                          controller: _lastName,
                          required: true,
                          errorText: errorFor('last_name'),
                          validator: Validators.text(required: true, max: 100),
                        ),
                        AppTextField(
                          label: 'Identifiant de connexion',
                          controller: _username,
                          required: true,
                          errorText: errorFor('username'),
                          validator: Validators.username,
                        ),
                        AppTextField(
                          label: 'Email',
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          errorText: errorFor('email'),
                          validator: Validators.email,
                        ),
                        AppTextField(
                          label: 'Téléphone',
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          errorText: errorFor('phone'),
                          validator: Validators.phone,
                        ),
                      ],
                    ),
                  ),
                  right: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_isEdit) ...[
                        SectionCard(
                          title: 'Accès',
                          icon: Icons.admin_panel_settings_outlined,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment(
                                    value: 'VENDEUR',
                                    label: Text('Vendeur'),
                                    icon: Icon(Icons.person_outline),
                                  ),
                                  ButtonSegment(
                                    value: 'ADMIN',
                                    label: Text('Administrateur'),
                                    icon: Icon(Icons.shield_outlined),
                                  ),
                                ],
                                selected: {_role},
                                onSelectionChanged: (selection) => setState(() => _role = selection.first),
                              ),
                              const SizedBox(height: Gaps.md),
                              StoreSelector(
                                value: _storeId,
                                label: _role == 'VENDEUR' ? 'Magasin (recommandé)' : 'Magasin',
                                allLabel: 'Aucun magasin',
                                onChanged: (store) => setState(() => _storeId = store?.id),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: Gaps.lg),
                      ],
                      SectionCard(
                        title: _isEdit ? 'Nouveau mot de passe (facultatif)' : 'Mot de passe',
                        icon: Icons.lock_outline,
                        child: Column(
                          children: [
                            AppTextField(
                              label: 'Mot de passe',
                              controller: _password,
                              obscureText: _hidePassword,
                              required: !_isEdit,
                              errorText: errorFor('password'),
                              validator: (value) => Validators.password(value, required: !_isEdit),
                              helper: '8 caractères minimum.',
                              suffix: IconButton(
                                onPressed: () => setState(() => _hidePassword = !_hidePassword),
                                icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                              ),
                            ),
                            const SizedBox(height: Gaps.md),
                            AppTextField(
                              label: 'Confirmer le mot de passe',
                              controller: _passwordConfirm,
                              obscureText: _hidePassword,
                              required: !_isEdit,
                              validator: (value) =>
                                  (value ?? '') == _password.text ? null : 'Les mots de passe ne correspondent pas.',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Gaps.xl),
                AppButton(
                  label: _isEdit ? 'Enregistrer les modifications' : 'Créer l\'utilisateur',
                  icon: Icons.check,
                  expand: true,
                  onPressed: _save,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
