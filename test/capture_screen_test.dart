import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/backup.dart';
import 'package:headroom/clipboard_image_io.dart'
    show readClipboardHtml, writeClipboardImage;
import 'package:headroom/formatting.dart';
import 'package:headroom/list_settings.dart';
import 'package:headroom/main.dart';
import 'package:headroom/sidebar.dart';
import 'package:headroom/sliver_animated_reorderable_list.dart';
import 'package:headroom/thought.dart';
import 'package:headroom/thought_field.dart';
import 'package:headroom/thought_store.dart';
import 'package:headroom/tidier.dart';
import 'package:headroom/tidy_client.dart';
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
  String? clipboardHtml;
  Uint8List? copiedImage;
  var copiedTexts = <String>[];
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
    clipboardHtml = null;
    copiedImage = null;
    copiedTexts = [];
    copyFails = false;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('pasteboard'),
      (call) async => call.method == 'image' ? clipboardImage : null,
    );
    final realReadClipboardHtml = readClipboardHtml;
    readClipboardHtml = () async => clipboardHtml;
    final realWriteClipboardImage = writeClipboardImage;
    writeClipboardImage = (image) async {
      if (copyFails) throw PlatformException(code: 'denied');
      copiedImage = image;
    };
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        if (copyFails) throw PlatformException(code: 'denied');
        copiedTexts.add((call.arguments as Map)['text'] as String);
      }
      return switch (call.method) {
        'Clipboard.hasStrings' => {'value': clipboardText != null},
        'Clipboard.getData' when clipboardText != null => {
          'text': clipboardText,
        },
        _ => null,
      };
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(
        const MethodChannel('pasteboard'),
        null,
      );
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      writeClipboardImage = realWriteClipboardImage;
      readClipboardHtml = realReadClipboardHtml;
    });

    storage = InMemoryStorage(initial)..images.addAll(images);
    if (ai != null) storage.values['ai'] = jsonEncode(testAi);
    store = ThoughtStore(storage);
    await store.load();
    tidier = Tidier(
      store,
      storage,
      client: MockClient(ai ?? (_) => throw StateError('No AI set up')),
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

  ThoughtField captureField(WidgetTester tester) =>
      tester.widget<ThoughtField>(find.byType(ThoughtField).first);

  QuillEditorConfig editorConfig(WidgetTester tester) => tester
      .widget<QuillEditor>(
        find.descendant(
          of: find.byType(ThoughtField).first,
          matching: find.byType(QuillEditor),
        ),
      )
      .config;

  /// What the capture field, or [field], holds.
  String fieldText(WidgetTester tester, [Finder? field]) {
    final plain = tester
        .widget<ThoughtField>(field ?? find.byType(ThoughtField).first)
        .controller
        .document
        .toPlainText();
    return plain.substring(0, plain.length - 1);
  }

  /// Opens the keyboard on [field], as tapping it would.
  Future<void> showKeyboard(WidgetTester tester, Finder field) async {
    tester
        .state<QuillRawEditorState>(
          find.descendant(of: field, matching: find.byType(QuillRawEditor)),
        )
        .requestKeyboard();
    await tester.idle();
  }

  /// Replaces what [field] holds with [text], as the keyboard would.
  Future<void> enterText(WidgetTester tester, Finder field, String text) async {
    await showKeyboard(tester, field);
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: '$text\n',
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
    await tester.idle();
  }

  IconButton sendButton(WidgetTester tester) => tester.widget<IconButton>(
    find.widgetWithIcon(IconButton, Icons.arrow_upward_rounded),
  );

  Finder listedImage() => find.descendant(
    of: find.byType(SliverAnimatedReorderableList),
    matching: find.byType(Image),
  );

  Finder listed(String text) => find.descendant(
    of: find.byType(SliverAnimatedReorderableList),
    matching: find.text(text),
  );

  Finder inSidebar(String text) =>
      find.descendant(of: find.byType(Sidebar), matching: find.text(text));

  Finder inDialog(String text) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

  Finder checkItem(String text) =>
      find.widgetWithText(CheckboxMenuButton, text);

  /// Asks the AI for clean-ups from the sidebar, opened from the drawer on a
  /// narrow window.
  Future<void> cleanUp(WidgetTester tester) async {
    final drawer = find.byTooltip('Open navigation menu');
    if (drawer.evaluate().isNotEmpty) {
      await tester.tap(drawer);
      await tester.pumpAndSettle();
    }
    await tester.tap(inSidebar('Clean up'));
    await tester.pumpAndSettle();
  }

  /// Drags [gesture] [dy] down, drifting [dx] across, then lets go.
  Future<void> drag(
    WidgetTester tester,
    TestGesture gesture,
    double dy, {
    double dx = 0,
  }) async {
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(dx / 10, dy / 10));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> pressPaste(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  Future<void> pasteImageFromMenu(WidgetTester tester, [Finder? field]) async {
    await tester.longPress(field ?? find.byType(ThoughtField));
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

    expect(captureField(tester).focusNode.hasFocus, isTrue);
    expect(
      find.text("What's on your mind?", findRichText: true),
      findsOneWidget,
    );
    expect(find.text('What you note shows up here.'), findsOneWidget);
  });

  testWidgets('sending captures the thought and keeps the field ready', (
    tester,
  ) async {
    await pumpApp(tester);

    await enterText(tester, find.byType(ThoughtField), 'Call the garage');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    await store.flush();

    expect(find.text('Call the garage'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(fieldText(tester), isEmpty);
    expect(captureField(tester).focusNode.hasFocus, isTrue);
    expect(storage.saved.single.text, 'Call the garage');
  });

  testWidgets('a screen reader hears that the thought was noted', (
    tester,
  ) async {
    await pumpApp(tester);

    await enterText(tester, find.byType(ThoughtField), 'Call the garage');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(tester.takeAnnouncements(), [
      isAccessibilityAnnouncement('Thought noted'),
    ]);
  });

  testWidgets('the field keeps its label once it holds text', (tester) async {
    await pumpApp(tester);

    await enterText(tester, find.byType(ThoughtField), 'Buy bread');
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.byType(ThoughtField)),
      isSemantics(label: 'Thought', value: 'Buy bread'),
    );
  });

  testWidgets('a failed save is read out', (tester) async {
    await pumpApp(tester);
    storage.failWrites = true;

    await enterText(tester, find.byType(ThoughtField), 'Buy bread');
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

    await enterText(tester, find.byType(ThoughtField), 'Buy bread');
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
    expect(editorConfig(tester).textInputAction, TextInputAction.newline);
    await enterText(tester, find.byType(ThoughtField), 'Call the garage');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(store.thoughts, isEmpty);

    await enterText(
      tester,
      find.byType(ThoughtField),
      'Call the garage\nTyres',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(store.thoughts.single.text, 'Call the garage\nTyres');
    expect(fieldText(tester), isEmpty);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('Enter is left to an input method that is composing', (
    tester,
  ) async {
    await pumpApp(tester);

    await showKeyboard(tester, find.byType(ThoughtField));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'にほん\n',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 3),
      ),
    );
    await tester.pump();

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isFalse);
    expect(store.thoughts, isEmpty);

    // Quill trips over a composition still going when it is disposed.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'にほん\n',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
  }, variant: TargetPlatformVariant.desktop());

  group('back to the field', () {
    bool fieldFocused(WidgetTester tester) =>
        captureField(tester).focusNode.hasFocus;

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
      expect(fieldText(tester), isEmpty);
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
          themes: ['Errands'],
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

    expect(editorConfig(tester).textInputAction, TextInputAction.send);
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

    await enterText(tester, find.byType(ThoughtField), 'word ' * 40);
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

  testWidgets('a wide window keeps the message narrow, under the list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    await pumpApp(tester, [
      Thought(id: '2', text: 'Buy bread', createdAt: now, themes: ['Errands']),
      Thought(id: '1', text: 'Fix the build', createdAt: now, themes: ['Work']),
    ]);

    await tester.drag(find.text('Buy bread'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    final message = tester.getRect(
      find
          .descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(message.width, 480);
    expect(message.center.dx, 240 + (1200 - 240) / 2);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsNothing);
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

    await enterText(tester, find.byType(ThoughtField), 'Buy bread');
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

  testWidgets('only keyboard focus reveals the delete button', (tester) async {
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

    // As a click on the web gives it, through semantics.
    await tester.tapAt(const Offset(780, 580));
    Focus.of(tester.element(find.text('Buy bread'))).requestFocus();
    await tester.pumpAndSettle();
    expect(opacity(), 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(opacity(), 1);
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
    await enterText(tester, find.byType(ThoughtField).last, 'Buy bread');
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
    await enterText(
      tester,
      find.byType(ThoughtField).last,
      'Buy bread\nAnd milk',
    );
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

    await enterText(tester, find.byType(ThoughtField).last, 'Receipt');
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
    await pasteImageFromMenu(tester, find.byType(ThoughtField).last);

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

    expect(fieldText(tester), 'Copied from Word');
    expect(find.byTooltip('Remove image'), findsNothing);
  });

  testWidgets('pasting keeps the bold and the lists of what was copied', (
    tester,
  ) async {
    await pumpApp(tester);
    clipboardText = 'Shopping\nBread\nMilk';
    clipboardHtml =
        '<div><b>Shopping</b></div><ul><li>Bread</li><li>Milk</li></ul>';

    await pressPaste(tester);
    await tester.tap(find.byWidget(sendButton(tester)));
    await tester.pumpAndSettle();
    await store.flush();

    final thought = storage.saved.single;
    expect(thought.text, 'Shopping\n- Bread\n- Milk');
    expect(thought.delta, [
      {
        'insert': 'Shopping',
        'attributes': {'bold': true},
      },
      {'insert': '\nBread'},
      {
        'insert': '\n',
        'attributes': {'list': 'bullet'},
      },
      {'insert': 'Milk'},
      {
        'insert': '\n',
        'attributes': {'list': 'bullet'},
      },
    ]);
    expect(find.byType(FormattedText), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(FormattedText)).label,
      startsWith('Shopping\n- Bread\n- Milk\n'),
    );
  });

  testWidgets('editing keeps the formatting of a thought', (tester) async {
    await pumpApp(tester, [
      Thought(
        id: '1',
        text: 'Bread and milk',
        delta: [
          {
            'insert': 'Bread',
            'attributes': {'bold': true},
          },
          {'insert': ' and milk\n'},
        ],
        createdAt: DateTime.now(),
      ),
    ]);

    await tester.tap(find.byType(FormattedText));
    await tester.pumpAndSettle();
    final field = find.byType(ThoughtField).last;
    expect(fieldText(tester, field), 'Bread and milk');
    await enterText(tester, field, 'Bread and milk!');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(store.thoughts.single.text, 'Bread and milk!');
    expect(store.thoughts.single.delta, [
      {
        'insert': 'Bread',
        'attributes': {'bold': true},
      },
      {'insert': ' and milk!\n'},
    ]);
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
    expect(fieldText(tester), isEmpty);

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

  Finder menuItem(String text) => find.widgetWithText(MenuItemButton, text);

  testWidgets('right-clicking a listed image offers to copy it', (
    tester,
  ) async {
    await pumpReceipt(tester);

    await rightClick(tester, listedImage());
    expect(menuItem('Edit'), findsOneWidget);
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

    await tester.tap(find.byType(ThoughtField));
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
    expect(menuItem('Edit'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('right-clicking a thought opens its menu', (tester) async {
    await pumpApp(tester, [
      Thought(id: '1', text: 'Buy bread', createdAt: DateTime.now()),
    ]);

    await rightClick(tester, listed('Buy bread'));
    expect(menuItem('Edit'), findsOneWidget);
    expect(menuItem('Copy text'), findsOneWidget);
    expect(find.widgetWithText(SubmenuButton, 'Themes'), findsOneWidget);
    expect(menuItem('Pin'), findsOneWidget);
    expect(menuItem('Delete'), findsOneWidget);
    expect(menuItem('Move up'), findsNothing);
    expect(menuItem('Copy image'), findsNothing);

    await tester.tap(menuItem('Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(menuItem('Edit'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('the menu copies the text as written, not its title', (
    tester,
  ) async {
    await pumpApp(tester, [
      Thought(
        id: '1',
        text: 'Get milk, eggs and flour for the pancakes',
        title: 'Pancakes',
        createdAt: DateTime.now(),
      ),
    ]);

    await rightClick(tester, listed('Pancakes'));
    await tester.tap(menuItem('Copy text'));
    await tester.pumpAndSettle();

    expect(copiedTexts, ['Get milk, eggs and flour for the pancakes']);
    expect(menuItem('Copy text'), findsNothing);
  });

  testWidgets('a failed text copy says so', (tester) async {
    await pumpApp(tester, [
      Thought(id: '1', text: 'Buy bread', createdAt: DateTime.now()),
    ]);
    copyFails = true;

    await rightClick(tester, listed('Buy bread'));
    await tester.tap(menuItem('Copy text'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isA<PlatformException>());
    expect(find.text("Couldn't copy the text."), findsOneWidget);
  });

  testWidgets('the menu deletes a thought, with undo', (tester) async {
    await pumpApp(tester, [
      Thought(id: '1', text: 'Buy bread', createdAt: DateTime.now()),
    ]);

    await rightClick(tester, listed('Buy bread'));
    await tester.tap(menuItem('Delete'));
    await tester.pumpAndSettle();
    expect(listed('Buy bread'), findsNothing);
    expect(store.thoughts, isEmpty);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(listed('Buy bread'), findsOneWidget);
  });

  testWidgets('the menu key or Shift+F10 opens the menu', (tester) async {
    await pumpApp(tester, [
      Thought(id: '1', text: 'Buy bread', createdAt: DateTime.now()),
    ]);
    Finder inMenu(String text) =>
        find.descendant(of: menuItem(text), matching: find.text(text));

    Focus.of(tester.element(listed('Buy bread'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(inMenu('Edit'))).hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      Focus.of(tester.element(inMenu('Copy text'))).hasPrimaryFocus,
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(menuItem('Edit'), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a pinned thought stays above the days until unpinned', (
    tester,
  ) async {
    final now = DateTime.now();
    await pumpApp(tester, [
      Thought(id: '2', text: 'Buy bread', createdAt: now),
      Thought(
        id: '1',
        text: 'Water the plants',
        createdAt: now.subtract(const Duration(days: 1)),
      ),
    ]);
    double top(Finder finder) => tester.getTopLeft(finder).dy;

    await rightClick(tester, listed('Water the plants'));
    await tester.tap(menuItem('Pin'));
    await tester.pumpAndSettle();
    expect(top(find.text('Pinned')), lessThan(top(listed('Water the plants'))));
    expect(top(listed('Water the plants')), lessThan(top(find.text('Today'))));
    expect(top(find.text('Today')), lessThan(top(listed('Buy bread'))));
    // Its day heading has gone, and the thought shows its day instead.
    expect(
      find.descendant(
        of: find.ancestor(
          of: listed('Water the plants'),
          matching: find.byType(Dismissible),
        ),
        matching: find.text('Yesterday'),
      ),
      findsOneWidget,
    );
    expect(find.text('Yesterday'), findsOneWidget);
    await store.flush();
    expect(storage.saved.firstWhere((t) => t.id == '1').pinned, isTrue);

    await tester.tap(find.byTooltip('Unpin'));
    await tester.pumpAndSettle();
    expect(find.text('Pinned'), findsNothing);
    expect(top(listed('Buy bread')), lessThan(top(find.text('Yesterday'))));
    expect(
      top(find.text('Yesterday')),
      lessThan(top(listed('Water the plants'))),
    );
  });

  testWidgets('pinning moves only that thought, the others stay put', (
    tester,
  ) async {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    await pumpApp(tester, [
      Thought(id: '3', text: 'Buy bread', createdAt: now),
      Thought(id: '2', text: 'Water the plants', createdAt: yesterday),
      Thought(
        id: '1',
        text: 'Post the letter',
        createdAt: yesterday.subtract(const Duration(minutes: 1)),
      ),
    ]);
    final focus = Focus.of(tester.element(listed('Post the letter')))
      ..requestFocus();
    await tester.pump();

    store.pin('2');
    await tester.pumpAndSettle();
    expect(focus.hasPrimaryFocus, isTrue);

    store.pin('2', pinned: false);
    await tester.pumpAndSettle();
    expect(focus.hasPrimaryFocus, isTrue);
  });

  testWidgets('the edit dialog pins a thought once saved', (tester) async {
    await pumpApp(tester, [
      Thought(id: '1', text: 'Buy bread', createdAt: DateTime.now()),
    ]);

    await tester.tap(find.text('Buy bread'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pin'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Unpin'), findsOneWidget);
    expect(store.thoughts.single.pinned, isFalse);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.thoughts.single.pinned, isTrue);
    expect(find.text('Pinned'), findsOneWidget);
  });

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

    expect(
      find.text("Qu'est-ce que tu as en tête ?", findRichText: true),
      findsOneWidget,
    );
    expect(find.text("Ce que tu notes s'affiche ici."), findsOneWidget);
  });

  testWidgets('has no sidebar until a thought has a theme', (tester) async {
    await pumpApp(tester, [
      Thought(id: '1', text: 'Buy bread', createdAt: DateTime.now()),
    ]);
    expect(find.byTooltip('Open navigation menu'), findsNothing);
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('opens the settings from the toolbar, even with no thought', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('AI tidying'), findsOneWidget);
    expect(find.text('No copy saved yet'), findsOneWidget);
    expect(find.text('Restore a copy'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Restore a copy'), findsNothing);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Restore a copy'), findsNothing);
  });

  testWidgets('opens the settings from the sidebar', (tester) async {
    await pumpApp(tester, [
      Thought(
        id: '1',
        text: 'Buy bread',
        createdAt: DateTime.now(),
        themes: ['Errands'],
      ),
    ]);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Save a copy'), findsOneWidget);
  });

  testWidgets('lists the thoughts the AI will not sort under No theme', (
    tester,
  ) async {
    final now = DateTime.now();
    await pumpApp(tester, [
      Thought(id: '2', text: 'Fix the build', createdAt: now, themes: ['Work']),
      Thought(id: '1', text: 'Buy bread', createdAt: now),
    ]);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No theme'));
    await tester.pumpAndSettle();
    expect(listed('Buy bread'), findsOneWidget);
    expect(listed('Fix the build'), findsNothing);
  });

  testWidgets('opens on the theme it was left on, while it exists', (
    tester,
  ) async {
    final now = DateTime.now();
    await pumpApp(tester, [
      Thought(id: '2', text: 'Fix the build', createdAt: now, themes: ['Work']),
      Thought(id: '1', text: 'Buy bread', createdAt: now, themes: ['Errands']),
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

    store.addThemes(['Bills']);
    await reopen('Bills');
    expect(listed('Fix the build'), findsNothing);
    expect(listed('Buy bread'), findsNothing);
    expect(find.text('What you note shows up here.'), findsOneWidget);

    await reopen('Gone');
    expect(find.text('All'), findsOneWidget);
    expect(listed('Buy bread'), findsOneWidget);
  });

  testWidgets('the edit dialog ticks the themes of a thought, or a new one', (
    tester,
  ) async {
    final now = DateTime.now();
    await pumpApp(tester, [
      Thought(id: '3', text: 'Buy milk', createdAt: now, themes: ['Errands']),
      Thought(id: '2', text: 'Fix the build', createdAt: now, themes: ['Work']),
      Thought(id: '1', text: 'Buy bread', createdAt: now, themes: ['Errands']),
    ]);
    Thought bread() => store.thoughts.last;
    Future<void> toggleMenu() async {
      await tester.tap(find.byTooltip('Themes'));
      await tester.pumpAndSettle();
    }

    Future<void> openMenu() async {
      await tester.tap(find.text('Buy bread'));
      await tester.pumpAndSettle();
      await toggleMenu();
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
    await tester.tap(checkItem('Work'));
    await tester.pumpAndSettle();
    expect(checkItem('Errands'), findsOneWidget, reason: 'It stays open');
    expect(inDialog('Errands, Work'), findsOneWidget);
    await toggleMenu();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(bread().themes, ['Errands', 'Work']);
    expect(bread().themesChosen, isTrue);

    await openMenu();
    await create('Bakery');
    expect(inDialog('Errands, Work, Bakery'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(bread().themes, ['Errands', 'Work']);

    await openMenu();
    await create('errands');
    expect(inDialog('Errands, Work'), findsOneWidget);
    await toggleMenu();
    await tester.tap(checkItem('Errands'));
    await tester.pump();
    await tester.tap(checkItem('Work'));
    await tester.pumpAndSettle();
    expect(inDialog('Choose themes'), findsOneWidget);
    await toggleMenu();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(bread().themes, isEmpty);
    expect(bread().themesChosen, isTrue);
  });

  testWidgets('every thought shows its other themes, which a tap corrects', (
    tester,
  ) async {
    final now = DateTime.now();
    await pumpApp(tester, [
      Thought(id: '3', text: 'Pay rent', createdAt: now),
      Thought(id: '2', text: 'Fix the build', createdAt: now, themes: ['Work']),
      Thought(
        id: '1',
        text: 'Buy bread',
        createdAt: now,
        themes: ['Food', 'Errands'],
      ),
    ]);
    Finder themesOf(String themes) => find.descendant(
      of: find.byType(SliverAnimatedReorderableList),
      matching: find.widgetWithText(TextButton, themes),
    );
    expect(themesOf('Work'), findsOneWidget);
    expect(themesOf('Errands, Food'), findsOneWidget);
    expect(find.byTooltip('Change themes'), findsNWidgets(2));
    expect(
      find.semantics.byPredicate((node) {
        final merged = node.getSemanticsData();
        return merged.label == 'Errands, Food' &&
            merged.tooltip == 'Change themes';
      }),
      findsOne,
    );

    await tester.tap(themesOf('Errands, Food'));
    await tester.pumpAndSettle();
    await tester.tap(checkItem('Work'));
    await tester.pumpAndSettle();
    await tester.tap(themesOf('Errands, Food, Work'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(checkItem('Work'), findsNothing);
    expect(store.thoughts.last.themes, ['Food', 'Errands', 'Work']);
    expect(store.thoughts.last.themesChosen, isTrue);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(inSidebar('Work'));
    await tester.pumpAndSettle();
    expect(listed('Buy bread'), findsOneWidget);
    expect(listed('Fix the build'), findsOneWidget);
    expect(find.byTooltip('Change themes'), findsOneWidget);
    expect(themesOf('Errands, Food'), findsOneWidget);

    await tester.tap(themesOf('Errands, Food'));
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxMenuButton>(checkItem('Work')).value, isTrue);
  });

  testWidgets('the themes of a thought open a menu under them that stays put', (
    tester,
  ) async {
    final now = DateTime.now();
    await pumpApp(tester, [
      Thought(id: '2', text: 'Fix the build', createdAt: now, themes: ['Work']),
      Thought(id: '1', text: 'Buy bread', createdAt: now, themes: ['Food']),
    ]);
    final button = find.descendant(
      of: find.byType(SliverAnimatedReorderableList),
      matching: find.widgetWithText(TextButton, 'Food'),
    );
    final below = tester.getBottomLeft(button).dy;
    await tester.tap(button);
    await tester.pumpAndSettle();
    final food = tester.getTopLeft(checkItem('Food'));
    final work = tester.getTopLeft(checkItem('Work'));
    expect(food.dy, greaterThanOrEqualTo(below));
    expect(work.dy, greaterThanOrEqualTo(below));

    await tester.tap(checkItem('Work'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(checkItem('Food')), food);
    expect(tester.getTopLeft(checkItem('Work')), work);
  });

  testWidgets('renames the open theme, or joins it to another', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    await pumpApp(tester, [
      Thought(id: '2', text: 'Fix the build', createdAt: now, themes: ['Work']),
      Thought(id: '1', text: 'Buy bread', createdAt: now, themes: ['Errands']),
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
    await tester.tap(inSidebar('Errands'));
    await tester.pumpAndSettle();

    await rename('Shopping');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(inSidebar('Errands'), findsNothing);
    expect(inSidebar('Shopping'), findsOneWidget);
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
    expect(inSidebar('Shopping'), findsNothing);
    expect(listed('Buy bread'), findsOneWidget);
    expect(listed('Fix the build'), findsOneWidget);
    expect(store.thoughts.map((t) => t.themes), [
      ['Work'],
      ['Work'],
    ]);
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
        Thought(id: '3', text: 'Read Dune', createdAt: now, themes: ['Études']),
        Thought(
          id: '2',
          text: 'Fix the build',
          createdAt: now,
          themes: ['Work'],
        ),
        Thought(
          id: '1',
          text: 'Buy bread',
          createdAt: now,
          themes: ['Errands'],
        ),
      ]);
      order = () {
        final themes = [
          'Errands',
          'Études',
          'Work',
          'Bills',
        ].where((theme) => inSidebar(theme).evaluate().isNotEmpty);
        return themes.toList()..sort(
          (a, b) => tester
              .getTopLeft(inSidebar(a))
              .dy
              .compareTo(tester.getTopLeft(inSidebar(b)).dy),
        );
      };
    }

    Future<List<String>> savedOrder() async {
      final reopened = ListSettings(storage);
      await reopened.load();
      return reopened.themeOrder;
    }

    testWidgets('moves a theme dragged with a mouse or after a long press', (
      tester,
    ) async {
      await pumpThemes(tester);
      expect(order(), ['Errands', 'Études', 'Work']);

      final mouse = await tester.startGesture(
        tester.getCenter(inSidebar('Work')),
        kind: PointerDeviceKind.mouse,
      );
      await drag(tester, mouse, -100);
      expect(order(), ['Work', 'Errands', 'Études']);
      expect(await savedOrder(), ['Work', 'Errands', 'Études']);

      final finger = await tester.startGesture(
        tester.getCenter(inSidebar('Errands')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await drag(tester, finger, 50);
      expect(order(), ['Work', 'Études', 'Errands']);

      store.chooseThemes('4', ['Bills']);
      await tester.pumpAndSettle();
      expect(order(), ['Work', 'Études', 'Errands', 'Bills']);
    });

    testWidgets('a right-click renames or moves a theme, not All', (
      tester,
    ) async {
      await pumpThemes(tester);

      await rightClick(tester, inSidebar('All'));
      expect(menuItem('Rename theme'), findsNothing);

      await rightClick(tester, inSidebar('Errands'));
      expect(
        tester.widget<MenuItemButton>(menuItem('Move up')).onPressed,
        isNull,
      );
      await tester.tap(menuItem('Move down'));
      await tester.pumpAndSettle();
      expect(order(), ['Études', 'Errands', 'Work']);

      await rightClick(tester, inSidebar('Work'));
      await tester.tap(menuItem('Rename theme'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Theme name'),
        'Bills',
      );
      await tester.pump();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      expect(order(), ['Études', 'Errands', 'Bills']);
      expect(listSettings.theme, isNull);
    });

    testWidgets('deletes a theme, whose thoughts stay, until undone', (
      tester,
    ) async {
      await pumpThemes(tester);
      await tester.tap(inSidebar('Work'));
      await tester.pumpAndSettle();

      await rightClick(tester, inSidebar('Work'));
      await tester.tap(menuItem('Delete theme'));
      await tester.pumpAndSettle();
      expect(order(), ['Errands', 'Études']);
      expect(listSettings.theme, isNull);
      expect(listed('Fix the build'), findsOneWidget);
      expect(store.thoughts.firstWhere((t) => t.id == '2').themes, isEmpty);
      expect(find.text('Theme deleted. Its thoughts stay.'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(order(), ['Errands', 'Études', 'Work']);
      expect(listSettings.theme, 'Work');
      expect(listed('Fix the build'), findsOneWidget);
    });

    testWidgets('keeps a theme once its last thought is deleted', (
      tester,
    ) async {
      await pumpThemes(tester);
      await tester.tap(inSidebar('Work'));
      await tester.pumpAndSettle();

      await tester.tap(listed('Fix the build'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(listSettings.theme, 'Work');
      expect(find.text('What you note shows up here.'), findsOneWidget);

      await tester.tap(inSidebar('All'));
      await tester.pumpAndSettle();
      expect(order(), ['Errands', 'Études', 'Work']);
    });

    testWidgets('counts the thoughts of each theme, not of All', (
      tester,
    ) async {
      await pumpThemes(tester);
      store.chooseThemes('1', ['Errands', 'Work']);
      store.addThemes(['Bills']);
      await tester.pumpAndSettle();
      await tester.tap(inSidebar('Work'));
      await tester.pumpAndSettle();

      String count(String entry) => tester.getSemantics(inSidebar(entry)).value;
      expect(count('All'), isEmpty);
      expect(count('Work'), '2 thoughts');
      expect(count('Errands'), '1 thought');
      expect(count('Bills'), isEmpty);
      expect(count('No theme'), '1 thought');

      final two = find.text('2').hitTestable();
      expect(two, findsOneWidget);
      expect(
        tester.getTopRight(two).dx,
        tester.getTopRight(find.text('1').hitTestable().first).dx,
      );
      expect(
        tester.getTopRight(find.byTooltip('Rename theme')).dx,
        lessThanOrEqualTo(tester.getTopLeft(two).dx),
      );

      await tester.tapAt(
        Offset(
          tester.getCenter(two).dx,
          tester.getCenter(inSidebar('Errands')).dy,
        ),
      );
      await tester.pumpAndSettle();
      expect(listSettings.theme, 'Errands');
    });

    testWidgets('creates a theme, which opens empty', (tester) async {
      await pumpThemes(tester);
      Future<void> create(String name) async {
        await tester.tap(inSidebar('New theme'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Theme name'),
          name,
        );
        await tester.pump();
        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();
      }

      await create('Bills');
      expect(order(), ['Bills', 'Errands', 'Études', 'Work']);
      expect(listSettings.theme, 'Bills');
      expect(find.text('What you note shows up here.'), findsOneWidget);

      await create('work');
      expect(listSettings.theme, 'Work');
      expect(listed('Fix the build'), findsOneWidget);
      expect(store.themes, hasLength(4));
    });

    testWidgets('a click that wobbles still opens the theme', (tester) async {
      await pumpThemes(tester);

      final mouse = await tester.startGesture(
        tester.getCenter(inSidebar('Work')),
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

      Focus.of(tester.element(inSidebar('Errands'))).requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(order(), ['Études', 'Errands', 'Work']);
      expect(
        Focus.of(tester.element(inSidebar('Errands'))).hasPrimaryFocus,
        isTrue,
      );

      tester.semantics.customAction(
        find.semantics.byPredicate(
          (node) =>
              node.label == 'Work' &&
              node.getSemanticsData().hasAction(SemanticsAction.customAction),
        ),
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
      await tester.tap(inSidebar('Errands'));
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

  group("a theme's thoughts", () {
    Future<void> pumpTheme(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));
      await pumpApp(tester, [
        Thought(
          id: '4',
          text: 'Fix the build',
          createdAt: now,
          themes: ['Work'],
        ),
        Thought(
          id: '3',
          text: 'Buy bread',
          createdAt: ago(1),
          themes: ['Errands'],
        ),
        Thought(
          id: '2',
          text: 'Post the letter',
          createdAt: ago(2),
          themes: ['Errands'],
        ),
        Thought(
          id: '1',
          text: 'Water the plants',
          createdAt: ago(3),
          themes: ['Errands'],
        ),
      ]);
      await tester.tap(inSidebar('Errands'));
      await tester.pumpAndSettle();
    }

    List<String> order(WidgetTester tester) {
      final texts = [
        'Call mum',
        'Fix the build',
        'Buy bread',
        'Post the letter',
        'Water the plants',
      ].where((text) => listed(text).evaluate().isNotEmpty);
      return texts.toList()..sort(
        (a, b) => tester
            .getTopLeft(listed(a))
            .dy
            .compareTo(tester.getTopLeft(listed(b)).dy),
      );
    }

    Future<List<String>> savedOrder() async {
      await store.flush();
      final errands =
          storage.saved.where((t) => t.themes.contains('Errands')).toList()
            ..sort(
              (a, b) => b.rankIn('Errands').compareTo(a.rankIn('Errands')),
            );
      return [for (final t in errands) t.text];
    }

    Future<TestGesture> hoveringMouse(WidgetTester tester, String text) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: tester.getCenter(listed(text)));
      await tester.pump();
      return mouse;
    }

    testWidgets('move when dragged with a mouse or after a long press', (
      tester,
    ) async {
      await pumpTheme(tester);
      expect(order(tester), [
        'Buy bread',
        'Post the letter',
        'Water the plants',
      ]);

      final mouse = await hoveringMouse(tester, 'Water the plants');
      await mouse.down(tester.getCenter(listed('Water the plants')));
      // Across first, as a hand does, which must not swipe it away.
      await mouse.moveBy(const Offset(4, 0));
      await tester.pump();
      await drag(tester, mouse, -200, dx: 30);
      expect(order(tester), [
        'Water the plants',
        'Buy bread',
        'Post the letter',
      ]);

      final finger = await tester.startGesture(
        tester.getCenter(listed('Buy bread')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await drag(tester, finger, 200);
      expect(order(tester), [
        'Water the plants',
        'Post the letter',
        'Buy bread',
      ]);
      expect(await savedOrder(), [
        'Water the plants',
        'Post the letter',
        'Buy bread',
      ]);
      expect(store.thoughts, hasLength(4));
    });

    testWidgets('a new thought comes in at the top', (tester) async {
      await pumpTheme(tester);
      store.reorder('Errands', ['1', '3', '2']);
      await tester.pumpAndSettle();

      await enterText(tester, find.byType(ThoughtField), 'Call mum');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      store.chooseThemes(store.thoughts.first.id, ['Errands']);
      await tester.pumpAndSettle();

      expect(order(tester), [
        'Call mum',
        'Water the plants',
        'Buy bread',
        'Post the letter',
      ]);
    });

    testWidgets('keep to their day in the list of every thought', (
      tester,
    ) async {
      await pumpTheme(tester);
      store.reorder('Errands', ['1', '3', '2']);
      await tester.tap(inSidebar('All'));
      await tester.pumpAndSettle();

      final mouse = await hoveringMouse(tester, 'Water the plants');
      await mouse.down(tester.getCenter(listed('Water the plants')));
      await drag(tester, mouse, -200);

      expect(order(tester), [
        'Fix the build',
        'Buy bread',
        'Post the letter',
        'Water the plants',
      ]);
    });

    testWidgets('a finger still swipes one away', (tester) async {
      await pumpTheme(tester);

      await tester.drag(listed('Post the letter'), const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(listed('Post the letter'), findsNothing);
      expect(store.thoughts, hasLength(3));
    });

    testWidgets('a delete button goes away with the mouse', (tester) async {
      await pumpTheme(tester);
      double opacity(String text) => tester
          .widget<AnimatedOpacity>(
            find
                .ancestor(
                  of: find.descendant(
                    of: find.ancestor(
                      of: listed(text),
                      matching: find.byType(Dismissible),
                    ),
                    matching: find.byTooltip('Delete'),
                  ),
                  matching: find.byType(AnimatedOpacity),
                )
                .first,
          )
          .opacity;

      final mouse = await hoveringMouse(tester, 'Buy bread');
      await tester.pumpAndSettle();
      expect(opacity('Buy bread'), 1);

      await mouse.moveTo(tester.getCenter(listed('Post the letter')));
      await tester.pumpAndSettle();
      expect(opacity('Buy bread'), 0);
      expect(opacity('Post the letter'), 1);

      // Moved, it leaves the list for a while, and comes back under the mouse.
      await mouse.down(tester.getCenter(listed('Post the letter')));
      await drag(tester, mouse, -100);
      expect(order(tester).first, 'Post the letter');
      await mouse.moveTo(tester.getCenter(listed('Water the plants')));
      await tester.pumpAndSettle();
      expect(opacity('Post the letter'), 0);
      expect(opacity('Water the plants'), 1);
    }, variant: TargetPlatformVariant.desktop());

    testWidgets('a click that wobbles still opens the thought', (tester) async {
      await pumpTheme(tester);

      final mouse = await hoveringMouse(tester, 'Post the letter');
      await mouse.down(tester.getCenter(listed('Post the letter')));
      await mouse.moveBy(const Offset(0, 4));
      await mouse.up();
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(await savedOrder(), [
        'Buy bread',
        'Post the letter',
        'Water the plants',
      ]);
    });

    testWidgets('the menu moves a thought and changes its themes', (
      tester,
    ) async {
      await pumpTheme(tester);

      await rightClick(tester, listed('Buy bread'));
      expect(
        tester.widget<MenuItemButton>(menuItem('Move up')).onPressed,
        isNull,
      );
      await tester.tap(menuItem('Move down'));
      await tester.pumpAndSettle();
      expect(order(tester), [
        'Post the letter',
        'Buy bread',
        'Water the plants',
      ]);

      await rightClick(tester, listed('Buy bread'));
      await tester.tap(find.widgetWithText(SubmenuButton, 'Themes'));
      await tester.pumpAndSettle();
      await tester.tap(checkItem('Work'));
      await tester.pumpAndSettle();
      expect(store.thoughts.firstWhere((t) => t.id == '3').themes, [
        'Errands',
        'Work',
      ]);
      expect(checkItem('Work'), findsOneWidget);
    });

    testWidgets('a screen reader or the keyboard moves a thought', (
      tester,
    ) async {
      await pumpTheme(tester);

      Focus.of(tester.element(listed('Buy bread'))).requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(order(tester), [
        'Post the letter',
        'Buy bread',
        'Water the plants',
      ]);
      expect(
        Focus.of(tester.element(listed('Buy bread'))).hasPrimaryFocus,
        isTrue,
      );

      tester.semantics.customAction(
        find.semantics.byPredicate(
          (node) =>
              node.label.startsWith('Water the plants') &&
              node.getSemanticsData().hasAction(SemanticsAction.customAction),
        ),
        const CustomSemanticsAction(label: 'Move up'),
      );
      await tester.pumpAndSettle();
      expect(order(tester), [
        'Post the letter',
        'Water the plants',
        'Buy bread',
      ]);
      expect(await savedOrder(), [
        'Post the letter',
        'Water the plants',
        'Buy bread',
      ]);
    });

    testWidgets('a pinned one stays above the others, which move below it', (
      tester,
    ) async {
      await pumpTheme(tester);

      tester.semantics.customAction(
        find.semantics.byPredicate(
          (node) =>
              node.label.startsWith('Water the plants') &&
              node.getSemanticsData().hasAction(SemanticsAction.customAction),
        ),
        const CustomSemanticsAction(label: 'Pin'),
      );
      await tester.pumpAndSettle();
      expect(order(tester), [
        'Water the plants',
        'Buy bread',
        'Post the letter',
      ]);

      Focus.of(tester.element(listed('Buy bread'))).requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(order(tester), [
        'Water the plants',
        'Buy bread',
        'Post the letter',
      ]);

      final mouse = await hoveringMouse(tester, 'Post the letter');
      await mouse.down(tester.getCenter(listed('Post the letter')));
      await drag(tester, mouse, -300);
      expect(order(tester), [
        'Water the plants',
        'Post the letter',
        'Buy bread',
      ]);
      // The pinned thought keeps its own place among the others.
      expect(await savedOrder(), [
        'Post the letter',
        'Buy bread',
        'Water the plants',
      ]);

      await enterText(tester, find.byType(ThoughtField), 'Call mum');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      store.chooseThemes(store.thoughts.first.id, ['Errands']);
      await tester.pumpAndSettle();
      expect(order(tester), [
        'Water the plants',
        'Call mum',
        'Post the letter',
        'Buy bread',
      ]);

      store.pin('1', pinned: false);
      await tester.pumpAndSettle();
      expect(order(tester), [
        'Call mum',
        'Post the letter',
        'Buy bread',
        'Water the plants',
      ]);
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
            themes: ['Work'],
          ),
          Thought(
            id: '3',
            text: 'Buy milk',
            createdAt: now,
            themes: ['Errands'],
          ),
          Thought(id: '2', text: 'milk!!', createdAt: now, themes: ['Errands']),
          Thought(
            id: '1',
            text: 'Read Dune',
            createdAt: now.subtract(const Duration(days: 3)),
            themes: ['Études'],
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
      expect(find.text('Clean-up'), findsNothing);
      await cleanUp(tester);
      double top(String text) => tester.getTopLeft(inSidebar(text)).dy;
      expect(find.byTooltip('Open navigation menu'), findsNothing);
      expect(top('All'), lessThan(top('Errands')));
      expect(top('Errands'), lessThan(top('Études')));
      expect(top('Études'), lessThan(top('Work')));
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Clean-up'), findsOneWidget);

      await tester.tap(inSidebar('Work'));
      await tester.pumpAndSettle();
      expect(listed('Fix the build'), findsOneWidget);
      expect(listed('Buy milk'), findsNothing);
      expect(listed('Read Dune'), findsNothing);
      expect(find.text('Today'), findsNothing);
      expect(find.text('Clean-up'), findsNothing);

      await tester.tap(inSidebar('Errands'));
      await tester.pumpAndSettle();
      expect(listed('Buy milk'), findsOneWidget);
      expect(listed('Fix the build'), findsNothing);
      expect(find.text('Clean-up'), findsOneWidget);
      final reopened = ListSettings(storage);
      await reopened.load();
      expect(reopened.theme, 'Errands');

      await tester.tap(inSidebar('All'));
      await tester.pumpAndSettle();
      expect(listed('Fix the build'), findsOneWidget);
      expect(listed('Read Dune'), findsOneWidget);
    });

    testWidgets(
      'a thought noted in a theme stays there, in the themes the AI adds too',
      (tester) async {
        final now = DateTime.now();
        final answer = Completer<void>();
        late http.Request asked;
        await pumpApp(
          tester,
          [
            Thought(
              id: '2',
              text: 'Fix the build',
              createdAt: now,
              themes: ['Work'],
            ),
            Thought(
              id: '1',
              text: 'Buy bread',
              createdAt: now,
              themes: ['Errands'],
            ),
          ],
          const {},
          (request) async {
            asked = request;
            await answer.future;
            return describedAs(['Errands']);
          },
        );
        expect(find.text('All'), findsOneWidget);
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        await tester.tap(inSidebar('Work'));
        await tester.pumpAndSettle();
        expect(find.text('Work'), findsOneWidget);
        expect(listed('Fix the build'), findsOneWidget);
        expect(listed('Buy bread'), findsNothing);

        await enterText(tester, find.byType(ThoughtField), 'Buy milk');
        await tester.testTextInput.receiveAction(TextInputAction.send);
        // Not pumpAndSettle: the thought's spinner runs until the AI replies.
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(listed('Buy milk'), findsOneWidget);

        expect(store.thoughts.first.themes, ['Work']);
        expect(sentInput(asked)['notedIn'], ['Work']);

        answer.complete();
        await tester.pumpAndSettle();
        expect(store.thoughts.first.themes, ['Work', 'Errands']);
        expect(listed('Buy milk'), findsOneWidget);
        expect(listed('Fix the build'), findsOneWidget);

        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        await tester.tap(inSidebar('Errands'));
        await tester.pumpAndSettle();
        expect(listed('Buy milk'), findsOneWidget);
        expect(listed('Buy bread'), findsOneWidget);
      },
    );

    testWidgets('merges the thoughts it finds repeated, until undone', (
      tester,
    ) async {
      final now = DateTime.now();
      await pumpApp(
        tester,
        [
          Thought(
            id: '2',
            text: 'Buy milk',
            createdAt: now,
            themes: ['Errands'],
          ),
          Thought(id: '1', text: 'milk!!', createdAt: now, themes: ['Errands']),
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
      await cleanUp(tester);

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
            themes: ['Fun'],
          ),
          Thought(
            id: '1',
            text: 'Dentist on Monday',
            createdAt: now,
            themes: ['Health'],
          ),
        ],
        const {},
        (request) async => chatReply({
          'themes': {},
          'outdated': [1, 2],
        }),
      );
      await cleanUp(tester);

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
        [],
        const {},
        (request) async => refuse
            ? http.Response(
                jsonEncode({
                  'error': {'code': '1113', 'message': 'Insufficient balance.'},
                }),
                429,
              )
            : describedAs(['Errands']),
      );
      await enterText(tester, find.byType(ThoughtField), 'Buy bread');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
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
      expect(store.thoughts.single.themes, ['Errands']);
    });

    testWidgets('lists the title and subtasks the AI gives a thought', (
      tester,
    ) async {
      await pumpApp(
        tester,
        [],
        const {},
        (request) async => describedAs(
          ['Errands'],
          title: 'Groceries',
          subtasks: ['Bread', 'Milk'],
        ),
      );

      await enterText(
        tester,
        find.byType(ThoughtField),
        'Bread and milk for the week',
      );
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      expect(listed('Groceries'), findsOneWidget);
      expect(listed('Bread and milk for the week'), findsNothing);
      expect(
        tester.getSemantics(
          find.ancestor(
            of: listed('Milk'),
            matching: find.byType(MergeSemantics),
          ),
        ),
        isSemantics(
          label: 'Milk',
          hasCheckedState: true,
          isChecked: false,
          hasTapAction: true,
        ),
      );

      await tester.tap(listed('Milk'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(store.thoughts.single.subtasks.map((s) => s.done), [false, true]);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(store.thoughts.single.subtasks.map((s) => s.done), [true, true]);

      await tester.tap(listed('Groceries'));
      await tester.pumpAndSettle();
      expect(
        fieldText(tester, find.byType(ThoughtField).last),
        'Bread and milk for the week',
      );
    });

    testWidgets('a clean-up says what it found outside the open theme', (
      tester,
    ) async {
      final now = DateTime.now();
      var outdated = <int>[];
      await pumpApp(
        tester,
        [
          Thought(
            id: '2',
            text: 'Fix the build',
            createdAt: now,
            themes: ['Work'],
          ),
          Thought(
            id: '1',
            text: 'Dentist on Monday',
            createdAt: now,
            themes: ['Health'],
          ),
        ],
        const {},
        (request) async => chatReply({'outdated': outdated}),
      );
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(inSidebar('Work'));
      await tester.pumpAndSettle();

      await cleanUp(tester);
      expect(find.text('No repeated or out-of-date thoughts.'), findsOneWidget);

      outdated = [2];
      await cleanUp(tester);
      expect(find.text('1 suggestion, in All'), findsOneWidget);
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();
      expect(listed('Fix the build'), findsOneWidget);
      expect(find.text('This thought looks out of date:'), findsOneWidget);
    });

    testWidgets('what a clean-up found elsewhere goes away on its own', (
      tester,
    ) async {
      final now = DateTime.now();
      await pumpApp(
        tester,
        [
          Thought(
            id: '2',
            text: 'Fix the build',
            createdAt: now,
            themes: ['Work'],
          ),
          Thought(
            id: '1',
            text: 'Dentist on Monday',
            createdAt: now,
            themes: ['Health'],
          ),
        ],
        const {},
        (request) async => chatReply({
          'outdated': [2],
        }),
      );
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(inSidebar('Work'));
      await tester.pumpAndSettle();

      await cleanUp(tester);
      expect(find.text('Show'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Show'), findsNothing);
    });

    testWidgets('is set up in the settings', (tester) async {
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
            : describedAs(['Errands']),
      );
      await tidier.configure(null);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Clean up'), findsNothing);

      await tester.tap(find.byTooltip('Settings'));
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
      await tester.ensureVisible(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(tidier.settings?.baseUrl, 'https://api.anthropic.com/v1');
      expect(tidier.settings?.apiKey, 'sk');
      expect(tidier.settings?.model, 'claude-haiku-5-5');
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );
      expect(find.text('Turn off'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Clean up'), findsOneWidget);
      expect(store.thoughts.single.themes, isEmpty);

      await enterText(tester, find.byType(ThoughtField), 'Call the garage');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(store.thoughts.first.themes, ['Errands']);
      expect(find.byTooltip('Settings'), findsNothing);

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(inSidebar('Clean up'), findsOneWidget);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Turn off'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn off'));
      await tester.pumpAndSettle();
      expect(tidier.settings, isNull);
      expect(find.text('Turn off'), findsNothing);
      expect(find.text('claude-haiku-5-5'), findsNothing);
    });

    testWidgets('its settings show the AI a restored backup set up', (
      tester,
    ) async {
      await pumpApp(
        tester,
        [],
        const {},
        (request) async => http.Response(jsonEncode({'data': []}), 200),
      );
      await tidier.configure(null);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Turn off'), findsNothing);

      await tidier.restore(
        const AiSettings(
          baseUrl: 'https://api.mistral.ai/v1',
          apiKey: '',
          model: 'mistral-small',
        ),
        [],
      );
      await tester.pumpAndSettle();

      expect(find.text('https://api.mistral.ai/v1'), findsOneWidget);
      expect(find.text('mistral-small'), findsOneWidget);
      expect(find.text('Turn off'), findsOneWidget);
    });

    testWidgets('shows a thought is being sorted until the AI replies', (
      tester,
    ) async {
      final reply = Completer<http.Response>();
      await pumpApp(tester, [], const {}, (request) => reply.future);

      await enterText(tester, find.byType(ThoughtField), 'Buy bread');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(listed('Tidying'), findsOneWidget);

      reply.complete(describedAs(['Errands']));
      await tester.pumpAndSettle();
      expect(listed('Tidying'), findsNothing);
      expect(listed('Errands'), findsOneWidget);
    });
  });
}
