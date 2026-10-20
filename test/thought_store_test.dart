import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/thought.dart';
import 'package:headroom/thought_store.dart';

import 'in_memory_storage.dart';

void main() {
  group('ThoughtStore', () {
    late InMemoryStorage storage;
    late ThoughtStore store;

    setUp(() {
      storage = InMemoryStorage();
      store = ThoughtStore(storage);
    });

    test('adds trimmed thoughts, newest first, and persists them', () async {
      store.add('  first ');
      store.add('second');
      await store.flush();

      expect(store.thoughts.map((t) => t.text), ['second', 'first']);
      expect(storage.saved.map((t) => t.text), ['second', 'first']);
    });

    test('ignores blank input without an image', () {
      expect(store.add('   \n '), isNull);
      expect(store.thoughts, isEmpty);
    });

    test('accepts images without text', () async {
      final first = await store.saveImage(Uint8List.fromList([1]));
      final second = await store.saveImage(Uint8List.fromList([2]));
      store.add(' ', images: [first, second]);
      await store.flush();

      expect(storage.saved.single.text, isEmpty);
      expect(storage.saved.single.images, [first, second]);
    });

    test('refuses an update that would leave neither text nor image', () {
      final withImage = store.add('caption', images: ['photo'])!;
      final textOnly = store.add('note')!;

      store
        ..update(withImage.id, text: '', images: ['photo'])
        ..update(textOnly.id, text: '', images: []);

      expect(store.thoughts.map((t) => t.text), ['note', '']);
    });

    test('update adds and removes images', () {
      final thought = store.add('note')!;

      store.update(thought.id, text: 'note', images: ['first', 'second']);
      expect(store.thoughts.single.images, ['first', 'second']);

      store.update(thought.id, text: 'note', images: ['second']);
      expect(store.thoughts.single.images, ['second']);

      store.update(thought.id, text: 'note', images: []);
      expect(store.thoughts.single.images, isEmpty);
    });

    test('load drops images that no thought uses', () async {
      final used = await storage.saveImage(Uint8List.fromList([1]));
      await storage.saveImage(Uint8List.fromList([2]));
      storage.saved = [
        Thought(id: '1', text: '', images: [used], createdAt: DateTime(2026)),
      ];

      await store.load();

      expect(storage.images.keys, [used]);
    });

    test('restores a removed thought at its old position', () async {
      store
        ..add('a')
        ..add('b')
        ..add('c');
      final b = store.thoughts[1];

      final index = store.remove(b.id);
      expect(store.thoughts.map((t) => t.text), ['c', 'a']);

      store.restore(b, index);
      await store.flush();
      expect(storage.saved.map((t) => t.text), ['c', 'b', 'a']);
    });

    test('new text drops the theme, new images keep it', () {
      final thought = store.add('Buy bread')!;
      store.setThemes({thought.id: 'Errands', 'gone': 'Nowhere'});
      expect(store.thoughts.single.theme, 'Errands');

      store.update(thought.id, text: 'Buy bread ', images: ['receipt']);
      expect(store.thoughts.single.theme, 'Errands');

      store.update(thought.id, text: 'Bake bread', images: ['receipt']);
      expect(store.thoughts.single.theme, isNull);
    });

    test('keeps a chosen theme, even through new text and the AI', () {
      final thought = store.add('Buy bread')!;
      store.chooseTheme(thought.id, 'Bakery');

      store.setThemes({thought.id: 'Errands'});
      store.update(thought.id, text: 'Bake bread', images: []);
      expect(store.thoughts.single.theme, 'Bakery');
      expect(store.thoughts.single.themeChosen, isTrue);

      store.chooseTheme(thought.id, null);
      expect(store.thoughts.single.theme, isNull);
      expect(store.thoughts.single.themeChosen, isFalse);
      store.setThemes({thought.id: 'Errands'});
      expect(store.thoughts.single.theme, 'Errands');
    });

    test('renames a theme, which may join another', () async {
      store
        ..add('Fix the build')
        ..add('Buy milk')
        ..add('Buy bread');
      final [bread, milk, build] = store.thoughts;
      store
        ..setThemes({bread.id: 'Errands', build.id: 'Work'})
        ..chooseTheme(milk.id, 'Errands');

      store.renameTheme('Errands', 'Shopping');
      expect(store.thoughts.map((t) => t.theme), [
        'Shopping',
        'Shopping',
        'Work',
      ]);
      expect(store.thoughts.map((t) => t.themeChosen), [false, true, false]);

      store.renameTheme('Shopping', 'Work');
      await store.flush();
      expect(storage.saved.map((t) => t.theme), ['Work', 'Work', 'Work']);
    });

    test('merges thoughts into the newest and unmerges them', () async {
      store
        ..add('milk', images: ['carton'])
        ..add('Call the garage')
        ..add('Buy milk', images: ['list', 'carton']);
      final [newest, middle, oldest] = store.thoughts;
      store.setThemes({newest.id: 'Errands'});

      final merged = store.merge([oldest.id, newest.id], ' Buy milk ')!;
      await store.flush();

      expect(storage.saved.map((t) => t.text), ['Buy milk', 'Call the garage']);
      final kept = store.thoughts.first;
      expect(kept.id, newest.id);
      expect(kept.createdAt, newest.createdAt);
      expect(kept.theme, 'Errands');
      expect(kept.images, ['list', 'carton']);

      store.unmerge(merged);
      await store.flush();
      expect(storage.saved.map((t) => t.id), [newest.id, middle.id, oldest.id]);
      expect(storage.saved.first.text, 'Buy milk');
      expect(storage.saved.last.images, ['carton']);
    });

    test('merges nothing when fewer than two thoughts are left', () {
      final thought = store.add('milk')!;

      expect(store.merge([thought.id, 'deleted'], 'Buy milk'), isNull);
      expect(store.thoughts.single.text, 'milk');
    });

    test('updates text but keeps the original date', () async {
      final thought = store.add('draft')!;
      store.update(thought.id, text: ' final ', images: []);
      await store.flush();

      expect(storage.saved.single.text, 'final');
      expect(storage.saved.single.createdAt, thought.createdAt);
    });

    test(
      'flags a failed write and clears the flag once a write succeeds',
      () async {
        final reported = <FlutterErrorDetails>[];
        final previous = FlutterError.onError;
        FlutterError.onError = reported.add;
        addTearDown(() => FlutterError.onError = previous);

        storage.failWrites = true;
        store.add('lost?');
        await store.flush();
        expect(store.saveFailed, isTrue);
        expect(reported, hasLength(1));

        storage.failWrites = false;
        store.add('retry');
        await store.flush();
        expect(store.saveFailed, isFalse);
        expect(storage.saved.map((t) => t.text), ['retry', 'lost?']);
      },
    );
  });
}
