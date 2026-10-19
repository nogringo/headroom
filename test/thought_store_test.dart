import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
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

    test('ignores blank input', () {
      expect(store.add('   \n '), isNull);
      expect(store.thoughts, isEmpty);
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
      store.update(thought.id, ' final ');
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
