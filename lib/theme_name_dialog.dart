import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'theme.dart';
import 'theme_names.dart';

/// Asks for a new theme's name, or for [renaming]'s new one. Pops the name
/// as the theme of [themes] it matches is spelled, when one does.
class ThemeNameDialog extends StatefulWidget {
  const ThemeNameDialog({super.key, required this.themes, this.renaming});

  final Iterable<String> themes;

  /// Null for a new theme.
  final String? renaming;

  @override
  State<ThemeNameDialog> createState() => _ThemeNameDialogState();
}

class _ThemeNameDialogState extends State<ThemeNameDialog> {
  late final _name = TextEditingController(text: widget.renaming)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.renaming?.length ?? 0,
    );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? _existing(String name) => themeSpelled(
    name,
    widget.themes.where((theme) => theme != widget.renaming),
  );

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, _existing(name) ?? name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final renaming = widget.renaming != null;
    return AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: paperRadius),
      title: Text(renaming ? l10n.renameTheme : l10n.newTheme),
      content: ValueListenableBuilder(
        valueListenable: _name,
        builder: (context, value, _) {
          final existing = renaming ? _existing(value.text) : null;
          return TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: l10n.themeName,
              helperText: existing == null ? null : l10n.themesJoin(existing),
              helperMaxLines: 2,
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ValueListenableBuilder(
          valueListenable: _name,
          builder: (context, value, _) => FilledButton(
            onPressed: value.text.trim().isEmpty ? null : _submit,
            child: Text(renaming ? l10n.rename : l10n.create),
          ),
        ),
      ],
    );
  }
}
