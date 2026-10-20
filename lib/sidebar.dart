import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'theme.dart';

/// Opens every thought or a single theme's, with the AI's settings below.
class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.themes,
    required this.selected,
    required this.onSelect,
    required this.tidying,
    required this.onTidySettings,
  });

  /// Listed alphabetically, then '' for the thoughts without one.
  final Set<String> themes;

  /// Null for every thought.
  final String? selected;
  final ValueChanged<String?> onSelect;
  final bool tidying;
  final VoidCallback onTidySettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final named = [
      for (final theme in themes)
        if (theme.isNotEmpty) theme,
    ]..sort((a, b) => _plain(a).compareTo(_plain(b)));

    Widget entry(String? theme, String label) => _Entry(
      label: label,
      selected: theme == selected,
      onTap: () => onSelect(theme),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              entry(null, l10n.allThoughts),
              const SizedBox(height: 12),
              for (final theme in named) entry(theme, theme),
              if (themes.contains('')) entry('', l10n.noTheme),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            0,
            12,
            12 + MediaQuery.paddingOf(context).bottom,
          ),
          child: _Entry(
            leading: tidying
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cleaning_services_outlined),
            label: tidying ? l10n.tidying : l10n.tidySettings,
            onTap: onTidySettings,
          ),
        ),
      ],
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.label,
    required this.onTap,
    this.selected = false,
    this.leading,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // The other themes stay quiet beside the one open.
    final color = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    final leading = this.leading;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? scheme.outlineVariant : Colors.transparent,
        borderRadius: paperRadius,
        child: InkWell(
          borderRadius: paperRadius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                if (leading != null) ...[
                  IconTheme.merge(
                    data: IconThemeData(color: color, size: 18),
                    child: leading,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: color,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _accented = 'àáâäãåçèéêëìíîïñòóôöõùúûüýÿ';
const _bare = 'aaaaaaceeeeiiiinooooouuuuyy';

/// Lowercase without accents, so "Études" sorts among the E.
String _plain(String theme) => [
  for (final char in theme.toLowerCase().split(''))
    switch (_accented.indexOf(char)) {
      -1 => char,
      final i => _bare[i],
    },
].join();
