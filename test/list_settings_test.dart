import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/list_settings.dart';

import 'in_memory_storage.dart';

void main() {
  Future<String?> themeOnReopen(InMemoryStorage storage) async {
    await pumpEventQueue();
    final settings = ListSettings(storage);
    await settings.load();
    return settings.theme;
  }

  test('starts on every thought', () async {
    expect(await themeOnReopen(InMemoryStorage()), isNull);
  });

  test('keeps the theme open for next time', () async {
    final storage = InMemoryStorage();
    final settings = ListSettings(storage)..theme = 'Errands';
    expect(await themeOnReopen(storage), 'Errands');

    settings.theme = '';
    expect(await themeOnReopen(storage), '');

    settings.theme = null;
    expect(await themeOnReopen(storage), isNull);
  });

  test('starts on every thought from unreadable settings', () async {
    final storage = InMemoryStorage()..values['list'] = '{"theme": 3}';
    expect(await themeOnReopen(storage), isNull);
  });
}
