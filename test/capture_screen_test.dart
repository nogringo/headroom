import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/main.dart';
import 'package:headroom/thought.dart';
import 'package:headroom/thought_store.dart';

import 'in_memory_storage.dart';

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

void main() {
  late InMemoryStorage storage;
  late ThoughtStore store;
  Uint8List? clipboardImage;
  String? clipboardText;

  Future<void> pumpApp(
    WidgetTester tester, [
    List<Thought> initial = const [],
    Map<String, Uint8List> images = const {},
  ]) async {
    clipboardImage = null;
    clipboardText = null;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('pasteboard'),
      (call) async => call.method == 'image' ? clipboardImage : null,
    );
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => switch (call.method) {
        'Clipboard.hasStrings' => {'value': clipboardText != null},
        'Clipboard.getData' when clipboardText != null => {
          'text': clipboardText,
        },
        _ => null,
      },
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(
        const MethodChannel('pasteboard'),
        null,
      );
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    storage = InMemoryStorage(initial)..images.addAll(images);
    store = ThoughtStore(storage);
    await store.load();
    await tester.pumpWidget(HeadroomApp(store: store));
    await tester.pumpAndSettle();
  }

  TextField captureField(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField));

  IconButton sendButton(WidgetTester tester) => tester.widget<IconButton>(
    find.widgetWithIcon(IconButton, Icons.arrow_upward_rounded),
  );

  Finder listedImage() => find.descendant(
    of: find.byType(AnimatedList),
    matching: find.byType(Image),
  );

  Future<void> pressPaste(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  Future<void> pasteImageFromMenu(WidgetTester tester, [Finder? field]) async {
    await tester.longPress(field ?? find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste image'));
    await tester.pumpAndSettle();
  }

  // Decoding runs in the engine, outside the test's fake clock.
  Future<void> decodeImages(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

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

    expect(sendButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Buy bread');
    await tester.pump();
    await tester.tap(find.byWidget(sendButton(tester)));
    await tester.pumpAndSettle();

    expect(find.text('Buy bread'), findsOneWidget);
    expect(sendButton(tester).onPressed, isNull);
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

  testWidgets('the edit dialog deletes the thought, with undo', (tester) async {
    await pumpApp(tester, [
      Thought(id: '1', text: 'Buy bread', createdAt: DateTime.now()),
    ]);

    await tester.tap(find.text('Buy bread'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Buy bread'), findsNothing);
    expect(store.thoughts, isEmpty);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Buy bread'), findsOneWidget);
  });

  testWidgets('hovering a thought with a mouse reveals a delete button', (
    tester,
  ) async {
    await pumpApp(tester, [
      Thought(id: '1', text: 'Buy bread', createdAt: DateTime.now()),
    ]);
    double opacity() => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: find.byTooltip('Delete'),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;

    expect(opacity(), 0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.text('Buy bread')));
    await tester.pumpAndSettle();
    expect(opacity(), 1);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Buy bread'), findsNothing);
    expect(store.thoughts, isEmpty);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('touch screens rely on the swipe, without a delete button', (
    tester,
  ) async {
    await pumpApp(tester, [
      Thought(id: '1', text: 'Buy bread', createdAt: DateTime.now()),
    ]);

    expect(find.byTooltip('Delete'), findsNothing);
  }, variant: TargetPlatformVariant.mobile());

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

  testWidgets('editing adds an image to a thought', (tester) async {
    await pumpApp(tester, [
      Thought(id: '1', text: 'Poster', createdAt: DateTime.now()),
    ]);
    clipboardImage = png;

    await tester.tap(find.text('Poster'));
    await tester.pumpAndSettle();
    await pressPaste(tester);
    expect(find.byTooltip('Remove image'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await store.flush();

    expect(storage.images[storage.saved.single.image], png);
    expect(listedImage(), findsOneWidget);
  });

  testWidgets('editing removes the image, then text is required', (
    tester,
  ) async {
    await pumpApp(
      tester,
      [Thought(id: '1', text: '', image: 'receipt', createdAt: DateTime.now())],
      {'receipt': png},
    );
    FilledButton saveButton() =>
        tester.widget(find.widgetWithText(FilledButton, 'Save'));

    await tester.tap(find.text('just now'));
    await tester.pumpAndSettle();
    expect(saveButton().onPressed, isNotNull);

    await tester.tap(find.byTooltip('Remove image'));
    await tester.pump();
    expect(saveButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, 'Receipt');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(store.thoughts.single.text, 'Receipt');
    expect(store.thoughts.single.image, isNull);
    expect(listedImage(), findsNothing);
  });

  testWidgets('editing reports a missing image inside the dialog', (
    tester,
  ) async {
    await pumpApp(tester, [
      Thought(id: '1', text: 'Poster', createdAt: DateTime.now()),
    ]);

    await tester.tap(find.text('Poster'));
    await tester.pumpAndSettle();
    await pasteImageFromMenu(tester, find.byType(TextField).last);

    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('No image in the clipboard.'),
      ),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('pasting an image alone attaches it, ready to send', (
    tester,
  ) async {
    await pumpApp(tester);
    clipboardImage = png;

    await pressPaste(tester);
    expect(find.byTooltip('Remove image'), findsOneWidget);
    expect(sendButton(tester).onPressed, isNotNull);

    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    await store.flush();

    expect(find.byTooltip('Remove image'), findsNothing);
    expect(listedImage(), findsOneWidget);
    final saved = storage.saved.single;
    expect(saved.text, isEmpty);
    expect(storage.images[saved.image], png);
  });

  testWidgets('pasting prefers text when the clipboard also has some', (
    tester,
  ) async {
    await pumpApp(tester);
    clipboardImage = png;
    clipboardText = 'Copied from Word';

    await pressPaste(tester);

    expect(captureField(tester).controller!.text, 'Copied from Word');
    expect(find.byTooltip('Remove image'), findsNothing);
  });

  testWidgets('"Paste image" attaches the image, or says there is none', (
    tester,
  ) async {
    await pumpApp(tester);

    await pasteImageFromMenu(tester);
    expect(find.text('No image in the clipboard.'), findsOneWidget);

    clipboardImage = png;
    clipboardText = 'Ignored';
    await pasteImageFromMenu(tester);
    expect(find.byTooltip('Remove image'), findsOneWidget);
    expect(captureField(tester).controller!.text, isEmpty);

    await tester.tap(find.byTooltip('Remove image'));
    await tester.pump();
    expect(find.byTooltip('Remove image'), findsNothing);
    expect(sendButton(tester).onPressed, isNull);
  });

  testWidgets('tapping an image shows it full screen', (tester) async {
    await pumpApp(
      tester,
      [
        Thought(
          id: '1',
          text: 'Receipt',
          image: 'receipt',
          createdAt: DateTime.now(),
        ),
      ],
      {'receipt': png},
    );
    await decodeImages(tester);

    await tester.tap(listedImage());
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('follows a French device locale', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('fr', 'FR')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await pumpApp(tester);

    expect(find.text("Qu'est-ce que tu as en tête ?"), findsOneWidget);
    expect(find.text("Ce que tu notes s'affiche ici."), findsOneWidget);
  });
}
