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

  test('keeps the themes in the order given, through renames', () async {
    final storage = InMemoryStorage();
    final settings = ListSettings(storage)
      ..themeOrder = ['Work', 'Errands', 'Home'];

    settings.renameTheme('Errands', 'Shopping');
    expect(settings.themeOrder, ['Work', 'Shopping', 'Home']);
    settings.renameTheme('Shopping', 'Home');
    expect(settings.themeOrder, ['Work', 'Home']);
    settings.renameTheme('Garden', 'Yard');
    expect(settings.themeOrder, ['Work', 'Home']);

    await pumpEventQueue();
    final reopened = ListSettings(storage);
    await reopened.load();
    expect(reopened.themeOrder, ['Work', 'Home']);
  });

  test('starts on every thought from unreadable settings', () async {
    final storage = InMemoryStorage()..values['list'] = '{"theme": 3}';
    expect(await themeOnReopen(storage), isNull);
  });
}
