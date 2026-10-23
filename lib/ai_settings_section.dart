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

class AiSettingsSection extends StatefulWidget {
  const AiSettingsSection({super.key, required this.tidier});

  final Tidier tidier;

  @override
  State<AiSettingsSection> createState() => _AiSettingsSectionState();
}

class _AiSettingsSectionState extends State<AiSettingsSection> {
  /// What the fields were filled from, so a backup restored below them
  /// fills them again.
  late var _shown = widget.tidier.settings;
  late final _address = TextEditingController(text: _shown?.baseUrl);
  late final _key = TextEditingController(text: _shown?.apiKey);
  late final _model = TextEditingController(text: _shown?.model);
  final _modelFocus = FocusNode();
  var _keyHidden = true;
  var _addressTouched = false;
  Future<List<String>>? _models;
  String? _modelsFor;

  @override
  void initState() {
    super.initState();
    widget.tidier.addListener(_tidierChanged);
  }

  @override
  void dispose() {
    widget.tidier.removeListener(_tidierChanged);
    _modelFocus.dispose();
    _model.dispose();
    _key.dispose();
    _address.dispose();
    super.dispose();
  }

  void _tidierChanged() {
    final settings = widget.tidier.settings;
    if (identical(settings, _shown)) return;
    setState(() {
      _shown = settings;
      _address.text = settings?.baseUrl ?? '';
      _key.text = settings?.apiKey ?? '';
      _model.text = settings?.model ?? '';
      _addressTouched = false;
    });
  }

  bool get _addressValid {
    final uri = Uri.tryParse(_address.text.trim());
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  bool get _changed {
    final draft = _draft;
    final saved = widget.tidier.settings;
    return saved == null ||
        draft.baseUrl != saved.baseUrl ||
        draft.apiKey != saved.apiKey ||
        draft.model != saved.model;
  }

  bool get _canSave =>
      _addressValid && _model.text.trim().isNotEmpty && _changed;

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
    // Keeps the fields as typed rather than filling them again.
    _shown = _draft;
    widget.tidier.configure(_shown);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final address = _address.text.trim();

    return Column(
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
            errorText: _addressTouched && address.isNotEmpty && !_addressValid
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
          onChanged: (_) => setState(() {}),
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
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: _canSave ? _save : null,
              child: Text(l10n.save),
            ),
            if (widget.tidier.settings != null)
              TextButton(
                onPressed: () => widget.tidier.configure(null),
                child: Text(l10n.turnOff),
              ),
          ],
        ),
      ],
    );
  }
}
