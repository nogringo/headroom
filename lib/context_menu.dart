import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Opens a menu where its child is right-clicked, or below it with the menu
/// key or Shift+F10. It goes around any [Semantics] of the child, which its
/// overlay would otherwise part from the child's label.
class ContextMenu<T> extends StatefulWidget {
  const ContextMenu({
    super.key,
    required this.menuChildren,
    required this.builder,
  });

  /// Builds the items for the target a part of the child opened the menu
  /// for, null for the child as a whole. The first item takes `focusFirst`
  /// as its `autofocus`, set when the keyboard opened the menu, so the arrow
  /// keys go through it.
  final List<Widget> Function(T? target, bool focusFirst) menuChildren;

  /// Builds the child, whose parts can open the menu with `open` at a global
  /// position, for a target of their own.
  final Widget Function(void Function(Offset position, T target) open) builder;

  @override
  State<ContextMenu<T>> createState() => _ContextMenuState<T>();
}

class _ContextMenuState<T> extends State<ContextMenu<T>> {
  final _menu = MenuController();
  T? _target;
  var _focusFirst = false;

  /// At a global [position], else below the child for the keyboard.
  void _open({Offset? position, T? target}) {
    final box = context.findRenderObject()! as RenderBox;
    setState(() {
      _target = target;
      _focusFirst = position == null;
    });
    _menu.open(position: position == null ? null : box.globalToLocal(position));
  }

  @override
  Widget build(BuildContext context) => MenuAnchor(
    controller: _menu,
    menuChildren: widget.menuChildren(_target, _focusFirst),
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.contextMenu): _open,
        const SingleActivator(LogicalKeyboardKey.f10, shift: true): _open,
      },
      child: GestureDetector(
        excludeFromSemantics: true,
        onSecondaryTapUp: (details) => _open(position: details.globalPosition),
        child: widget.builder(
          (position, target) => _open(position: position, target: target),
        ),
      ),
    ),
  );
}

/// Moves an item one place up or down, as Alt+arrows do. Null where it
/// cannot go.
List<Widget> moveMenuItems(
  BuildContext context, {
  required VoidCallback? up,
  required VoidCallback? down,
}) {
  final widgets = WidgetsLocalizations.of(context);
  return [
    MenuItemButton(
      leadingIcon: const Icon(Icons.arrow_upward_rounded),
      shortcut: const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true),
      onPressed: up,
      child: Text(widgets.reorderItemUp),
    ),
    MenuItemButton(
      leadingIcon: const Icon(Icons.arrow_downward_rounded),
      shortcut: const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true),
      onPressed: down,
      child: Text(widgets.reorderItemDown),
    ),
  ];
}
