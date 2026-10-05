import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app/theme/dimensions.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../core/widgets/notifications.dart';
import '../../shared/utils/api_form.dart';
import '../../shared/utils/validators.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/states.dart';
import '../invoices/invoice_actions.dart';
import 'company_repository.dart';
import '../../shared/widgets/responsive_grid.dart';

/// Choix du logo dans les fichiers / la galerie. Remplacé dans les tests (pas de galerie).
@visibleForTesting
Future<XFile?> Function() pickCompanyLogo = () =>
    ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024, imageQuality: 90);

/// Informations de la société (en-tête des factures). Modification réservée à `company.update`,
/// avec confirmation des changements. Les factures déjà émises ne changent pas.
class CompanyScreen extends StatefulWidget {
  const CompanyScreen({super.key, this.startEditing = false});

  /// Ouvert depuis Paramètres → Société → Modifier : le formulaire s'affiche directement.
  final bool startEditing;

  @override
  State<CompanyScreen> createState() => _CompanyScreenState();
}

class _CompanyScreenState extends State<CompanyScreen> with ApiFormState {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _logo = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  Company? _company;
  late bool _editing = widget.startEditing;
  bool _uploadingLogo = false;
  late Future<void> _ready = _load();

  Future<void> _load() async {
    final company = await context.read<CompanyRepository>().get();
    _apply(company);
  }

  void _apply(Company company) {
    _company = company;
    _name.text = Formats.title(company.name);
    _logo.text = company.logoUrl ?? '';
    _phone.text = company.phone ?? '';
    _email.text = company.email ?? '';
    _address.text = Formats.title(company.address ?? '');
    _city.text = Formats.title(company.city ?? '');
  }

  /// Le logo choisi est envoyé et enregistré tout de suite ; les autres champs, avec « Enregistrer ».
  Future<void> _pickLogo() async {
    final file = await pickCompanyLogo();
    if (file == null || !mounted) return;
    setState(() => _uploadingLogo = true);
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final repository = context.read<CompanyRepository>();
    Company? saved;
    await runApiAction(
      context,
      () async => saved = await repository.uploadLogo(bytes, file.name.isEmpty ? 'logo' : file.name),
      success: 'Logo enregistré.',
    );
    if (!mounted) return;
    setState(() {
      _uploadingLogo = false;
      if (saved case final company?) {
        _company = company;
        _logo.text = company.logoUrl ?? '';
      }
    });
  }

