@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/file_thought_storage.dart';
import 'package:headroom/thought.dart';

void main() {
  late Directory directory;
  late FileThoughtStorage storage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('headroom');
    storage = FileThoughtStorage(directory);
  });

  tearDown(() => directory.delete(recursive: true));

  test('round-trips thoughts and replaces the previous file', () async {
    expect(await storage.read(), isEmpty);

    final first = Thought(
      id: '1',
      text: 'Call the garage',
      createdAt: DateTime(2026, 10, 19, 9, 30),
    );
    final second = Thought(
      id: '2',
      text: '',
      images: ['photo', 'sketch'],
      createdAt: DateTime(2026, 10, 19, 10),
    );
    await storage.write([first]);
    await storage.write([second, first]);
    final loaded = await storage.read();

    expect(loaded.map((t) => t.text), ['', 'Call the garage']);
    expect(loaded.map((t) => t.images), [
      ['photo', 'sketch'],
      isEmpty,
    ]);
    expect(loaded.last.createdAt, first.createdAt);
    expect(File('${directory.path}/thoughts.json.tmp').existsSync(), isFalse);
  });

  test('stores images and deletes the ones no longer kept', () async {
    final kept = await storage.saveImage(Uint8List.fromList([1, 2, 3]));
    final dropped = await storage.saveImage(Uint8List.fromList([4, 5]));
    expect(kept, isNot(dropped));

    await storage.deleteImagesExcept({kept});

    expect(await storage.readImage(kept), [1, 2, 3]);
    await expectLater(storage.readImage(dropped), throwsA(isA<IOException>()));
  });

  test('stores the same image once, under the same name', () async {
    final first = await storage.saveImage(Uint8List.fromList([1, 2, 3]));
    final again = await storage.saveImage(Uint8List.fromList([1, 2, 3]));

    expect(again, first);
    expect(Directory('${directory.path}/images').listSync(), hasLength(1));
  });
}
