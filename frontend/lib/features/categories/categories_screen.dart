import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/api/paged_controller.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../core/export/excel_export.dart';
import '../../core/widgets/confirmation_dialog.dart';
import '../../shared/utils/api_form.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/export_button.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/paged_list_view.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/status_badge.dart';
import 'categories_repository.dart';
import 'category_dialog.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late final PagedController<Category> _controller = PagedController(
    (query) => context.read<CategoriesRepository>().list(query),
    filters: const {'is_active': true},
  );

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _edit(Category category) async {
    final user = context.read<SessionController>().requireUser;
    if (!user.can(Perm.productUpdate)) return;
    final saved = await showCategoryDialog(context, category: category);
    if (saved != null && mounted) await _controller.refresh();
  }

  Future<void> _toggle(Category category) async {
    final deactivate = category.isActive;
    final confirmed = await showConfirmation(
      context,
      title: deactivate ? 'Désactiver « ${category.label} » ?' : 'Réactiver « ${category.label} » ?',
      message: deactivate ? 'Les produits de cette catégorie sont conservés.' : null,
      changes: [FieldChange('Statut', deactivate ? 'Active' : 'Inactive', deactivate ? 'Inactive' : 'Active')],
      confirmLabel: deactivate ? 'Désactiver' : 'Réactiver',
      type: deactivate ? ConfirmationType.danger : ConfirmationType.normal,
    );
    if (!confirmed || !mounted) return;
    final repository = context.read<CategoriesRepository>();
    final done = await runApiAction(
      context,
      () => deactivate ? repository.deactivate(category.id) : repository.update(category.id, {'is_active': true}),
      success: deactivate ? 'Catégorie désactivée.' : 'Catégorie réactivée.',
    );
    if (done && mounted) await _controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().requireUser;
    // Actions en icônes : modifier, désactiver / réactiver.
    Widget actions(Category category) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (user.can(Perm.productUpdate))
          IconButton(tooltip: 'Modifier', onPressed: () => _edit(category), icon: const Icon(Icons.edit_outlined)),
        if (category.isActive && user.can(Perm.productDelete))
          IconButton(
            tooltip: 'Désactiver',
            onPressed: () => _toggle(category),
            icon: const Icon(Icons.block, color: AppColors.danger),
          ),
        if (!category.isActive && user.can(Perm.productUpdate))
          IconButton(
            tooltip: 'Réactiver',
            onPressed: () => _toggle(category),
            icon: const Icon(Icons.check_circle_outline, color: AppColors.success),
          ),
      ],
    );

    return ListPage(
      title: 'Catégories',
      controller: _controller,
      countLabel: (total) => '$total catégorie${total > 1 ? 's' : ''}',
      search: AppSearchField(hint: 'Nom de la catégorie', onChanged: (value) => _controller.setFilter('search', value)),
      quickFilters: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Wrap(
          spacing: Gaps.sm,
          children: [
            for (final (value, label) in const [(true, 'Actives'), (false, 'Inactives'), (null, 'Toutes')])
              ChoiceChip(
                label: Text(label),
                selected: _controller.filter('is_active') == value,
                onSelected: (_) => _controller.setFilter('is_active', value),
              ),
          ],
        ),
      ),
      actions: [
        ExportButton<Category>(
          controller: _controller,
          fileBaseName: 'categories',
          sheetName: 'Catégories',
          columns: [
            ExportColumn('Nom', (category) => category.label),
            ExportColumn('Active', (category) => category.isActive),
          ],
        ),
      ],
      primaryAction: user.can(Perm.productCreate)
          ? PrimaryAction(
              label: 'Nouvelle catégorie',
              icon: Icons.add,
              onPressed: () async {
                final saved = await showCategoryDialog(context);
                if (saved != null && mounted) await _controller.refresh();
              },
            )
          : null,
      body: PagedListView<Category>(
        controller: _controller,
        onTap: _edit,
        emptyTitle: 'Aucune catégorie',
        columns: [
          TableColumnDef.text('Nom', (category) => category.label),
          TableColumnDef('Statut', (category) => Badges.active(category.isActive)),
          TableColumnDef('Actions', actions),
        ],
        cardBuilder: (context, category) => AppCard(
          onTap: () => _edit(category),
          padding: const EdgeInsets.fromLTRB(Gaps.md, Gaps.xs, Gaps.xs, Gaps.xs),
          child: Row(
            children: [
              Expanded(child: Text(category.label, style: Theme.of(context).textTheme.titleSmall)),
              if (!category.isActive) Badges.active(false),
              actions(category),
            ],
          ),
        ),
      ),
    );
  }
}
