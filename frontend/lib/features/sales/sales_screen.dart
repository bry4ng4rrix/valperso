import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/dimensions.dart';
import '../../core/auth/current_user.dart';
import '../../core/auth/permissions.dart';
import '../../core/auth/session_controller.dart';
import '../../shared/widgets/adaptive_page.dart';
import 'new_sale_screen.dart';
import 'sales_history_screen.dart';

/// Onglets de l'écran Ventes.
enum SalesTab {
  newSale('new', 'Nouvelle vente', Icons.add_shopping_cart),
  history('history', 'Historique', Icons.receipt_long);

  const SalesTab(this.code, this.label, this.icon);
  final String code;
  final String label;
  final IconData icon;

  static SalesTab? fromCode(String? code) => values.where((tab) => tab.code == code).firstOrNull;
}

/// Toutes les pages de vente réunies : « Nouvelle vente » et « Historique ».
/// Chaque onglet n'apparaît que si l'utilisateur a la permission correspondante.
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key, this.initialTab, this.customerId});

  /// Onglet demandé par l'adresse (`/sales?tab=new` ou `/sales?tab=history`).
  final SalesTab? initialTab;

  /// Historique limité à un client (depuis la fiche client).
  final int? customerId;

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> with SingleTickerProviderStateMixin {
  late final CurrentUser _user = context.read<SessionController>().requireUser;
  late final List<SalesTab> _tabs = [
    if (_user.can(Perm.saleCreate)) SalesTab.newSale,
    if (_user.can(Perm.saleView)) SalesTab.history,
  ];
  late final TabController _controller = TabController(
    length: _tabs.length,
    vsync: this,
    initialIndex: _indexOf(_requested),
  );

  /// Onglet à ouvrir : celui de l'adresse, l'historique pour un client, sinon la nouvelle vente.
  SalesTab get _requested => widget.initialTab ?? (widget.customerId != null ? SalesTab.history : _tabs.first);

  int _indexOf(SalesTab tab) => _tabs.contains(tab) ? _tabs.indexOf(tab) : 0;

  /// Onglets déjà ouverts : construits une seule fois puis conservés (recherche, page, panier).
  late final Set<int> _opened = {_controller.index};

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (!mounted) return;
    setState(() => _opened.add(_controller.index));
  }

  @override
  void didUpdateWidget(SalesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Un lien vers l'autre onglet (ex. « Historique » depuis l'accueil) alors que l'écran est déjà ouvert.
    if (widget.initialTab != oldWidget.initialTab && widget.initialTab != null) {
      _controller.animateTo(_indexOf(widget.initialTab!));
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTabChanged);
    _controller.dispose();
    super.dispose();
  }

  Widget _content(SalesTab tab) => switch (tab) {
    SalesTab.newSale => const NewSaleScreen(),
    SalesTab.history => SalesHistoryScreen(customerId: widget.customerId, embedded: true),
  };

  @override
  Widget build(BuildContext context) {
    if (_tabs.length == 1) {
      return AdaptivePage(title: 'Ventes', body: _content(_tabs.single));
    }
    return AdaptivePage(
      title: 'Ventes',
      bottom: TabBar(
        controller: _controller,
        tabs: [
          for (final tab in _tabs)
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(tab.icon, size: 18),
                  const SizedBox(width: Gaps.sm),
                  Flexible(child: Text(tab.label, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
        ],
      ),
      // IndexedStack plutôt qu'une vue qui glisse : aucun défilement horizontal parasite
      // (listes, puces de filtre, champs qui demandent à être visibles).
      body: IndexedStack(
        index: _controller.index,
        children: [
          for (final (index, tab) in _tabs.indexed) _opened.contains(index) ? _content(tab) : const SizedBox.shrink(),
        ],
      ),
    );
  }
}
