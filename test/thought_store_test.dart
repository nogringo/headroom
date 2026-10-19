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

    test('accepts an image without text', () async {
      final image = await store.saveImage(Uint8List.fromList([1]));
      store.add(' ', image: image);
      await store.flush();

      expect(storage.saved.single.text, isEmpty);
      expect(storage.saved.single.image, image);
    });

    test('refuses an update that would leave neither text nor image', () {
      final withImage = store.add('caption', image: 'photo')!;
      final textOnly = store.add('note')!;

      store
        ..update(withImage.id, text: '', image: 'photo')
        ..update(textOnly.id, text: '', image: null);

      expect(store.thoughts.map((t) => t.text), ['note', '']);
    });

    test('update adds, replaces and removes the image', () {
      final thought = store.add('note')!;

      store.update(thought.id, text: 'note', image: 'first');
      expect(store.thoughts.single.image, 'first');

      store.update(thought.id, text: 'note', image: 'second');
      expect(store.thoughts.single.image, 'second');

      store.update(thought.id, text: 'note', image: null);
      expect(store.thoughts.single.image, isNull);
    });

    test('load drops images that no thought uses', () async {
      final used = await storage.saveImage(Uint8List.fromList([1]));
      await storage.saveImage(Uint8List.fromList([2]));
      storage.saved = [
        Thought(id: '1', text: '', image: used, createdAt: DateTime(2026)),
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

    test('updates text but keeps the original date', () async {
      final thought = store.add('draft')!;
      store.update(thought.id, text: ' final ', image: null);
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
