import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/navigation.dart';
import '../../app/theme/dimensions.dart';
import '../../core/api/api_client.dart';
import '../../core/realtime/live_refresh.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_card.dart';
import '../invoices/invoice_actions.dart';
import 'company_repository.dart';

/// Section « Société » des paramètres : informations actuelles, et bouton Modifier si autorisé
/// (ouvre directement le formulaire). Mise à jour en direct si un autre ADMIN les modifie.
class CompanySummaryCard extends StatefulWidget {
  const CompanySummaryCard({super.key, required this.canEdit});

  final bool canEdit;

  @override
  State<CompanySummaryCard> createState() => _CompanySummaryCardState();
}

class _CompanySummaryCardState extends State<CompanySummaryCard> {
  late Future<Company> _company = context.read<CompanyRepository>().get();

  void _reload() => setState(() {
    _company = context.read<CompanyRepository>().get();
  });

  Future<void> _open({required bool edit}) async {
    await context.push(edit ? '${Routes.company}?edit=1' : Routes.company);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return LiveRefresh(
      entities: const {'company'},
      onChange: _reload,
      child: SectionCard(
        title: 'Société',
        icon: Icons.business_outlined,
        trailing: widget.canEdit
            ? TextButton(onPressed: () => _open(edit: true), child: const Text('Modifier'))
            : TextButton(onPressed: () => _open(edit: false), child: const Text('Voir')),
        child: FutureBuilder<Company>(
          future: _company,
          builder: (context, snapshot) {
            final company = snapshot.data;
            if (company == null) {
              return snapshot.hasError
                  ? const Text('Informations indisponibles.')
                  : const LinearProgressIndicator(minHeight: 2);
            }
            final logoUrl = resolveLogoUrl(company.logoUrl, context.read<ApiClient>().baseUrl);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (logoUrl != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.md),
                    child: Image.network(
                      logoUrl,
                      width: 56,
                      height: 56,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox.square(dimension: 56),
                    ),
                  ),
                  const SizedBox(width: Gaps.md),
                ],
                Expanded(
                  child: Column(
                    children: [
                      InfoRow(label: 'Nom', value: Formats.title(company.name)),
                      InfoRow(label: 'Téléphone', value: company.phone ?? '—'),
                      InfoRow(label: 'Email', value: company.email ?? '—'),
                      InfoRow(
                        label: 'Adresse',
                        value: [
                          if (company.address != null) Formats.title(company.address),
                          if (company.city != null) Formats.title(company.city),
                        ].join(', ').ifEmpty('—'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
