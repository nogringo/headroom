@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/thought.dart';
import 'package:headroom/web_thought_storage.dart';
import 'package:web/web.dart' as web;

void main() {
  test('round-trips thoughts through localStorage', () async {
    final storage = WebThoughtStorage(key: 'headroom.test');
    addTearDown(() => web.window.localStorage.removeItem(storage.key));

    expect(await storage.read(), isEmpty);

    final thought = Thought(
      id: '1',
      text: 'Rappeler le garagiste',
      createdAt: DateTime(2026, 10, 19, 9, 30),
    );
    await storage.write([thought]);
    final loaded = await WebThoughtStorage(key: 'headroom.test').read();

    expect(loaded.single.text, thought.text);
    expect(loaded.single.createdAt, thought.createdAt);
  });
}