  @override
  void dispose() {
    for (final controller in [_name, _logo, _phone, _email, _address, _city]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final before = _company!;
    final after = Company(
      name: _name.text.trim(),
      logoUrl: trimOrNull(_logo.text),
      phone: trimOrNull(_phone.text),
      email: trimOrNull(_email.text),
      address: trimOrNull(_address.text),
      city: trimOrNull(_city.text),
    );
    String norm(String? value) => (value ?? '').trim().toUpperCase();
    final diff = [
      if (norm(after.name) != norm(before.name)) FieldChange('Nom', Formats.title(before.name), after.name),
      if ((after.logoUrl ?? '') != (before.logoUrl ?? ''))
        FieldChange('Logo', before.logoUrl ?? '—', after.logoUrl ?? '—'),
      if ((after.phone ?? '') != (before.phone ?? ''))
        FieldChange('Téléphone', before.phone ?? '—', after.phone ?? '—'),
      if (norm(after.email) != norm(before.email)) FieldChange('Email', before.email ?? '—', after.email ?? '—'),
      if (norm(after.address) != norm(before.address))
        FieldChange('Adresse', Formats.title(before.address ?? '—'), after.address ?? '—'),
      if (norm(after.city) != norm(before.city))
        FieldChange('Ville', Formats.title(before.city ?? '—'), after.city ?? '—'),
    ];
    if (diff.isEmpty) {
      setState(() => _editing = false);
      return Notify.info(context, 'Aucune modification.');
    }
    final confirmed = await showConfirmation(
      context,
      title: 'Modifier les informations de la société ?',
      message: 'Les nouvelles factures utiliseront ces informations. Les factures déjà émises ne changent pas.',
      changes: diff,
      confirmLabel: 'Enregistrer',
      type: ConfirmationType.warning,
    );
    if (!confirmed || !mounted) return;
    final saved = await submitToApi(() => context.read<CompanyRepository>().update(after));
    if (saved == null || !mounted) return;
    setState(() {
      _apply(saved);
      _editing = false;
    });
    Notify.success(context, 'Informations de la société enregistrées.');
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = context.watch<SessionController>().requireUser.can(Perm.companyUpdate);
    return DetailPage(
      title: 'Société',
      actions: [
        if (canEdit && !_editing && _company != null)
          IconButton(
            tooltip: 'Modifier',
            onPressed: () => setState(() => _editing = true),
            icon: const Icon(Icons.edit_outlined),
          ),
      ],
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
          if (snapshot.connectionState != ConnectionState.done) return const LoadingState(lines: 3);
          return _editing && canEdit ? _form() : _view(canEdit: canEdit);
        },
      ),
    );
  }

  Widget _view({required bool canEdit}) {
    final company = _company!;
    final logoUrl = resolveLogoUrl(company.logoUrl, context.read<ApiClient>().baseUrl);
    return ListView(
      padding: const EdgeInsets.all(Gaps.lg),
      children: [
        SectionCard(
          title: 'Informations affichées sur les factures',
          icon: Icons.business_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (logoUrl != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gaps.md),
                  child: Image.network(
                    logoUrl,
                    height: 72,
                    errorBuilder: (_, _, _) => const Text('Logo inaccessible à cette adresse.'),
                  ),
                ),
              InfoRow(label: 'Nom', value: Formats.title(company.name)),
              InfoRow(label: 'Téléphone', value: company.phone ?? '—'),
              InfoRow(label: 'Email', value: company.email ?? '—'),
              InfoRow(label: 'Adresse', value: Formats.title(company.address ?? '—')),
              InfoRow(label: 'Ville', value: Formats.title(company.city ?? '—')),
              InfoRow(label: 'Logo', value: company.logoUrl ?? '—'),
            ],
          ),
        ),
        const SizedBox(height: Gaps.md),
        Text(
          'Message de remerciement des factures : « Merci pour votre achat ! À bientôt chez ${Formats.title(company.name)}. »',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (canEdit) ...[
          const SizedBox(height: Gaps.xl),
          AppButton(
            label: 'Modifier les informations',
            icon: Icons.edit_outlined,
            expand: true,
            onPressed: () async => setState(() => _editing = true),
          ),
        ],
      ],
    );
  }

  Widget _logoEditor() {
    final path = _logo.text.trim();
    final url = resolveLogoUrl(path.isEmpty ? null : path, context.read<ApiClient>().baseUrl);
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 80,
          height: 80,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: url == null
              ? const Icon(Icons.image_outlined)
              : Image.network(url, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(Icons.broken_image)),
        ),
        const SizedBox(width: Gaps.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Logo (factures et tickets)', style: theme.textTheme.titleSmall),
              const SizedBox(height: Gaps.xs),
              Wrap(
                spacing: Gaps.sm,
                runSpacing: Gaps.xs,
                children: [
                  OutlinedButton.icon(
                    onPressed: _uploadingLogo ? null : _pickLogo,
                    icon: _uploadingLogo
                        ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.upload_outlined),
                    label: Text(url == null ? 'Choisir une image' : 'Changer le logo'),
                  ),
                  if (url != null)
                    TextButton.icon(
                      onPressed: () => setState(_logo.clear),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Retirer'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _form() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(Gaps.lg),
        children: [
          SectionCard(
            title: 'Modifier',
            icon: Icons.edit_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _logoEditor(),
                const SizedBox(height: Gaps.lg),
                ResponsiveGrid(
                  minItemWidth: 300,
                  maxColumns: 3,
                  children: [
                    AppTextField(
                      label: 'Nom de la société',
                      controller: _name,
                      required: true,
                      errorText: errorFor('name'),
                      validator: Validators.text(required: true, min: 2, max: 150),
                    ),
                    AppTextField(
                      label: 'Téléphone',
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      errorText: errorFor('phone'),
                      validator: Validators.phone,
                    ),
                    AppTextField(
                      label: 'Email',
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      errorText: errorFor('email'),
                      validator: Validators.email,
                    ),
                    AppTextField(
                      label: 'Adresse',
                      controller: _address,
                      errorText: errorFor('address'),
                      validator: Validators.text(required: false, max: 255),
                    ),
                    AppTextField(
                      label: 'Ville',
                      controller: _city,
                      errorText: errorFor('city'),
                      validator: Validators.text(required: false, max: 100),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: Gaps.xl),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _apply(_company!);
                    _editing = false;
                  }),
                  child: const Text('Annuler'),
                ),
              ),
              const SizedBox(width: Gaps.md),
              Expanded(
                child: AppButton(label: 'Enregistrer', icon: Icons.check, expand: true, onPressed: _save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
