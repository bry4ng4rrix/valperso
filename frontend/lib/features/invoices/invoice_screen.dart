import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/api/api_client.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/status_badge.dart';
import '../sales/sale_models.dart';
import '../sales/sales_repository.dart';
import 'invoice_actions.dart';

/// Facture d'une vente : aperçu, partage et enregistrement en PDF.
/// Les informations de la société sont celles en vigueur au moment de la vente.
class InvoiceScreen extends StatefulWidget {
  const InvoiceScreen({super.key, required this.saleId});

  final int saleId;

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  late Future<Invoice> _future = context.read<SalesRepository>().invoice(widget.saleId);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Invoice>(
      future: _future,
      builder: (context, snapshot) {
        final invoice = snapshot.data;
        return DetailPage(
          title: invoice == null ? 'Facture' : 'Facture ${invoice.number}',
          maxWidth: 820,
          bottomBar: invoice == null
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(Gaps.md),
                    child: Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            label: 'Enregistrer PDF',
                            icon: Icons.download_outlined,
                            variant: AppButtonVariant.secondary,
                            expand: true,
                            onPressed: () => saveInvoice(context, invoice),
                          ),
                        ),
                        const SizedBox(width: Gaps.md),
                        Expanded(
                          child: AppButton(
                            label: 'Partager',
                            icon: Icons.share_outlined,
                            expand: true,
                            onPressed: () => shareInvoice(context, widget.saleId, invoice: invoice),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          child: snapshot.hasError
              ? ErrorState(
                  message: errorMessageOf(snapshot.error),
                  onRetry: () => setState(() {
                    _future = context.read<SalesRepository>().invoice(widget.saleId);
                  }),
                )
              : invoice == null
              ? const LoadingState(lines: 5)
              : ListView(
                  padding: const EdgeInsets.all(Gaps.lg),
                  children: [InvoiceView(invoice: invoice)],
                ),
        );
      },
    );
  }
}

/// Rendu de la facture à l'écran (même contenu que le PDF).
class InvoiceView extends StatelessWidget {
  const InvoiceView({super.key, required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall;
    final logoUrl = resolveLogoUrl(invoice.logoUrl, context.read<ApiClient>().baseUrl);
    return AppCard(
      padding: const EdgeInsets.all(Gaps.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: Gaps.lg,
            runSpacing: Gaps.lg,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (logoUrl != null)
                    Padding(
                      padding: const EdgeInsets.only(right: Gaps.md),
                      child: Image.network(
                        logoUrl,
                        width: 56,
                        height: 56,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Formats.title(invoice.companyName),
                        style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary),
                      ),
                      if (invoice.companyAddress != null) Text(Formats.title(invoice.companyAddress), style: muted),
                      if (invoice.companyCity != null) Text(Formats.title(invoice.companyCity), style: muted),
                      if (invoice.companyPhone != null) Text('Tél. ${invoice.companyPhone}', style: muted),
                      if (invoice.companyEmail != null) Text(invoice.companyEmail!, style: muted),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('FACTURE', style: theme.textTheme.titleLarge),
                  Text(invoice.number, style: theme.textTheme.titleSmall),
                  Text(Formats.dateTime(invoice.date), style: muted),
                  const SizedBox(height: Gaps.xs),
                  if (invoice.status == 'CANCELLED')
                    Badges.saleStatus(invoice.status)
                  else
                    Badges.paymentStatus(invoice.paymentStatus.code),
                ],
              ),
            ],
          ),
          const Divider(height: Gaps.xxl),
          Wrap(
            spacing: Gaps.xxl,
            runSpacing: Gaps.md,
            children: [
              _Block(
                title: 'Magasin',
                lines: [
                  invoice.storeName.toLowerCase() == 'stock local' ? 'Stock Local' : Formats.title(invoice.storeName),
                  if (invoice.storeAddress != null) Formats.title(invoice.storeAddress),
                  if (invoice.storePhone != null) 'Tél. ${invoice.storePhone}',
                  'Vendeur : ${invoice.seller.fullName}',
                ],
              ),
              _Block(
                title: 'Client',
                lines: [
                  invoice.customer.fullName,
                  if (invoice.customer.phone != null) 'Tél. ${invoice.customer.phone}',
                ],
              ),
            ],
          ),
          const SizedBox(height: Gaps.xl),
          for (final line in invoice.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: Gaps.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(Formats.capitalize(line.name)),
                        Text(
                          '${line.reference.toUpperCase()} · ${line.quantity} × ${Formats.money(line.unitPrice)}',
                          style: muted,
                        ),
                      ],
                    ),
                  ),
                  Text(Formats.money(line.total), style: theme.textTheme.titleSmall),
                ],
              ),
            ),
          const Divider(height: Gaps.xl),
          InfoRow(label: 'Sous-total', value: Formats.money(invoice.subtotal)),
          if (invoice.discountAmount > 0) InfoRow(label: 'Remise', value: '- ${Formats.money(invoice.discountAmount)}'),
          InfoRow(label: 'Total', value: Formats.money(invoice.total), emphasis: true),
          InfoRow(label: 'Payé', value: Formats.money(invoice.amountPaid)),
          if (invoice.remainingAmount > 0) ...[
            InfoRow(
              label: 'Reste à payer',
              value: Formats.money(invoice.remainingAmount),
              valueStyle: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600),
            ),
            if (invoice.dueDate != null) InfoRow(label: 'Échéance', value: Formats.date(invoice.dueDate)),
          ],
          if (invoice.payments.isNotEmpty) ...[
            const SizedBox(height: Gaps.md),
            Text('Paiements', style: theme.textTheme.titleSmall),
            for (final payment in invoice.payments)
              Text(
                '${Formats.dateTime(payment.createdAt)} — ${payment.method.label} — ${Formats.money(payment.amount)}',
                style: muted,
              ),
          ],
          const SizedBox(height: Gaps.xl),
          for (final line in invoice.thankYouMessage)
            Text(
              line,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary),
            ),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 200),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.labelMedium),
          for (final (index, line) in lines.indexed)
            Text(line, style: index == 0 ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
