import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'focus_ring.dart';
import 'l10n/app_localizations.dart';
import 'theme.dart';

/// Opens every thought or a single theme's, which it can rename and move,
/// with the backup and the AI's settings below.
class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.themes,
    required this.selected,
    required this.onSelect,
    required this.onRename,
    required this.onReorder,
    required this.onBackup,
    required this.tidying,
    required this.onTidySettings,
  });

  /// In the person's order, then '' for the thoughts without one.
  final List<String> themes;

  /// Null for every thought.
  final String? selected;
  final ValueChanged<String?> onSelect;
  final ValueChanged<String> onRename;

  /// Called with every named theme, in their new order.
  final ValueChanged<List<String>> onReorder;
  final VoidCallback onBackup;
  final bool tidying;
  final VoidCallback onTidySettings;

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
        child: _MouseDragStartListener(
          index: index,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): ?up,
              const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
                  ?down,
            },
            child: entry(
              theme,
              theme,
              actions: {
                CustomSemanticsAction(label: widgets.reorderItemUp): ?up,
                CustomSemanticsAction(label: widgets.reorderItemDown): ?down,
              },
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
            proxyDecorator: (child, _, animation) => AnimatedBuilder(
              animation: animation,
              builder: (context, child) => Material(
                color: scheme.surface,
                borderRadius: paperRadius,
                elevation: Curves.easeOut.transform(animation.value) * 4,
                child: child,
              ),
              child: child,
            ),
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
    this.actions = const {},
  });

  final String label;
  final VoidCallback onTap;
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

/// Starts moving a theme dragged with a mouse once it has gone as far as a
/// finger would, so that a click that wobbles still opens the theme. Touch
/// keeps the long press, which leaves a swipe to scroll.
class _MouseDragStartListener extends ReorderableDragStartListener {
  const _MouseDragStartListener({required super.index, required super.child});

  @override
  MultiDragGestureRecognizer createRecognizer() =>
      _MouseDragRecognizer(debugOwner: this);
}

class _MouseDragRecognizer extends MultiDragGestureRecognizer {
  _MouseDragRecognizer({super.debugOwner})
    : super(supportedDevices: {PointerDeviceKind.mouse});

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      _MouseDragState(event.position, event.kind, gestureSettings);

  @override
  String get debugDescription => 'mouse drag';
}

class _MouseDragState extends MultiDragPointerState {
  _MouseDragState(super.initialPosition, super.kind, super.gestureSettings);

  @override
  void checkForResolutionAfterMove() {
    if (pendingDelta!.distance > kTouchSlop) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) =>
      starter(initialPosition);
}
