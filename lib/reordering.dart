import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// Starts moving an item dragged with a mouse once it has gone as far as a
/// finger would, so that a click that wobbles still opens it. Touch keeps the
/// long press, which leaves a swipe to scroll.
class MouseDragStartListener extends ReorderableDragStartListener {
  const MouseDragStartListener({
    super.key,
    required super.index,
    required super.child,
    this.claimsSwipes = false,
  });

  /// Whether it takes the mouse from a [Dismissible] around it, which slides
  /// away after a single pixel across.
  final bool claimsSwipes;

  @override
  MultiDragGestureRecognizer createRecognizer() =>
      _MouseDragRecognizer(claimsSwipes, debugOwner: this);
}

/// Lifts the item being moved off the page.
Widget liftDragged(Widget child, int index, Animation<double> animation) =>
    AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: paperRadius,
        elevation: Curves.easeOut.transform(animation.value) * 4,
        child: child,
      ),
      child: child,
    );

class _MouseDragRecognizer extends MultiDragGestureRecognizer {
  _MouseDragRecognizer(this.claimsSwipes, {super.debugOwner})
    : super(supportedDevices: {PointerDeviceKind.mouse});

  final bool claimsSwipes;

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      _MouseDragState(
        claimsSwipes,
        event.position,
        event.kind,
        gestureSettings,
      );

  @override
  String get debugDescription => 'mouse drag';
}

class _MouseDragState extends MultiDragPointerState {
  _MouseDragState(
    this.claimsSwipes,
    super.initialPosition,
    super.kind,
    super.gestureSettings,
  );

  final bool claimsSwipes;

  /// Kept while the pointer is claimed but has not gone far enough.
  GestureMultiDragStartCallback? _starter;

  bool get _farEnough => pendingDelta!.distance > kTouchSlop;

  @override
  void checkForResolutionAfterMove() {
    if (_starter case final starter? when _farEnough) {
      starter(initialPosition);
    } else if (_starter == null &&
        (_farEnough ||
            claimsSwipes && pendingDelta!.dx.abs() > kPrecisePointerHitSlop)) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    if (_farEnough) {
      starter(initialPosition);
    } else {
      _starter = starter;
    }
  }
}
