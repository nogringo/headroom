import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/backup.dart';
import 'package:headroom/clipboard_image_io.dart' show writeClipboardImage;
import 'package:headroom/list_settings.dart';
import 'package:headroom/main.dart';
import 'package:headroom/thought.dart';
import 'package:headroom/thought_store.dart';
import 'package:headroom/tidier.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'ai_replies.dart';
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
  late Tidier tidier;
  late ListSettings listSettings;
  Uint8List? clipboardImage;
  String? clipboardText;
  Uint8List? copiedImage;
  var copyFails = false;

  Future<void> pumpApp(
    WidgetTester tester, [
    List<Thought> initial = const [],
    Map<String, Uint8List> images = const {},
    // Sets up an AI answered by this, when given.
    Future<http.Response> Function(http.Request)? ai,
  ]) async {
    clipboardImage = null;
    clipboardText = null;
    copiedImage = null;
    copyFails = false;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('pasteboard'),
      (call) async => call.method == 'image' ? clipboardImage : null,
    );
    final realWriteClipboardImage = writeClipboardImage;
    writeClipboardImage = (image) async {
      if (copyFails) throw PlatformException(code: 'denied');
      copiedImage = image;
    };
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
      writeClipboardImage = realWriteClipboardImage;
    });

    storage = InMemoryStorage(initial)..images.addAll(images);
    if (ai != null) storage.values['ai'] = jsonEncode(testAi);
    store = ThoughtStore(storage);
    await store.load();
    tidier = Tidier(
      store,
      storage,
      client: MockClient(ai ?? (_) => throw StateError('No AI set up')),
      delay: Duration.zero,
    );
    await tidier.load();
    listSettings = ListSettings(storage);
    await listSettings.load();
    await tester.pumpWidget(
      HeadroomApp(
        store: store,
        tidier: tidier,
        listSettings: listSettings,
        backup: Backup(store, tidier, listSettings, storage),
      ),
    );
    await tester.pumpAndSettle();
  }

  TextField captureField(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField));

  IconButton sendButton(WidgetTester tester) => tester.widget<IconButton>(
    find.widgetWithIcon(IconButton, Icons.arrow_upward_rounded),
  );

  Finder listedImage() => find.descendant(
    of: find.byType(SliverAnimatedList),
    matching: find.byType(Image),
  );

  Finder listed(String text) => find.descendant(
    of: find.byType(SliverAnimatedList),
    matching: find.text(text),
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
    expect(find.text('Today'), findsOneWidget);
    expect(captureField(tester).controller!.text, isEmpty);
    expect(captureField(tester).focusNode!.hasFocus, isTrue);
    expect(storage.saved.single.text, 'Call the garage');
  });

  testWidgets('a screen reader hears that the thought was noted', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.enterText(find.byType(TextField), 'Call the garage');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(tester.takeAnnouncements(), [
      isAccessibilityAnnouncement('Thought noted'),
    ]);
  });

  testWidgets('the field keeps its label once it holds text', (tester) async {
    await pumpApp(tester);

    await tester.enterText(find.byType(TextField), 'Buy bread');
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.byType(EditableText)),
      isSemantics(label: 'Thought', value: 'Buy bread'),
    );
  });

  testWidgets('a failed save is read out', (tester) async {
    await pumpApp(tester);
    storage.failWrites = true;

    await tester.enterText(find.byType(TextField), 'Buy bread');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isStateError);
    expect(
      tester.getSemantics(
        find.text(
          "Couldn't save to this device. Retrying on your next change.",
        ),
      ),
      isSemantics(isLiveRegion: true),
    );
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

  group('back to the field', () {
    bool fieldFocused(WidgetTester tester) => tester
        .widget<TextField>(find.byType(TextField).first)
        .focusNode!
        .hasFocus;

    Future<void> leaveField(WidgetTester tester) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(fieldFocused(tester), isFalse);
    }

    Future<void> press(
      WidgetTester tester,
      LogicalKeyboardKey key, {
      LogicalKeyboardKey? modifier,
      String? character,
    }) async {
      if (modifier != null) await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(key, character: character);
      if (modifier != null) await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
    }

    testWidgets('with Ctrl+N or /', (tester) async {
      await pumpApp(tester);

      await leaveField(tester);
      await press(
        tester,
        LogicalKeyboardKey.keyN,
        modifier: LogicalKeyboardKey.controlLeft,
      );
      expect(fieldFocused(tester), isTrue);

      await leaveField(tester);
      await press(tester, LogicalKeyboardKey.slash, character: '/');
      expect(fieldFocused(tester), isTrue);
      expect(captureField(tester).controller!.text, isEmpty);
    });

    testWidgets('with Cmd+N on a Mac', (tester) async {
      await pumpApp(tester);

      await leaveField(tester);
      await press(
        tester,
        LogicalKeyboardKey.keyN,
        modifier: LogicalKeyboardKey.controlLeft,
      );
      expect(fieldFocused(tester), isFalse);
      await press(
        tester,
        LogicalKeyboardKey.keyN,
        modifier: LogicalKeyboardKey.metaLeft,
      );
      expect(fieldFocused(tester), isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('from the open drawer, which closes', (tester) async {
      await pumpApp(tester, [
        Thought(
          id: '1',
          text: 'Buy bread',
          createdAt: DateTime.now(),
          theme: 'Errands',
        ),
      ]);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.slash, character: '/');

      expect(find.byType(Drawer), findsNothing);
      expect(fieldFocused(tester), isTrue);
    });

    testWidgets('not from a dialog', (tester) async {
      await pumpApp(tester, [
        Thought(id: '1', text: 'Buy bread', createdAt: DateTime.now()),
      ]);
      await tester.tap(find.text('Buy bread'));
      await tester.pumpAndSettle();

      await press(
        tester,
        LogicalKeyboardKey.keyN,
        modifier: LogicalKeyboardKey.controlLeft,
      );

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(fieldFocused(tester), isFalse);
    });
  });

  testWidgets('touch keyboards keep their send key', (tester) async {
    await pumpApp(tester);

    expect(captureField(tester).textInputAction, TextInputAction.send);
  }, variant: TargetPlatformVariant.mobile());

  testWidgets('large text with the keyboard up fits a landscape phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(667, 375);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester);

    await tester.enterText(find.byType(TextField), 'word ' * 40);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
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

  testWidgets('thoughts are listed under their day', (tester) async {
    final now = DateTime.now();
    await pumpApp(tester, [
      Thought(id: '3', text: 'Buy bread', createdAt: now),
      Thought(id: '2', text: 'Call the garage', createdAt: now),
      Thought(
        id: '1',
        text: 'Water the plants',
        createdAt: now.subtract(const Duration(days: 1)),
      ),
    ]);

    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(top('Today'), lessThan(top('Buy bread')));
    expect(top('Call the garage'), lessThan(top('Yesterday')));
    expect(top('Yesterday'), lessThan(top('Water the plants')));
  });

  testWidgets('the first thought of the day brings its heading', (
    tester,
  ) async {
    await pumpApp(tester, [
      Thought(
        id: '1',
        text: 'Water the plants',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ]);
    expect(find.text('Today'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Buy bread');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
  });

  testWidgets('a day without thoughts loses its heading until undo', (
    tester,
  ) async {
    await pumpApp(tester, [
      Thought(id: '2', text: 'Buy bread', createdAt: DateTime.now()),
      Thought(
        id: '1',
        text: 'Water the plants',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ]);

    await tester.drag(find.text('Water the plants'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Yesterday'), findsNothing);
    expect(find.text('Today'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Water the plants'), findsOneWidget);
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

  testWidgets('a touch where the delete button hides opens the thought', (
    tester,
  ) async {
    await pumpApp(tester, [
      Thought(id: '1', text: 'Buy bread', createdAt: DateTime.now()),
    ]);

    await tester.tapAt(tester.getCenter(find.byTooltip('Delete')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(store.thoughts, hasLength(1));
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('a screen reader reaches the hidden delete button', (
    tester,
  ) async {
    await pumpApp(tester, [
      Thought(id: '1', text: 'Buy bread', createdAt: DateTime.now()),
    ]);

    tester.semantics.tap(
      find.semantics.byPredicate((node) => node.tooltip == 'Delete'),
    );
    await tester.pumpAndSettle();

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
          createdAt: DateTime(2026, 3, 2, 9, 41),
        ),
      ],
      {'receipt': png},
    );
    FilledButton saveButton() =>
        tester.widget(find.widgetWithText(FilledButton, 'Save'));

    await tester.tap(find.text('9:41 AM'));
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
    expect(
      tester.getSemantics(find.text('No image in the clipboard.')),
      isSemantics(isLiveRegion: true),
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

    expect(find.bySemanticsLabel('Image 1 of 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Image 2 of 2'), findsOneWidget);

    await tester.tap(listedImage().last);
    await tester.pumpAndSettle();
    expect(page(), 1);
    expect(
      find.descendant(
        of: find.byType(PageView),
        matching: find.bySemanticsLabel('Image 2 of 2'),
      ),
      findsOneWidget,
    );
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

  testWidgets('has no sidebar until a thought has a theme', (tester) async {
    await pumpApp(tester, [
      Thought(id: '1', text: 'Buy bread', createdAt: DateTime.now()),
    ]);
    expect(find.byTooltip('Open navigation menu'), findsNothing);
    expect(find.byTooltip('AI tidying'), findsOneWidget);
  });

  testWidgets('opens the backup from the toolbar, even with no thought', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Backup'));
    await tester.pumpAndSettle();

    expect(find.text('No copy saved yet'), findsOneWidget);
    expect(find.text('Restore a copy'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Restore a copy'), findsNothing);
  });

  testWidgets('opens the backup from the sidebar', (tester) async {
    await pumpApp(tester, [
      Thought(
        id: '1',
        text: 'Buy bread',
        createdAt: DateTime.now(),
        theme: 'Errands',
      ),
    ]);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Backup'));
    await tester.pumpAndSettle();

    expect(find.text('Save a copy'), findsOneWidget);
  });

  testWidgets('lists the thoughts the AI will not sort under No theme', (
    tester,
  ) async {
    final now = DateTime.now();
    await pumpApp(tester, [
      Thought(id: '2', text: 'Fix the build', createdAt: now, theme: 'Work'),
      Thought(id: '1', text: 'Buy bread', createdAt: now),
    ]);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No theme'));
    await tester.pumpAndSettle();
    expect(listed('Buy bread'), findsOneWidget);
    expect(listed('Fix the build'), findsNothing);
  });

  testWidgets('opens on the theme it was left on, while it has thoughts', (
    tester,
  ) async {
    final now = DateTime.now();
    await pumpApp(tester, [
      Thought(id: '2', text: 'Fix the build', createdAt: now, theme: 'Work'),
      Thought(id: '1', text: 'Buy bread', createdAt: now, theme: 'Errands'),
    ]);
    Future<void> reopen(String theme) async {
      storage.values['list'] = jsonEncode({'theme': theme});
      final listSettings = ListSettings(storage);
      await listSettings.load();
      await tester.pumpWidget(
        HeadroomApp(
          key: UniqueKey(),
          store: store,
          tidier: tidier,
          listSettings: listSettings,
          backup: Backup(store, tidier, listSettings, storage),
        ),
      );
      await tester.pumpAndSettle();
    }

    await reopen('Work');
    expect(listed('Fix the build'), findsOneWidget);
    expect(listed('Buy bread'), findsNothing);

    await reopen('Gone');
    expect(find.text('All'), findsOneWidget);
    expect(listed('Buy bread'), findsOneWidget);
  });

  testWidgets('the edit dialog puts a thought in another theme, or a new one', (
    tester,
  ) async {
    final now = DateTime.now();
    await pumpApp(tester, [
      Thought(id: '3', text: 'Buy milk', createdAt: now, theme: 'Errands'),
      Thought(id: '2', text: 'Fix the build', createdAt: now, theme: 'Work'),
      Thought(id: '1', text: 'Buy bread', createdAt: now, theme: 'Errands'),
    ]);
    Thought bread() => store.thoughts.last;
    Future<void> openMenu() async {
      await tester.tap(find.text('Buy bread'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Theme'));
      await tester.pumpAndSettle();
    }

    Future<void> create(String name) async {
      await tester.tap(find.text('New theme...'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Theme name'),
        name,
      );
      await tester.pump();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
    }

    await openMenu();
    expect(find.text('Let the AI choose'), findsNothing);
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(bread().theme, 'Work');
    expect(bread().themeChosen, isTrue);

    await openMenu();
    await create('Bakery');
    expect(find.text('Bakery'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(bread().theme, 'Work');

    await openMenu();
    await create('errands');
    expect(find.text('Errands'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(bread().theme, 'Errands');

    await openMenu();
    await tester.tap(find.text('No theme'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a theme'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(bread().theme, isNull);
    expect(bread().themeChosen, isFalse);
  });

  testWidgets('renames the open theme, or joins it to another', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    await pumpApp(tester, [
      Thought(id: '2', text: 'Fix the build', createdAt: now, theme: 'Work'),
      Thought(id: '1', text: 'Buy bread', createdAt: now, theme: 'Errands'),
    ]);
    Future<void> rename(String name) async {
      await tester.tap(find.byTooltip('Rename theme'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Theme name'),
        name,
      );
      await tester.pump();
    }

    expect(find.byTooltip('Rename theme'), findsNothing);
    await tester.tap(find.text('Errands'));
    await tester.pumpAndSettle();

    await rename('Shopping');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.text('Errands'), findsNothing);
    expect(find.text('Shopping'), findsOneWidget);
    expect(listed('Buy bread'), findsOneWidget);
    final reopened = ListSettings(storage);
    await reopened.load();
    expect(reopened.theme, 'Shopping');

    await rename('work');
    expect(
      find.text('Its thoughts will join Work, which already exists.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.text('Shopping'), findsNothing);
    expect(listed('Buy bread'), findsOneWidget);
    expect(listed('Fix the build'), findsOneWidget);
    expect(store.thoughts.map((t) => t.theme), ['Work', 'Work']);
  });

  group('the sidebar', () {
    late List<String> Function() order;

    Future<void> pumpThemes(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      await pumpApp(tester, [
        Thought(id: '4', text: 'Pay rent', createdAt: now),
        Thought(id: '3', text: 'Read Dune', createdAt: now, theme: 'Études'),
        Thought(id: '2', text: 'Fix the build', createdAt: now, theme: 'Work'),
        Thought(id: '1', text: 'Buy bread', createdAt: now, theme: 'Errands'),
      ]);
      order = () {
        final themes = [
          'Errands',
          'Études',
          'Work',
          'Bills',
        ].where((theme) => find.text(theme).evaluate().isNotEmpty);
        return themes.toList()..sort(
          (a, b) => tester
              .getTopLeft(find.text(a))
              .dy
              .compareTo(tester.getTopLeft(find.text(b)).dy),
        );
      };
    }

    Future<List<String>> savedOrder() async {
      final reopened = ListSettings(storage);
      await reopened.load();
      return reopened.themeOrder;
    }

    Future<void> drag(
      WidgetTester tester,
      TestGesture gesture,
      double dy,
    ) async {
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(Offset(0, dy / 10));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('moves a theme dragged with a mouse or after a long press', (
      tester,
    ) async {
      await pumpThemes(tester);
      expect(order(), ['Errands', 'Études', 'Work']);

      final mouse = await tester.startGesture(
        tester.getCenter(find.text('Work')),
        kind: PointerDeviceKind.mouse,
      );
      await drag(tester, mouse, -100);
      expect(order(), ['Work', 'Errands', 'Études']);
      expect(await savedOrder(), ['Work', 'Errands', 'Études']);

      final finger = await tester.startGesture(
        tester.getCenter(find.text('Errands')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await drag(tester, finger, 50);
      expect(order(), ['Work', 'Études', 'Errands']);

      store.chooseTheme('4', 'Bills');
      await tester.pumpAndSettle();
      expect(order(), ['Work', 'Études', 'Errands', 'Bills']);
    });

    testWidgets('a click that wobbles still opens the theme', (tester) async {
      await pumpThemes(tester);

      final mouse = await tester.startGesture(
        tester.getCenter(find.text('Work')),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveBy(const Offset(0, 4));
      await mouse.up();
      await tester.pumpAndSettle();

      expect(listed('Fix the build'), findsOneWidget);
      expect(listed('Buy bread'), findsNothing);
      expect(await savedOrder(), isEmpty);
    });

    testWidgets('a screen reader or the keyboard moves a theme', (
      tester,
    ) async {
      await pumpThemes(tester);

      Focus.of(tester.element(find.text('Errands'))).requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(order(), ['Études', 'Errands', 'Work']);
      expect(
        Focus.of(tester.element(find.text('Errands'))).hasPrimaryFocus,
        isTrue,
      );

      tester.semantics.customAction(
        find.semantics.byLabel('Work'),
        const CustomSemanticsAction(label: 'Move up'),
      );
      await tester.pumpAndSettle();
      expect(order(), ['Études', 'Work', 'Errands']);
      expect(await savedOrder(), ['Études', 'Work', 'Errands']);
    });

    testWidgets('follows the order a backup brings', (tester) async {
      await pumpThemes(tester);

      listSettings.restoreThemeOrder(['Work', 'Études']);
      await tester.pumpAndSettle();

      expect(order(), ['Work', 'Études', 'Errands']);
    });

    testWidgets('a renamed theme keeps its place', (tester) async {
      await pumpThemes(tester);
      listSettings.themeOrder = ['Work', 'Errands', 'Études'];
      await tester.tap(find.text('Errands'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Rename theme'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Theme name'),
        'Shopping',
      );
      await tester.pump();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(await savedOrder(), ['Work', 'Shopping', 'Études']);
    });
  });

  group('with an AI', () {
    testWidgets('a wide window lists one theme at a time from the sidebar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      await pumpApp(
        tester,
        [
          Thought(
            id: '4',
            text: 'Fix the build',
            createdAt: now,
            theme: 'Work',
          ),
          Thought(id: '3', text: 'Buy milk', createdAt: now, theme: 'Errands'),
          Thought(id: '2', text: 'milk!!', createdAt: now, theme: 'Errands'),
          Thought(
            id: '1',
            text: 'Read Dune',
            createdAt: now.subtract(const Duration(days: 3)),
            theme: 'Études',
          ),
        ],
        const {},
        (request) async => chatReply({
          'themes': {},
          'merges': [
            {
              'thoughts': [2, 3],
              'text': 'Buy lots of milk',
            },
          ],
        }),
      );
      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(find.byTooltip('Open navigation menu'), findsNothing);
      expect(top('All'), lessThan(top('Errands')));
      expect(top('Errands'), lessThan(top('Études')));
      expect(top('Études'), lessThan(top('Work')));
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Clean-up'), findsOneWidget);

      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();
      expect(listed('Fix the build'), findsOneWidget);
      expect(listed('Buy milk'), findsNothing);
      expect(listed('Read Dune'), findsNothing);
      expect(find.text('Today'), findsNothing);
      expect(find.text('Clean-up'), findsNothing);

      await tester.tap(find.text('Errands'));
      await tester.pumpAndSettle();
      expect(listed('Buy milk'), findsOneWidget);
      expect(listed('Fix the build'), findsNothing);
      expect(find.text('Clean-up'), findsOneWidget);
      final reopened = ListSettings(storage);
      await reopened.load();
      expect(reopened.theme, 'Errands');

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(listed('Fix the build'), findsOneWidget);
      expect(listed('Read Dune'), findsOneWidget);
    });

    testWidgets(
      'a thought noted in a theme stays there until the AI sorts it',
      (tester) async {
        final now = DateTime.now();
        final answer = Completer<void>();
        var asked = 0;
        await pumpApp(
          tester,
          [
            Thought(
              id: '2',
              text: 'Fix the build',
              createdAt: now,
              theme: 'Work',
            ),
            Thought(
              id: '1',
              text: 'Buy bread',
              createdAt: now,
              theme: 'Errands',
            ),
          ],
          const {},
          (request) async {
            if (asked++ > 0) await answer.future;
            return sortAllInto(request, 'Errands');
          },
        );
        expect(find.text('All'), findsOneWidget);
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Work'));
        await tester.pumpAndSettle();
        expect(find.text('Work'), findsOneWidget);
        expect(listed('Fix the build'), findsOneWidget);
        expect(listed('Buy bread'), findsNothing);

        await tester.enterText(find.byType(TextField), 'Buy milk');
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.pumpAndSettle();
        expect(listed('Buy milk'), findsOneWidget);

        answer.complete();
        await tester.pumpAndSettle();
        expect(store.thoughts.first.theme, 'Errands');
        expect(listed('Buy milk'), findsNothing);
        expect(listed('Fix the build'), findsOneWidget);
      },
    );

    testWidgets('merges the thoughts it finds repeated, until undone', (
      tester,
    ) async {
      final now = DateTime.now();
      await pumpApp(
        tester,
        [
          Thought(id: '2', text: 'Buy milk', createdAt: now, theme: 'Errands'),
          Thought(id: '1', text: 'milk!!', createdAt: now, theme: 'Errands'),
        ],
        const {},
        (request) async => chatReply({
          'themes': {},
          'merges': [
            {
              'thoughts': [1, 2],
              'text': 'Buy lots of milk',
            },
          ],
        }),
      );

      expect(find.text('Clean-up'), findsOneWidget);
      expect(find.text('These thoughts repeat each other:'), findsOneWidget);
      expect(find.text('Buy lots of milk'), findsOneWidget);

      await tester.tap(find.text('Merge'));
      await tester.pumpAndSettle();
      expect(find.text('Clean-up'), findsNothing);
      expect(find.text('milk!!'), findsNothing);
      expect(store.thoughts.map((t) => t.text), ['Buy lots of milk']);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(store.thoughts.map((t) => t.text), ['Buy milk', 'milk!!']);
      expect(find.text('Clean-up'), findsNothing);
    });

    testWidgets('an out-of-date thought can be kept or deleted', (
      tester,
    ) async {
      final now = DateTime.now();
      await pumpApp(
        tester,
        [
          Thought(
            id: '2',
            text: 'Party on Friday',
            createdAt: now,
            theme: 'Fun',
          ),
          Thought(
            id: '1',
            text: 'Dentist on Monday',
            createdAt: now,
            theme: 'Health',
          ),
        ],
        const {},
        (request) async => chatReply({
          'themes': {},
          'outdated': [1, 2],
        }),
      );

      expect(find.text('This thought looks out of date:'), findsOneWidget);
      expect(find.text('2 suggestions'), findsOneWidget);

      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(find.text('1 suggestion'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Clean-up'), findsNothing);
      expect(find.text('Thought deleted'), findsOneWidget);
      expect(store.thoughts.map((t) => t.text), ['Party on Friday']);
    });

    testWidgets('a tidying error stays shown until a retry works', (
      tester,
    ) async {
      var refuse = true;
      await pumpApp(
        tester,
        [Thought(id: '1', text: 'Buy bread', createdAt: DateTime.now())],
        const {},
        (request) async => refuse
            ? http.Response(
                jsonEncode({
                  'error': {'code': '1113', 'message': 'Insufficient balance.'},
                }),
                429,
              )
            : sortAllInto(request, 'Errands'),
      );
      const error =
          "Tidying paused: the AI service's limit or credit is used up.";
      expect(find.text(error), findsOneWidget);
      expect(find.text('Insufficient balance.'), findsOneWidget);
      expect(
        tester.getSemantics(find.text(error)),
        isSemantics(isLiveRegion: true),
      );

      refuse = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text(error), findsNothing);
      expect(find.text('Insufficient balance.'), findsNothing);
      expect(store.thoughts.single.theme, 'Errands');
    });

    testWidgets('a chosen theme can be handed back to the AI', (tester) async {
      await pumpApp(
        tester,
        [
          Thought(
            id: '1',
            text: 'Buy bread',
            createdAt: DateTime.now(),
            theme: 'Bakery',
            themeChosen: true,
          ),
        ],
        const {},
        (request) async => sortAllInto(request, 'Errands'),
      );

      await tester.tap(find.text('Buy bread'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Theme'));
      await tester.pumpAndSettle();
      expect(find.text('No theme'), findsNothing);
      await tester.tap(find.text('Let the AI choose'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(store.thoughts.single.theme, 'Errands');
      expect(store.thoughts.single.themeChosen, isFalse);
    });

    testWidgets('is set up from the broom button', (tester) async {
      var sort = false;
      await pumpApp(
        tester,
        [Thought(id: '1', text: 'Buy bread', createdAt: DateTime.now())],
        const {},
        (request) async => request.method == 'GET'
            ? http.Response(
                jsonEncode({
                  'data': [
                    {'id': 'claude-opus-5-5'},
                    {'id': 'claude-haiku-5-5'},
                  ],
                }),
                200,
              )
            : sort
            ? sortAllInto(request, 'Errands')
            : chatReply({'themes': {}}),
      );
      await tidier.configure(null);
      await tester.pumpAndSettle();
      sort = true;

      await tester.tap(find.byTooltip('AI tidying'));
      await tester.pumpAndSettle();
      expect(find.text('Turn off'), findsNothing);
      expect(find.text('Z.ai'), findsOneWidget);
      expect(find.text('DeepSeek'), findsOneWidget);
      await tester.tap(find.text('Claude'));
      await tester.pump();
      expect(find.text('https://api.anthropic.com/v1'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'API key'), 'sk');
      await tester.enterText(find.widgetWithText(TextField, 'Model'), 'haiku');
      await tester.pumpAndSettle();
      expect(find.text('claude-opus-5-5'), findsNothing);
      await tester.tap(find.text('claude-haiku-5-5'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(tidier.settings?.baseUrl, 'https://api.anthropic.com/v1');
      expect(tidier.settings?.apiKey, 'sk');
      expect(tidier.settings?.model, 'claude-haiku-5-5');
      expect(find.byTooltip('AI tidying'), findsNothing);

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI tidying'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Turn off'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn off'));
      await tester.pumpAndSettle();
      expect(tidier.settings, isNull);
    });
  });
}
