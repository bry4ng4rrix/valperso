import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' show Barcode, BarcodeBar;
import 'package:provider/provider.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/api/api_client.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/list_page.dart';
import '../../shared/widgets/states.dart';
import '../sales/sale_models.dart';
import '../sales/sales_repository.dart';
import 'invoice_actions.dart';
import 'receipt.dart';

/// Facture d'une vente au format ticket de caisse : aperçu, impression et partage en PDF.
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
          bottomBar: invoice == null
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(Gaps.md),
                    child: Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            label: 'Imprimer',
                            icon: Icons.print_outlined,
                            expand: true,
                            onPressed: () => printInvoice(context, invoice),
                          ),
                        ),
                        const SizedBox(width: Gaps.md),
                        Expanded(
                          child: AppButton(
                            label: sharePdfLabel,
                            icon: Icons.picture_as_pdf_outlined,
                            variant: AppButtonVariant.secondary,
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

/// Rendu de la facture à l'écran : le ticket de caisse, avec le même contenu que le PDF.
class InvoiceView extends StatelessWidget {
  const InvoiceView({super.key, required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final logoUrl = resolveLogoUrl(invoice.logoUrl, context.read<ApiClient>().baseUrl);
    const bold = TextStyle(fontWeight: FontWeight.w700);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        // Papier blanc et encre noire dans les deux thèmes, comme le ticket imprimé.
        child: PhysicalShape(
          clipper: const _TornEdges(),
          color: AppColors.receiptPaper,
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.xxl, Gaps.xl, Gaps.xxl),
            child: DefaultTextStyle(
              style: const TextStyle(
                fontFamily: 'monospace',
                fontFamilyFallback: ['DejaVu Sans Mono', 'Courier New'],
                fontSize: 13,
                height: 1.35,
                color: AppColors.receiptInk,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (logoUrl != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Gaps.sm),
                      child: Image.network(
                        logoUrl,
                        width: 56,
                        height: 56,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  _Centered(
                    invoice.companyName.toUpperCase(),
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                  ),
                  for (final line in invoice.companyLines) _Centered(line),
                  const _Dashes(),
                  for (final (label, value) in invoice.infoRows)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(receiptLabel(label, invoice.infoRows)),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: Gaps.sm),
                            child: Text(value),
                          ),
                        ),
                      ],
                    ),
                  if (invoice.status == 'CANCELLED') ...[
                    const SizedBox(height: Gaps.sm),
                    const _Centered(
                      '*** VENTE ANNULÉE ***',
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger),
                    ),
                  ],
                  const _Dashes(),
                  for (final line in invoice.lines) ...[
                    Text(line.name.toUpperCase()),
                    if (line.description != null) Text('  ${Formats.capitalize(line.description)}'),
                    _Line('  ${line.receiptDetail}', Formats.amount(line.total)),
                    const SizedBox(height: 2),
                  ],
                  const _Dashes(),
                  _Line('NB ARTICLES', Formats.quantity(invoice.articleCount)),
                  if (invoice.discountAmount > 0) ...[
                    _Line('SOUS-TOTAL', Formats.amount(invoice.subtotal)),
                    _Line('REMISE', '-${Formats.amount(invoice.discountAmount)}'),
                  ],
                  const _DoubleRule(),
                  _Line(
                    'TOTAL',
                    Formats.money(invoice.total),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const _DoubleRule(),
                  _Line('PAYÉ', Formats.money(invoice.amountPaid)),
                  if (invoice.remainingAmount > 0) ...[
                    _Line('RESTE À PAYER', Formats.money(invoice.remainingAmount), style: bold),
                    if (invoice.installments.isEmpty && invoice.dueDate != null)
                      _Line('ÉCHÉANCE', Formats.date(invoice.dueDate)),
                  ],
                  _Line('STATUT', invoice.paymentStatus.label.toUpperCase()),
                  if (invoice.installments.isNotEmpty) ...[
                    const _Dashes(),
                    const Text('ÉCHÉANCIER', style: bold),
                    for (final (date, amount) in invoice.installmentRows) _Line(date, amount),
                  ],
                  if (invoice.payments.isNotEmpty) ...[
                    const _Dashes(),
                    const Text('PAIEMENTS', style: bold),
                    for (final (date, amount) in invoice.paymentRows) _Line(date, amount),
                  ],
                  const _Dashes(),
                  for (final line in invoice.thankYouMessage) _Centered(line),
                  if (_barcode.isValid(invoice.number)) ...[
                    const SizedBox(height: Gaps.md),
                    Center(
                      child: SizedBox(
                        width: 240,
                        height: 44,
                        child: CustomPaint(painter: _BarcodePainter(invoice.number)),
                      ),
                    ),
                    const SizedBox(height: 2),
                    _Centered(invoice.number),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final _barcode = Barcode.code128();

class _Centered extends StatelessWidget {
  const _Centered(this.text, {this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(text, style: style, textAlign: TextAlign.center);
}

/// Libellé à gauche, montant à droite.
class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.style});

  final String label;
  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: Text(label, style: style)),
      const SizedBox(width: Gaps.sm),
      Text(value, style: style),
    ],
  );
}

/// Ligne de tirets qui sépare les parties du ticket.
class _Dashes extends StatelessWidget {
  const _Dashes();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: Gaps.sm),
    child: SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(painter: _DashPainter()),
    ),
  );
}

class _DashPainter extends CustomPainter {
  const _DashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.receiptInk
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, 0.5), Offset(x + 4 > size.width ? size.width : x + 4, 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => false;
}

/// Double trait autour du TOTAL.
class _DoubleRule extends StatelessWidget {
  const _DoubleRule();

  @override
  Widget build(BuildContext context) => Container(
    height: 4,
    margin: const EdgeInsets.symmetric(vertical: Gaps.xs),
    decoration: const BoxDecoration(
      border: Border.symmetric(horizontal: BorderSide(color: AppColors.receiptInk)),
    ),
  );
}

/// Code-barres du numéro de facture (Code 128), comme celui du PDF.
class _BarcodePainter extends CustomPainter {
  const _BarcodePainter(this.data);

  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.receiptInk;
    for (final bar in _barcode.make(data, width: size.width, height: size.height).whereType<BarcodeBar>()) {
      if (bar.black) canvas.drawRect(Rect.fromLTWH(bar.left, bar.top, bar.width, bar.height), paint);
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter oldDelegate) => oldDelegate.data != data;
}

/// Bords dentelés en haut et en bas, comme un ticket détaché du rouleau.
class _TornEdges extends CustomClipper<Path> {
  const _TornEdges();

  static const _tooth = 6.0;

  @override
  Path getClip(Size size) {
    final count = (size.width / (_tooth * 2)).floor();
    final step = size.width / count;
    final path = Path()..moveTo(0, _tooth);
    for (var i = 0; i < count; i++) {
      path
        ..lineTo(step * i + step / 2, 0)
        ..lineTo(step * (i + 1), _tooth);
    }
    path.lineTo(size.width, size.height - _tooth);
    for (var i = count; i > 0; i--) {
      path
        ..lineTo(step * i - step / 2, size.height)
        ..lineTo(step * (i - 1), size.height - _tooth);
    }
    return path..close();
  }

  @override
  bool shouldReclip(_TornEdges oldClipper) => false;
}
