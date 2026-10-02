import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/colors.dart';
import '../../app/theme/dimensions.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_config.dart';
import '../../core/auth/settings_controller.dart';
import '../../core/widgets/notifications.dart';
import '../../core/widgets/app_dialog.dart';

/// Modifier l'adresse du serveur. L'adresse est testée avant d'être enregistrée.
Future<void> showApiUrlDialog(BuildContext context) {
  return showDialog<void>(context: context, builder: (_) => const _ApiUrlDialog());
}

class _ApiUrlDialog extends StatefulWidget {
  const _ApiUrlDialog();

  @override
  State<_ApiUrlDialog> createState() => _ApiUrlDialogState();
}

class _ApiUrlDialogState extends State<_ApiUrlDialog> {
  late final TextEditingController _controller = TextEditingController(text: context.read<SettingsController>().apiUrl);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save({required bool force}) async {
    final url = _controller.text.trim();
    if (url.isEmpty) return setState(() => _error = 'Saisissez l\'adresse du serveur.');
    setState(() {
      _busy = true;
      _error = null;
    });
    final reachable = force || await context.read<ApiClient>().ping(url);
    if (!mounted) return;
    if (!reachable) {
      return setState(() {
        _busy = false;
        _error = 'Le serveur ne répond pas à cette adresse.';
      });
    }
    await context.read<SettingsController>().setApiUrl(url);
    if (!mounted) return;
    Navigator.of(context).pop();
    Notify.success(context, 'Adresse du serveur enregistrée.');
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Adresse du serveur',
      size: DialogSize.small,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Adresse de l\'API',
              hintText: 'http://192.168.1.10:8001',
              errorText: _error,
              prefixIcon: const Icon(Icons.dns_outlined, size: 20),
            ),
          ),
          const SizedBox(height: Gaps.sm),
          Text(
            'Émulateur Android : http://10.0.2.2:8001 — Téléphone : adresse IP de l\'ordinateur sur le réseau local.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          TextButton(
            onPressed: _busy ? null : () => _controller.text = ApiConfig.defaultBaseUrl,
            child: const Text('Utiliser l\'adresse par défaut'),
          ),
        ],
      ),
      actions: [
        OutlinedButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Annuler')),
        if (_error != null)
          TextButton(
            onPressed: _busy ? null : () => _save(force: true),
            child: const Text('Enregistrer quand même', style: TextStyle(color: AppColors.warning)),
          ),
        FilledButton(
          onPressed: _busy ? null : () => _save(force: false),
          child: _busy
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Tester et enregistrer'),
        ),
      ],
    );
  }
}
