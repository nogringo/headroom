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
final otherPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==',
);

void main() {
  late InMemoryStorage storage;
  late ThoughtStore store;
  Uint8List? clipboardImage;
  String? clipboardText;
  Uint8List? copiedImage;
  var copyFails = false;

  Future<void> pumpApp(
    WidgetTester tester, [
    List<Thought> initial = const [],
    Map<String, Uint8List> images = const {},
  ]) async {
    clipboardImage = null;
    clipboardText = null;
    copiedImage = null;
    copyFails = false;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('pasteboard'), (
      call,
    ) async {
      switch (call.method) {
        case 'image':
          return clipboardImage;
        case 'writeImage':
          if (copyFails) throw PlatformException(code: 'denied');
          copiedImage = call.arguments as Uint8List;
      }
      return null;
    });
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

  testWidgets('on a computer, Enter sends and Shift+Enter starts a new line', (
    tester,
  ) async {
    await pumpApp(tester);

    // The platform inserts the line break, as the field takes several lines.
    expect(captureField(tester).keyboardType, TextInputType.multiline);
    await tester.enterText(find.byType(TextField), 'Call the garage');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(store.thoughts, isEmpty);

    await tester.enterText(find.byType(TextField), 'Call the garage\nTyres');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(store.thoughts.single.text, 'Call the garage\nTyres');
    expect(captureField(tester).controller!.text, isEmpty);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('Enter is left to an input method that is composing', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.showKeyboard(find.byType(TextField));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'にほん',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 3),
      ),
    );
    await tester.pump();

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isFalse);
    expect(store.thoughts, isEmpty);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('touch keyboards keep their send key', (tester) async {
    await pumpApp(tester);

    expect(captureField(tester).textInputAction, TextInputAction.send);
  }, variant: TargetPlatformVariant.mobile());

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

  testWidgets('undo goes away on its own', (tester) async {
    await pumpApp(tester, [
      Thought(id: '1', text: 'Buy bread', createdAt: DateTime.now()),
    ]);

    await tester.drag(find.text('Buy bread'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('undo waits for a screen reader', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpApp(tester, [
      Thought(id: '1', text: 'Buy bread', createdAt: DateTime.now()),
    ]);

    await tester.drag(find.text('Buy bread'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(find.text('Undo'), findsOneWidget);
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

  testWidgets('on a computer, Enter saves an edit', (tester) async {
    await pumpApp(tester, [
      Thought(id: '1', text: 'Buy bread', createdAt: DateTime.now()),
    ]);

    await tester.tap(find.text('Buy bread'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Buy bread\nAnd milk');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(store.thoughts.single.text, 'Buy bread\nAnd milk');
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('editing adds images after the ones a thought has', (
    tester,
  ) async {
    await pumpApp(
      tester,
      [
        Thought(
          id: '1',
          text: 'Poster',
          images: ['front'],
          createdAt: DateTime.now(),
        ),
      ],
      {'front': png},
    );
    clipboardImage = png;

    await tester.tap(find.text('Poster'));
    await tester.pumpAndSettle();
    await pressPaste(tester);
    expect(find.byTooltip('Remove image'), findsNWidgets(2));

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await store.flush();

    final images = storage.saved.single.images;
    expect(images, hasLength(2));
    expect(images.first, 'front');
    expect(storage.images[images.last], png);
    expect(listedImage(), findsNWidgets(2));
  });

  testWidgets('editing removes the image, then text is required', (
    tester,
  ) async {
    await pumpApp(
      tester,
      [
        Thought(
          id: '1',
          text: '',
          images: ['receipt'],
          createdAt: DateTime.now(),
        ),
      ],
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
    expect(store.thoughts.single.images, isEmpty);
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
    expect(storage.images[saved.images.single], png);
  });

  testWidgets('pasting adds each new image once, each removable', (
    tester,
  ) async {
    await pumpApp(tester);

    clipboardImage = png;
    await pressPaste(tester);
    clipboardImage = otherPng;
    await pressPaste(tester);
    expect(find.byTooltip('Remove image'), findsNWidgets(2));

    await pressPaste(tester);
    expect(find.byTooltip('Remove image'), findsNWidgets(2));
    expect(find.text('Image already added.'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove image').first);
    await tester.pump();
    expect(find.byTooltip('Remove image'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    await store.flush();

    expect(storage.images[storage.saved.single.images.single], otherPng);
    expect(listedImage(), findsOneWidget);
  });

  testWidgets('editing refuses an image the thought already has', (
    tester,
  ) async {
    final name = await InMemoryStorage().saveImage(png);
    await pumpApp(
      tester,
      [
        Thought(
          id: '1',
          text: 'Poster',
          images: [name],
          createdAt: DateTime.now(),
        ),
      ],
      {name: png},
    );
    clipboardImage = png;

    await tester.tap(find.text('Poster'));
    await tester.pumpAndSettle();
    await pressPaste(tester);

    expect(find.byTooltip('Remove image'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Image already added.'),
      ),
      findsOneWidget,
    );
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
          images: ['receipt'],
          createdAt: DateTime.now(),
        ),
      ],
      {'receipt': png},
    );
    await decodeImages(tester);

    await tester.tap(listedImage());
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);

    expect(find.byTooltip('Next image'), findsNothing);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  Future<void> openViewer(WidgetTester tester) async {
    await pumpApp(
      tester,
      [
        Thought(
          id: '1',
          text: 'Receipt',
          images: ['receipt'],
          createdAt: DateTime.now(),
        ),
      ],
      {'receipt': png},
    );
    await decodeImages(tester);
    await tester.tap(listedImage());
    await tester.pumpAndSettle();
  }

  testWidgets('the viewer copies the image it shows', (tester) async {
    await openViewer(tester);

    await tester.tap(find.byTooltip('Copy image'));
    await tester.pumpAndSettle();
    expect(copiedImage, png);
    expect(find.byTooltip('Image copied'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.byTooltip('Copy image'), findsOneWidget);
  });

  testWidgets('Ctrl+C in the viewer copies the image', (tester) async {
    await openViewer(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(copiedImage, png);
  });

  testWidgets('a failed copy says so inside the viewer', (tester) async {
    await openViewer(tester);
    copyFails = true;

    await tester.tap(find.byTooltip('Copy image'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isA<PlatformException>());
    expect(find.text("Couldn't copy the image."), findsOneWidget);
    expect(find.byTooltip('Copy image'), findsOneWidget);
  });

  testWidgets('the viewer offers no copy on Linux', (tester) async {
    await openViewer(tester);

    expect(find.byTooltip('Copy image'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  Future<void> pumpReceipt(WidgetTester tester) async {
    await pumpApp(
      tester,
      [
        Thought(
          id: '1',
          text: 'Receipt',
          images: ['receipt'],
          createdAt: DateTime.now(),
        ),
      ],
      {'receipt': png},
    );
    await decodeImages(tester);
  }

  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    await tester.tap(
      finder,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('right-clicking a listed image offers to copy it', (
    tester,
  ) async {
    await pumpReceipt(tester);

    await rightClick(tester, listedImage());
    await tester.tap(find.text('Copy image'));
    await tester.pumpAndSettle();

    expect(copiedImage, png);
    expect(find.text('Copy image'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('long-pressing a listed image offers to copy it', (tester) async {
    await pumpReceipt(tester);

    await tester.longPress(listedImage());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy image'));
    await tester.pumpAndSettle();

    expect(copiedImage, png);
  });

  testWidgets('clicking elsewhere closes the copy menu', (tester) async {
    await pumpReceipt(tester);

    await rightClick(tester, listedImage());
    expect(find.text('Copy image'), findsOneWidget);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('Copy image'), findsNothing);
    expect(copiedImage, isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a failed copy from the list says so', (tester) async {
    await pumpReceipt(tester);
    copyFails = true;

    await tester.longPress(listedImage());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy image'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isA<PlatformException>());
    expect(find.text("Couldn't copy the image."), findsOneWidget);
  });

  testWidgets('right-clicking in the viewer copies the image shown', (
    tester,
  ) async {
    await openViewer(tester);

    await rightClick(tester, find.byType(InteractiveViewer));
    await tester.tap(find.text('Copy image'));
    await tester.pumpAndSettle();

    expect(copiedImage, png);
    expect(find.byTooltip('Image copied'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Linux gets no copy menu', (tester) async {
    await pumpReceipt(tester);

    await rightClick(tester, listedImage());

    expect(find.text('Copy image'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('the viewer turns between the images of a thought', (
    tester,
  ) async {
    await pumpApp(
      tester,
      [
        Thought(
          id: '1',
          text: 'Before and after',
          images: ['before', 'after'],
          createdAt: DateTime.now(),
        ),
      ],
      {'before': png, 'after': png},
    );
    await decodeImages(tester);
    int page() => tester
        .widget<PageView>(find.byType(PageView))
        .controller!
        .page!
        .round();

    await tester.tap(listedImage().last);
    await tester.pumpAndSettle();
    expect(page(), 1);
    expect(find.byTooltip('Next image'), findsNothing);

    await tester.tap(find.byTooltip('Previous image'));
    await tester.pumpAndSettle();
    expect(page(), 0);
    expect(find.byTooltip('Previous image'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(page(), 1);

    await tester.drag(find.byType(PageView), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(page(), 0);
  });

  testWidgets('follows a French device locale', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('fr', 'FR')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await pumpApp(tester);

    expect(find.text("Qu'est-ce que tu as en tête ?"), findsOneWidget);
    expect(find.text("Ce que tu notes s'affiche ici."), findsOneWidget);
  });
}
