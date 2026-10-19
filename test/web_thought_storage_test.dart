@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/thought.dart';
import 'package:headroom/web_thought_storage.dart';
import 'package:web/web.dart' as web;

void main() {
  late WebThoughtStorage storage;

  setUp(() {
    storage = WebThoughtStorage(
      key: 'headroom.test',
      database: 'headroom-test',
    );
  });

  tearDown(() {
    web.window.localStorage.removeItem(storage.key);
    web.window.indexedDB.deleteDatabase(storage.database);
  });

  test('round-trips thoughts through localStorage', () async {
    expect(await storage.read(), isEmpty);

    final thought = Thought(
      id: '1',
      text: 'Rappeler le garagiste',
      image: 'photo',
      createdAt: DateTime(2026, 10, 19, 9, 30),
    );
    await storage.write([thought]);
    final loaded = await WebThoughtStorage(key: storage.key).read();

    expect(loaded.single.text, thought.text);
    expect(loaded.single.image, 'photo');
    expect(loaded.single.createdAt, thought.createdAt);
  });

  test('stores images in IndexedDB and deletes the ones not kept', () async {
    final kept = await storage.saveImage(Uint8List.fromList([1, 2, 3]));
    final dropped = await storage.saveImage(Uint8List.fromList([4, 5]));

    await storage.deleteImagesExcept({kept});

    expect(await storage.readImage(kept), [1, 2, 3]);
    await expectLater(storage.readImage(dropped), throwsStateError);
  });
}
