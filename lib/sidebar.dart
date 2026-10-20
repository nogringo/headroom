import 'package:flutter/material.dart';

import 'focus_ring.dart';
import 'l10n/app_localizations.dart';
import 'theme.dart';
import 'theme_names.dart';

/// Opens every thought or a single theme's, which it can rename, with the
/// backup and the AI's settings below.
class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.themes,
    required this.selected,
    required this.onSelect,
    required this.onRename,
    required this.onBackup,
    required this.tidying,
    required this.onTidySettings,
  });

  /// Listed alphabetically, then '' for the thoughts without one.
  final Set<String> themes;

  /// Null for every thought.
  final String? selected;
  final ValueChanged<String?> onSelect;
  final ValueChanged<String> onRename;
  final VoidCallback onBackup;
  final bool tidying;
  final VoidCallback onTidySettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final named = sortedThemes(themes.where((theme) => theme.isNotEmpty));

    Widget entry(String? theme, String label) => _Entry(
      label: label,
      selected: theme == selected,
      onTap: () => onSelect(theme),
      trailing: theme == selected && theme != null && theme.isNotEmpty
          ? IconButton(
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
              iconSize: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              tooltip: l10n.renameTheme,
              onPressed: () => onRename(theme),
              icon: const Icon(Icons.edit_outlined),
            )
          : null,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Entry(
                leading: const Icon(Icons.backup_outlined),
                label: l10n.backup,
                onTap: onBackup,
              ),
              _Entry(
                leading: tidying
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cleaning_services_outlined),
                label: tidying ? l10n.tidying : l10n.tidySettings,
                onTap: onTidySettings,
              ),
            ],
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
    this.trailing,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // The other themes stay quiet beside the one open.
    final color = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    final leading = this.leading;
    final trailing = this.trailing;
    return Material(
      color: selected ? scheme.outlineVariant : Colors.transparent,
      borderRadius: paperRadius,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              child: FocusRing(
                builder: (onFocusChange) => InkWell(
                  borderRadius: paperRadius,
                  onTap: onTap,
                  onFocusChange: onFocusChange,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
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
            ),
          ),
          if (trailing != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 2),
              child: trailing,
            ),
        ],
      ),
    );
  }
}
