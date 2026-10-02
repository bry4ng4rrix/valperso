import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/dimensions.dart';
import '../../core/widgets/notifications.dart';
import '../../shared/utils/api_form.dart';
import '../../shared/utils/validators.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/list_page.dart';
import 'customers_repository.dart';

/// Nouveau client. Le téléphone devient obligatoire pour une vente avec avance ou à crédit.
class CustomerFormScreen extends StatefulWidget {
  const CustomerFormScreen({super.key});

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> with ApiFormState {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final customer = await submitToApi(
      () => context.read<CustomersRepository>().create(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        phone: trimOrNull(_phone.text),
      ),
    );
    if (customer == null || !mounted) return;
    Notify.success(context, 'Client ${customer.fullName} créé.');
    context.pushReplacement('/customers/${customer.id}');
  }

  @override
  Widget build(BuildContext context) {
    return DetailPage(
      title: 'Nouveau client',
      maxWidth: Sizes.formMaxWidth,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(Gaps.lg),
          children: [
            SectionCard(
              title: 'Coordonnées',
              icon: Icons.person_outline,
              child: Column(
                children: [
                  AppTextField(
                    label: 'Prénom',
                    controller: _firstName,
                    required: true,
                    errorText: errorFor('first_name'),
                    validator: Validators.text(required: true, max: 100),
                  ),
                  const SizedBox(height: Gaps.md),
                  AppTextField(
                    label: 'Nom',
                    controller: _lastName,
                    required: true,
                    errorText: errorFor('last_name'),
                    validator: Validators.text(required: true, max: 100),
                  ),
                  const SizedBox(height: Gaps.md),
                  AppTextField(
                    label: 'Téléphone',
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    prefixIcon: Icons.phone_outlined,
                    errorText: errorFor('phone'),
                    validator: Validators.phone,
                    helper: 'Obligatoire pour une vente avec avance ou à crédit.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: Gaps.xl),
            AppButton(label: 'Créer le client', icon: Icons.check, expand: true, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
