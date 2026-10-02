import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/api/api_exception.dart';
import '../../core/auth/session_controller.dart';
import '../../core/auth/settings_controller.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';
import '../settings/api_url_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      await context.read<SessionController>().login(_identifier.text, _password.text);
      // Le routeur affiche l'accueil dès que la session est ouverte.
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = context.watch<SessionController>();
    final apiUrl = context.watch<SettingsController>().apiUrl;
    final notice = session.expiredMessage;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Gaps.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(Radii.lg),
                          ),
                          child: Icon(Icons.storefront, color: theme.colorScheme.onPrimary, size: 36),
                        ),
                      ),
                      const SizedBox(height: Gaps.lg),
                      Text(AppInfo.name, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                      const SizedBox(height: Gaps.xs),
                      Text(
                        'Connectez-vous pour continuer',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: Gaps.xl),
                      if (notice != null && _error == null) ...[
                        _Banner(message: notice, color: AppColors.warning, icon: Icons.info_outline),
                        const SizedBox(height: Gaps.lg),
                      ],
                      if (_error != null) ...[
                        _Banner(message: _error!, color: AppColors.danger, icon: Icons.error_outline),
                        const SizedBox(height: Gaps.lg),
                      ],
                      AppTextField(
                        label: 'Nom d\'utilisateur ou email',
                        controller: _identifier,
                        prefixIcon: Icons.person_outline,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        required: true,
                      ),
                      const SizedBox(height: Gaps.lg),
                      AppTextField(
                        label: 'Mot de passe',
                        controller: _password,
                        prefixIcon: Icons.lock_outline,
                        obscureText: _hidePassword,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        required: true,
                        suffix: IconButton(
                          tooltip: _hidePassword ? 'Afficher le mot de passe' : 'Masquer le mot de passe',
                          onPressed: () => setState(() => _hidePassword = !_hidePassword),
                          icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        ),
                      ),
                      const SizedBox(height: Gaps.xl),
                      AppButton(
                        label: 'Se connecter',
                        loadingLabel: 'Connexion...',
                        icon: Icons.login,
                        expand: true,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: Gaps.xl),
                      TextButton.icon(
                        onPressed: () => showApiUrlDialog(context),
                        icon: const Icon(Icons.dns_outlined, size: 18),
                        label: Text('Serveur : $apiUrl', overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.color, required this.icon});

  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Gaps.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: Gaps.sm),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
