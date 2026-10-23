import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'context_menu.dart';
import 'focus_ring.dart';
import 'l10n/app_localizations.dart';
import 'reordering.dart';
import 'theme.dart';

/// Opens every thought or a single theme's, which it can rename, move and
/// delete, with the AI's clean-up and the settings below.
class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.themes,
    required this.selected,
    required this.onSelect,
    required this.onRename,
    required this.onDelete,
    required this.onReorder,
    required this.cleaning,
    required this.onCleanUp,
    required this.onSettings,
  });

  /// In the person's order, then '' for the thoughts without one.
  final List<String> themes;

  /// Null for every thought.
  final String? selected;
  final ValueChanged<String?> onSelect;
  final ValueChanged<String> onRename;
  final ValueChanged<String> onDelete;

  /// Called with every named theme, in their new order.
  final ValueChanged<List<String>> onReorder;
  final bool cleaning;

  /// Null hides the clean-up, while no AI is set up.
  final VoidCallback? onCleanUp;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final named = [
      for (final theme in themes)
        if (theme.isNotEmpty) theme,
    ];

    /// [to] counts the themes once the one at [from] is taken out.
    void move(int from, int to) {
      final order = [...named];
      order.insert(to, order.removeAt(from));
      onReorder(order);
    }

    Widget entry(
      String? theme,
      String label, {
      Map<CustomSemanticsAction, VoidCallback> actions = const {},
    }) => _Entry(
      label: label,
      selected: theme == selected,
      onTap: () => onSelect(theme),
      actions: actions,
      trailing: theme == selected && theme != null && theme.isNotEmpty
          ? IconButton(
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
              iconSize: 18,
              color: scheme.onSurfaceVariant,
              tooltip: l10n.renameTheme,
              onPressed: () => onRename(theme),
              icon: const Icon(Icons.edit_outlined),
            )
          : null,
    );

    Widget movable(int index, String theme) {
      final widgets = WidgetsLocalizations.of(context);
      final up = index > 0 ? () => move(index, index - 1) : null;
      final down = index < named.length - 1
          ? () => move(index, index + 1)
          : null;
      return ReorderableDelayedDragStartListener(
        key: ValueKey(theme),
        index: index,
        child: MouseDragStartListener(
          index: index,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): ?up,
              const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
                  ?down,
            },
            child: ContextMenu<Never>(
              menuChildren: (_, focusFirst) => [
                MenuItemButton(
                  autofocus: focusFirst,
                  leadingIcon: const Icon(Icons.edit_outlined),
                  onPressed: () => onRename(theme),
                  child: Text(l10n.renameTheme),
                ),
                if (up != null || down != null) ...[
                  const Divider(),
                  ...moveMenuItems(context, up: up, down: down),
                ],
                const Divider(),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => onDelete(theme),
                  child: Text(l10n.deleteTheme),
                ),
              ],
              builder: (_) => entry(
                theme,
                theme,
                actions: {
                  CustomSemanticsAction(label: l10n.renameTheme): () =>
                      onRename(theme),
                  CustomSemanticsAction(label: widgets.reorderItemUp): ?up,
                  CustomSemanticsAction(label: widgets.reorderItemDown): ?down,
                  CustomSemanticsAction(label: l10n.deleteTheme): () =>
                      onDelete(theme),
                },
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ReorderableListView(
            padding: const EdgeInsets.all(12),
            buildDefaultDragHandles: false,
            header: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: entry(null, l10n.allThoughts),
            ),
            footer: themes.contains('') ? entry('', l10n.noTheme) : null,
            onReorderItem: move,
            proxyDecorator: liftDragged,
            children: [
              for (final (index, theme) in named.indexed) movable(index, theme),
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
          child: switch (onCleanUp) {
            final onCleanUp? => Row(
              children: [
                Expanded(
                  child: _Entry(
                    leading: cleaning
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_fix_high_outlined),
                    label: cleaning ? l10n.cleaningUp : l10n.cleanUpAction,
                    onTap: cleaning ? null : onCleanUp,
                  ),
                ),
                IconButton(
                  color: scheme.onSurfaceVariant,
                  tooltip: l10n.settings,
                  onPressed: onSettings,
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
            null => _Entry(
              leading: const Icon(Icons.settings_outlined),
              label: l10n.settings,
              onTap: onSettings,
            ),
          },
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
    this.actions = const {},
  });

  final String label;

  /// Null while it has nothing to do.
  final VoidCallback? onTap;
  final bool selected;
  final Widget? leading;
  final Widget? trailing;

  /// For a screen reader.
  final Map<CustomSemanticsAction, VoidCallback> actions;

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
              customSemanticsActions: actions,
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
