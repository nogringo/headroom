@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/file_thought_storage.dart';
import 'package:headroom/thought.dart';

void main() {
  test('round-trips thoughts and replaces the previous file', () async {
    final directory = await Directory.systemTemp.createTemp('headroom');
    addTearDown(() => directory.delete(recursive: true));
    final storage = FileThoughtStorage(File('${directory.path}/thoughts.json'));

    expect(await storage.read(), isEmpty);

    final first = Thought(
      id: '1',
      text: 'Call the garage',
      createdAt: DateTime(2026, 10, 19, 9, 30),
    );
    final second = Thought(
      id: '2',
      text: 'Buy bread',
      createdAt: DateTime(2026, 10, 19, 10),
    );
    await storage.write([first]);
    await storage.write([second, first]);
    final loaded = await storage.read();

    expect(loaded.map((t) => t.text), ['Buy bread', 'Call the garage']);
    expect(loaded.last.createdAt, first.createdAt);
    expect(File('${directory.path}/thoughts.json.tmp').existsSync(), isFalse);
  });
}
