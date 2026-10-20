import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/focus_ring.dart';

void main() {
  testWidgets('rings its InkWell while the keyboard has it focused', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FocusRing(
            builder: (onFocusChange) => InkWell(
              onTap: () {},
              onFocusChange: onFocusChange,
              child: const SizedBox(width: 200, height: 40),
            ),
          ),
        ),
      ),
    );
    BorderSide ring() {
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(FocusRing),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final shape = (box.decoration as ShapeDecoration).shape;
      return (shape as RoundedRectangleBorder).side;
    }

    expect(ring(), BorderSide.none);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(ring().width, 2);

    // A touch hides it, as it does the InkWell's own focus overlay.
    await tester.tapAt(const Offset(400, 400));
    await tester.pump();
    expect(ring(), BorderSide.none);
  });
}
