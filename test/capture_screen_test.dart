import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/main.dart';
import 'package:headroom/thought.dart';
import 'package:headroom/thought_store.dart';

import 'in_memory_storage.dart';

void main() {
  late InMemoryStorage storage;
  late ThoughtStore store;

  Future<void> pumpApp(
    WidgetTester tester, [
    List<Thought> initial = const [],
  ]) async {
    storage = InMemoryStorage(initial);
    store = ThoughtStore(storage);
    await store.load();
    await tester.pumpWidget(HeadroomApp(store: store));
    await tester.pumpAndSettle();
  }

  TextField captureField(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField));

  testWidgets('opens with the field focused and an empty list', (tester) async {
    await pumpApp(tester);

    expect(captureField(tester).focusNode!.hasFocus, isTrue);
    expect(find.text("What's on your mind?"), findsOneWidget);
    expect(find.text('What you note shows up here.'), findsOneWidget);
  });

  testWidgets('sending captures the thought and keeps the field ready', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.enterText(find.byType(TextField), 'Call the garage');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    await store.flush();

    expect(find.text('Call the garage'), findsOneWidget);
    expect(find.text('just now'), findsOneWidget);
    expect(captureField(tester).controller!.text, isEmpty);
    expect(captureField(tester).focusNode!.hasFocus, isTrue);
    expect(storage.saved.single.text, 'Call the garage');
  });

  testWidgets('the send button is disabled until there is text', (
    tester,
  ) async {
    await pumpApp(tester);
    IconButton button() => tester.widget<IconButton>(find.byType(IconButton));

    expect(button().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Buy bread');
    await tester.pump();
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(find.text('Buy bread'), findsOneWidget);
    expect(button().onPressed, isNull);
  });

  testWidgets('swiping deletes a thought and undo brings it back', (
    tester,
  ) async {
    await pumpApp(tester, [
      Thought(id: '1', text: 'Buy bread', createdAt: DateTime.now()),
    ]);

    await tester.drag(find.text('Buy bread'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Buy bread'), findsNothing);
    expect(store.thoughts, isEmpty);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Buy bread'), findsOneWidget);
    expect(store.thoughts.single.id, '1');
  });

  testWidgets('tapping a thought edits it', (tester) async {
    await pumpApp(tester, [
      Thought(id: '1', text: 'Buy bred', createdAt: DateTime.now()),
    ]);

    await tester.tap(find.text('Buy bred'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Buy bread');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Buy bread'), findsOneWidget);
    expect(store.thoughts.single.text, 'Buy bread');
  });

  testWidgets('follows a French device locale', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('fr', 'FR')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await pumpApp(tester);

    expect(find.text("Qu'est-ce que tu as en tête ?"), findsOneWidget);
    expect(find.text("Ce que tu notes s'affiche ici."), findsOneWidget);
  });
}
