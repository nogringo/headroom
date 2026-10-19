import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'theme.dart';
import 'tidier.dart';
import 'tidy_client.dart';

/// Shortcuts to the address of well-known services. Any other works too.
const _services = {
  'OpenAI': 'https://api.openai.com/v1',
  'Claude': 'https://api.anthropic.com/v1',
  'Gemini': 'https://generativelanguage.googleapis.com/v1beta/openai',
  'Mistral': 'https://api.mistral.ai/v1',
  'DeepSeek': 'https://api.deepseek.com',
  'OpenRouter': 'https://openrouter.ai/api/v1',
  // Z.ai refuses calls from a browser (no CORS).
  if (!kIsWeb) 'Z.ai': 'https://api.z.ai/api/paas/v4',
  'Ollama': 'http://localhost:11434/v1',
};

class AiSettingsDialog extends StatefulWidget {
  const AiSettingsDialog({super.key, required this.tidier});

  final Tidier tidier;

  @override
  State<AiSettingsDialog> createState() => _AiSettingsDialogState();
}

class _AiSettingsDialogState extends State<AiSettingsDialog> {
  late final _initial = widget.tidier.settings;
  late final _address = TextEditingController(text: _initial?.baseUrl);
  late final _key = TextEditingController(text: _initial?.apiKey);
  late final _model = TextEditingController(text: _initial?.model);
  final _modelFocus = FocusNode();
  var _keyHidden = true;
  var _addressTouched = false;
  Future<List<String>>? _models;
  String? _modelsFor;

  @override
  void dispose() {
    _modelFocus.dispose();
    _model.dispose();
    _key.dispose();
    _address.dispose();
    super.dispose();
  }

  bool get _addressValid {
    final uri = Uri.tryParse(_address.text.trim());
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  bool get _canSave => _addressValid && _model.text.trim().isNotEmpty;

  AiSettings get _draft => AiSettings(
    baseUrl: _address.text.trim(),
    apiKey: _key.text.trim(),
    model: _model.text.trim(),
  );

  /// Fetched once per address and key.
  Future<List<String>> _modelList() {
    final draft = _draft;
    final asked = '${draft.baseUrl}\n${draft.apiKey}';
    if (asked != _modelsFor) {
      _modelsFor = asked;
      _models = _fetchModels(draft);
    }
    return _models!;
  }

  Future<List<String>> _fetchModels(AiSettings draft) async {
    try {
      return await widget.tidier.models(draft);
    } on TidyException {
      // Typing the model's name works without the list.
      return const [];
    }
  }

  void _save() {
    if (!_canSave) return;
    widget.tidier.configure(_draft);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = Theme.of(context);
    // Settings are the app's own words, not handwritten like thoughts.
    final theme = appTheme.copyWith(
      textTheme: appTheme.textTheme.copyWith(
        bodyLarge: appTheme.textTheme.bodyMedium?.copyWith(fontSize: 16),
      ),
    );
    final l10n = AppLocalizations.of(context);
    final address = _address.text.trim();

    return Theme(data: theme, child: _buildDialog(theme, l10n, address));
  }

  Widget _buildDialog(ThemeData theme, AppLocalizations l10n, String address) {
    return AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: paperRadius),
      title: Text(l10n.tidySettings),
      scrollable: true,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.tidyIntro, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final MapEntry(key: name, value: url) in _services.entries)
                  ChoiceChip(
                    label: Text(name),
                    selected: address == url,
                    onSelected: (_) => setState(() {
                      _address.text = url;
                      _model.clear();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _address,
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: (_) => setState(() => _addressTouched = true),
              decoration: InputDecoration(
                labelText: l10n.tidyAddress,
                hintText: _services['OpenAI'],
                errorText:
                    _addressTouched && address.isNotEmpty && !_addressValid
                    ? l10n.tidyAddressInvalid
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _key,
              obscureText: _keyHidden,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: l10n.tidyKey,
                helperText: l10n.tidyKeyHelp,
                suffixIcon: IconButton(
                  tooltip: _keyHidden ? l10n.showKey : l10n.hideKey,
                  onPressed: () => setState(() => _keyHidden = !_keyHidden),
                  icon: Icon(
                    _keyHidden
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            RawAutocomplete<String>(
              textEditingController: _model,
              focusNode: _modelFocus,
              optionsBuilder: (value) async {
                if (!_addressValid) return const [];
                final query = value.text.trim().toLowerCase();
                return [
                  for (final model in await _modelList())
                    if (model.toLowerCase().contains(query)) model,
                ];
              },
              fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
                  TextField(
                    controller: controller,
                    focusNode: focusNode,
                    autocorrect: false,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => onSubmitted(),
                    decoration: InputDecoration(labelText: l10n.tidyModel),
                  ),
              optionsViewBuilder: (context, onSelected, options) => Align(
                alignment: AlignmentDirectional.topStart,
                child: Material(
                  elevation: 4,
                  borderRadius: paperRadius,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 240,
                      maxWidth: 360,
                    ),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shrinkWrap: true,
                      children: [
                        for (final option in options)
                          ListTile(
                            dense: true,
                            title: Text(option),
                            onTap: () => onSelected(option),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              onSelected: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text(l10n.tidyPrivacy, style: theme.textTheme.bodySmall),
            // In the content, as a narrow dialog would stack three actions.
            if (_initial != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () {
                    widget.tidier.configure(null);
                    Navigator.pop(context);
                  },
                  child: Text(l10n.turnOff),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _canSave ? _save : null,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
