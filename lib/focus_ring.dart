import 'package:flutter/material.dart';

import 'theme.dart';

/// Rings the [InkWell] built by [builder] while it shows keyboard focus, which
/// its own overlay makes too faint to see on the page (WCAG 1.4.11).
class FocusRing extends StatefulWidget {
  const FocusRing({super.key, required this.builder});

  /// Builds the InkWell, which must pass on this `onFocusChange`.
  final Widget Function(ValueChanged<bool> onFocusChange) builder;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  var _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_highlightModeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_highlightModeChanged);
    super.dispose();
  }

  void _highlightModeChanged(FocusHighlightMode _) => setState(() {});

  @override
  Widget build(BuildContext context) {
    // As the InkWell decides to show its overlay: not after a touch.
    final shown =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: ShapeDecoration(
        shape: RoundedRectangleBorder(
          borderRadius: paperRadius,
          side: shown
              ? BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : BorderSide.none,
        ),
      ),
      child: widget.builder((focused) => setState(() => _focused = focused)),
    );
  }
}
