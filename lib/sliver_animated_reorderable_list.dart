import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'reordering.dart';

/// Builds the item at [index], which puts [moves] in place.
typedef MovableItemBuilder = Widget Function(
  BuildContext context,
  int index,
  Animation<double> animation,
  ItemMoves moves,
);

/// The ways an item moves, for the item to put in place.
class ItemMoves {
  const ItemMoves._(this._index, this.actions);

  /// For an item that stays where it is.
  static const none = ItemMoves._(null, {});

  final int? _index;

  /// For the item's semantics, where a screen reader reaches them.
  final Map<CustomSemanticsAction, VoidCallback> actions;

  /// Lets [child] be dragged after a long press or with a mouse. Inside a
  /// [Dismissible], a mouse then moves the item rather than sliding it away.
  Widget draggable(Widget child) => switch (_index) {
    null => child,
    final index => ReorderableDelayedDragStartListener(
      index: index,
      child: MouseDragStartListener(
        index: index,
        claimsSwipes: true,
        child: child,
      ),
    ),
  };
}

/// A [SliverAnimatedList] whose items can also be put in another order,
/// once [onReorderItem] is set: dragged with a mouse or after a long press,
/// with Alt+arrows on the keyboard, or from a screen reader.
class SliverAnimatedReorderableList extends StatefulWidget {
  const SliverAnimatedReorderableList({
    super.key,
    required this.itemBuilder,
    this.initialItemCount = 0,
    this.onReorderItem,
  });

  final MovableItemBuilder itemBuilder;
  final int initialItemCount;

  /// Called with an item's index and the one it moves to, both counted
  /// without the items being removed.
  final ReorderCallback? onReorderItem;

  @override
  SliverAnimatedReorderableListState createState() =>
      SliverAnimatedReorderableListState();
}

/// An item on screen, growing in while [controller] runs forward and
/// collapsing once it has a [removedBuilder].
class _Slot {
  _Slot([this.controller]);

  /// Keeps the item's state, and its focus, wherever it moves.
  late final key = GlobalObjectKey(this);
  AnimationController? controller;
  AnimatedRemovedItemBuilder? removedBuilder;
}

class SliverAnimatedReorderableListState
    extends State<SliverAnimatedReorderableList>
    with TickerProviderStateMixin {
  late final _slots = [
    for (var i = 0; i < widget.initialItemCount; i++) _Slot(),
  ];

  /// Each slot's index among the items not being removed.
  late var _indices = _indexed();

  List<int?> _indexed() {
    var index = 0;
    return [
      for (final slot in _slots) slot.removedBuilder == null ? index++ : null,
    ];
  }

  /// Where the item at [index] sits, or the end for one past the last.
  int _slotOf(int index) => switch (_indices.indexOf(index)) {
    -1 => _slots.length,
    final at => at,
  };

  @override
  void dispose() {
    for (final slot in _slots) {
      slot.controller?.dispose();
    }
    super.dispose();
  }

  /// Grows a new item in at [index], as [SliverAnimatedListState.insertItem].
  void insertItem(int index, {required Duration duration}) {
    final controller = duration == Duration.zero
        ? null
        : AnimationController(duration: duration, vsync: this);
    final slot = _Slot(controller);
    setState(() {
      _slots.insert(_slotOf(index), slot);
      _indices = _indexed();
    });
    controller?.forward().then((_) {
      // Unless a removal took it over in the meantime.
      if (slot.removedBuilder != null) return;
      slot.controller = null;
      controller.dispose();
    });
  }

  /// Collapses the item at [index], built by [builder] until it is gone, as
  /// [SliverAnimatedListState.removeItem].
  void removeItem(
    int index,
    AnimatedRemovedItemBuilder builder, {
    required Duration duration,
  }) {
    final slot = _slots[_slotOf(index)];
    if (duration == Duration.zero) {
      slot.controller?.dispose();
      setState(() {
        _slots.remove(slot);
        _indices = _indexed();
      });
      return;
    }
    final controller = slot.controller ??= AnimationController(
      duration: duration,
      value: 1,
      vsync: this,
    );
    setState(() {
      slot.removedBuilder = builder;
      _indices = _indexed();
    });
    controller.reverse().then((_) {
      controller.dispose();
      setState(() {
        _slots.remove(slot);
        _indices = _indexed();
      });
    });
  }

  /// [from] and [to] count every slot, as [SliverReorderableList] does.
  void _reorder(int from, int to) {
    final index = _indices[from];
    if (index == null) return;
    setState(() {
      _slots.insert(to, _slots.removeAt(from));
      _indices = _indexed();
    });
    widget.onReorderItem!(index, _indices[to]!);
  }

  Widget _buildSlot(BuildContext context, int at) {
    final slot = _slots[at];
    final animation = slot.controller?.view ?? kAlwaysCompleteAnimation;
    return KeyedSubtree(
      key: slot.key,
      child: switch (slot.removedBuilder) {
        final builder? => builder(context, animation),
        null when widget.onReorderItem == null => widget.itemBuilder(
          context,
          _indices[at]!,
          animation,
          ItemMoves.none,
        ),
        null => _buildMovable(context, at, animation),
      },
    );
  }

  Widget _buildMovable(
    BuildContext context,
    int at,
    Animation<double> animation,
  ) {
    final up = at > 0 ? () => _reorder(at, at - 1) : null;
    final down = at < _slots.length - 1 ? () => _reorder(at, at + 1) : null;
    final widgets = WidgetsLocalizations.of(context);
    final item = widget.itemBuilder(
      context,
      _indices[at]!,
      animation,
      ItemMoves._(at, {
        CustomSemanticsAction(label: widgets.reorderItemUp): ?up,
        CustomSemanticsAction(label: widgets.reorderItemDown): ?down,
      }),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): ?up,
        const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): ?down,
      },
      child: item,
    );
  }

  @override
  Widget build(BuildContext context) => widget.onReorderItem == null
      ? SliverList(
          delegate: SliverChildBuilderDelegate(
            _buildSlot,
            childCount: _slots.length,
          ),
        )
      : SliverReorderableList(
          itemBuilder: _buildSlot,
          itemCount: _slots.length,
          onReorderItem: _reorder,
          proxyDecorator: liftDragged,
        );
}
