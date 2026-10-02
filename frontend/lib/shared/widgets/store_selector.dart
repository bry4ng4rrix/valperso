import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/dimensions.dart';
import '../../features/stores/store_models.dart';
import '../../features/stores/stores_repository.dart';

/// Choix d'un magasin parmi les magasins actifs (réservé aux utilisateurs qui peuvent les voir).
class StoreSelector extends StatelessWidget {
  const StoreSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Magasin',
    this.allLabel,
    this.excludeId,
    this.dense = false,
  });

  final int? value;
  final ValueChanged<Store?> onChanged;
  final String label;

  /// Libellé de l'option « tous les magasins ». Null : un magasin doit être choisi.
  final String? allLabel;

  /// Magasin à masquer (ex. le magasin source d'un transfert).
  final int? excludeId;

  /// Version compacte pour une barre d'outils.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Store>>(
      future: context.read<StoresRepository>().active(),
      builder: (context, snapshot) {
        final stores = (snapshot.data ?? const <Store>[]).where((store) => store.id != excludeId).toList();
        final known = stores.any((store) => store.id == value);
        return DropdownButtonFormField<int?>(
          key: ValueKey('store-$value-${stores.length}'),
          initialValue: known ? value : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            isDense: dense,
            prefixIcon: const Icon(Icons.storefront_outlined, size: 20),
            contentPadding: dense ? const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.sm) : null,
          ),
          hint: Text(snapshot.connectionState == ConnectionState.waiting ? 'Chargement...' : 'Choisir un magasin'),
          items: [
            if (allLabel != null) DropdownMenuItem<int?>(value: null, child: Text(allLabel!)),
            for (final store in stores) DropdownMenuItem<int?>(value: store.id, child: Text(store.label)),
          ],
          onChanged: (id) => onChanged(id == null ? null : stores.firstWhere((store) => store.id == id)),
        );
      },
    );
  }
}
