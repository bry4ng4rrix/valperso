import 'package:flutter/material.dart';

import '../../core/utils/debouncer.dart';

/// Champ de recherche. La requête n'est envoyée qu'après une courte pause de frappe.
class AppSearchField extends StatefulWidget {
  const AppSearchField({super.key, required this.hint, required this.onChanged, this.initialValue});

  final String hint;
  final ValueChanged<String> onChanged;
  final String? initialValue;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late final _controller = TextEditingController(text: widget.initialValue);
  final _debouncer = Debouncer();

  @override
  void dispose() {
    _debouncer.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    setState(() {}); // affiche / masque le bouton d'effacement
    _debouncer.run(() => widget.onChanged(value.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: _changed,
      textInputAction: TextInputAction.search,
      onSubmitted: (value) => widget.onChanged(value.trim()),
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Effacer',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _controller.clear();
                  _changed('');
                },
              ),
      ),
    );
  }
}
