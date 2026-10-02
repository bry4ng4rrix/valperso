import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/dimensions.dart';
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
import 'store_models.dart';
import 'stores_repository.dart';
import '../../shared/widgets/responsive_grid.dart';

/// Création ou modification d'un magasin. Un magasin est créé sans vendeur.
class StoreFormScreen extends StatefulWidget {
  const StoreFormScreen({super.key, this.storeId});

  final int? storeId;

  @override
  State<StoreFormScreen> createState() => _StoreFormScreenState();
}

class _StoreFormScreenState extends State<StoreFormScreen> with ApiFormState {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  Store? _store;
  late Future<void> _ready = _load();

  Future<void> _load() async {
    final id = widget.storeId;
    if (id == null) return;
    final store = await context.read<StoresRepository>().get(id);
    _store = store;
    _name.text = store.isCentral ? Formats.title(store.name) : store.label;
    _address.text = Formats.title(store.address ?? '');
    _phone.text = store.phone ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repository = context.read<StoresRepository>();
    final name = _name.text.trim();
    final address = trimOrNull(_address.text);
    final phone = trimOrNull(_phone.text);
    final existing = _store;
    Store? saved;
    if (existing == null) {
      final confirmed = await showConfirmation(
        context,
        title: 'Créer le magasin $name ?',
        message:
            'Le magasin est créé sans vendeur et sans stock. '
            'Affectez ensuite un vendeur (Utilisateurs) et transférez des produits depuis le Stock Local.',
        confirmLabel: 'Créer',
      );
      if (!confirmed || !mounted) return;
      saved = await submitToApi(() => repository.create(name: name, address: address, phone: phone));
    } else {
      String norm(String? value) => (value ?? '').trim().toUpperCase();
      final changes = <String, Object?>{};
      final diff = <FieldChange>[];
      if (norm(name) != norm(existing.name)) {
        changes['name'] = name;
        diff.add(FieldChange('Nom', Formats.title(existing.name), name));
      }
      if (norm(address) != norm(existing.address)) {
        changes['address'] = address;
        diff.add(FieldChange('Adresse', Formats.title(existing.address ?? '—'), address ?? '—'));
      }
      if ((phone ?? '') != (existing.phone ?? '')) {
        changes['phone'] = phone;
        diff.add(FieldChange('Téléphone', existing.phone ?? '—', phone ?? '—'));
      }
      if (diff.isEmpty) return Notify.info(context, 'Aucune modification à enregistrer.');
      final confirmed = await showConfirmation(
        context,
        title: 'Enregistrer les modifications ?',
        message: 'Les factures déjà émises conservent les anciennes informations.',
        changes: diff,
        confirmLabel: 'Enregistrer',
      );
      if (!confirmed || !mounted) return;
      saved = await submitToApi(() => repository.update(existing.id, changes));
    }
    if (saved == null || !mounted) return;
    Notify.success(context, existing == null ? 'Magasin créé.' : 'Magasin modifié.');
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    return DetailPage(
      title: widget.storeId == null ? 'Nouveau magasin' : 'Modifier le magasin',
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
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(Gaps.lg),
              children: [
                SectionCard(
                  title: 'Magasin',
                  icon: Icons.storefront_outlined,
                  child: ResponsiveGrid(
                    minItemWidth: 300,
                    maxColumns: 3,
                    children: [
                      AppTextField(
                        label: 'Nom',
                        controller: _name,
                        required: true,
                        errorText: errorFor('name'),
                        validator: Validators.text(required: true, min: 2, max: 150),
                        helper: 'Ex. H109',
                      ),
                      AppTextField(
                        label: 'Adresse',
                        controller: _address,
                        errorText: errorFor('address'),
                        validator: Validators.text(required: false, max: 255),
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
                const SizedBox(height: Gaps.xl),
                AppButton(
                  label: widget.storeId == null ? 'Créer le magasin' : 'Enregistrer les modifications',
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
