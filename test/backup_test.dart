import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/backup.dart';
import 'package:headroom/list_settings.dart';
import 'package:headroom/thought.dart';
import 'package:headroom/thought_store.dart';
import 'package:headroom/tidier.dart';
import 'package:headroom/tidy_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'ai_replies.dart';
import 'in_memory_storage.dart';

typedef _App = ({
  InMemoryStorage storage,
  ThoughtStore store,
  Tidier tidier,
  ListSettings listSettings,
});

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

void main() {
  late String image;
  setUpAll(() async => image = await InMemoryStorage().saveImage(png));

  Future<_App> open(
    List<Thought> thoughts, {
    AiSettings? ai,
    List<Suggestion> declined = const [],
    List<String> themeOrder = const [],
  }) async {
    final storage = InMemoryStorage(thoughts);
    await storage.saveImage(png);
    if (ai != null) storage.values['ai'] = jsonEncode(ai);
    storage.values['tidy'] = jsonEncode({'declined': declined});
    storage.values['list'] = jsonEncode({'themeOrder': themeOrder});
    final store = ThoughtStore(storage);
    await store.load();
    final tidier = Tidier(
      store,
      storage,
      // Turned away like a backup's AI without its key.
      client: MockClient((_) async => http.Response('', 401)),
    );
    addTearDown(tidier.dispose);
    await tidier.load();
    final listSettings = ListSettings(storage);
    await listSettings.load();
    return (
      storage: storage,
      store: store,
      tidier: tidier,
      listSettings: listSettings,
    );
  }

  Backup backupOf(_App app) =>
      Backup(app.store, app.tidier, app.listSettings, app.storage);

  final day = DateTime(2026, 10, 19, 9);

  Future<Uint8List> saveFrom(
    List<Thought> thoughts, {
    List<String> themeOrder = const ['Work', 'Errands'],
  }) async {
    final from = await open(
      thoughts,
      ai: testAi,
      declined: [
        const Merge(['2', '1'], 'Groceries'),
      ],
      themeOrder: themeOrder,
    );
    from.listSettings.theme = 'Work';
    return backupOf(from).create();
  }

  test('restores thoughts with their place, images, the AI without its key, '
      'what was declined, and the order of the themes', () async {
    final moved = day.add(const Duration(hours: 2)).microsecondsSinceEpoch;
    final zip = await saveFrom([
      Thought(
        id: '2',
        text: 'Milk',
        images: [image],
        createdAt: day.add(const Duration(hours: 1)),
        themes: ['Errands', 'Food'],
        themesChosen: true,
      ),
      Thought(
        id: '1',
        text: 'Eggs and flour',
        createdAt: day,
        themes: ['Errands'],
        title: 'Baking',
        subtasks: [(text: 'Eggs', done: true), (text: 'Flour', done: false)],
        ranks: {'Errands': moved},
      ),
    ]);
    final to = await open([]);

    final restored = await backupOf(to).restore(zip);

    expect(restored, (thoughts: 2, ai: true));
    expect(to.store.thoughts.map((t) => t.text), ['Milk', 'Eggs and flour']);
    final [milk, baking] = to.store.thoughts;
    expect(milk.images, [image]);
    expect(milk.themes, ['Errands', 'Food']);
    expect(to.store.thoughts.map((t) => t.themesChosen), [true, false]);
    expect(baking.title, 'Baking');
    expect(baking.subtasks.map((s) => s.done), [true, false]);
    expect(baking.rankIn('Errands'), moved);
    expect(await to.storage.readImage(image), png);
    expect(to.tidier.settings?.baseUrl, testAi.baseUrl);
    expect(to.tidier.settings?.model, testAi.model);
    expect(to.tidier.settings?.apiKey, isEmpty);
    expect(to.tidier.declined.single.ids, ['2', '1']);
    expect(to.listSettings.themeOrder, ['Work', 'Errands']);
    expect(to.listSettings.theme, isNull);
    await to.store.flush();
    expect(to.storage.saved, hasLength(2));
  });

  test('never holds the API key, and names images so they open', () async {
    final zip = await saveFrom([
      Thought(id: '1', text: 'Eggs', images: [image], createdAt: day),
    ]);
    final files = ZipDecoder().decodeBytes(zip);

    expect(files.map((f) => f.name), contains('images/$image.png'));
    for (final file in files) {
      if (file.name.startsWith('images/')) continue;
      expect(utf8.decode(file.content), isNot(contains(testAi.apiKey)));
    }
    expect(jsonDecode(utf8.decode(files.find('ai.json')!.content)), {
      'baseUrl': testAi.baseUrl,
      'model': testAi.model,
    });
  });

  test('adds only the missing thoughts, in date order, and keeps the AI '
      'set up here', () async {
    final zip = await saveFrom([
      Thought(
        id: '3',
        text: 'Later',
        createdAt: day.add(const Duration(days: 2)),
      ),
      Thought(
        id: '2',
        text: 'Old text',
        createdAt: day.add(const Duration(days: 1)),
      ),
      Thought(id: '1', text: 'Earlier', createdAt: day),
    ]);
    const mine = AiSettings(
      baseUrl: 'http://localhost:11434/v1',
      apiKey: '',
      model: 'local',
    );
    final to = await open([
      Thought(
        id: '4',
        text: 'Newest',
        createdAt: day.add(const Duration(days: 3)),
      ),
      Thought(
        id: '2',
        text: 'Edited here',
        createdAt: day.add(const Duration(days: 1)),
      ),
    ], ai: mine);

    final restored = await backupOf(to).restore(zip);

    expect(restored, (thoughts: 2, ai: false));
    expect(to.store.thoughts.map((t) => t.text), [
      'Newest',
      'Later',
      'Edited here',
      'Earlier',
    ]);
    expect(to.tidier.settings?.model, 'local');
    expect(await backupOf(to).restore(zip), (thoughts: 0, ai: false));
  });

  test('places the themes the order here lacks after its own', () async {
    final zip = await saveFrom(
      [Thought(id: '1', text: 'Eggs', createdAt: day)],
      themeOrder: ['Home', 'Errands', 'Work'],
    );
    final files = ZipDecoder().decodeBytes(zip);
    expect(jsonDecode(utf8.decode(files.find('list.json')!.content)), {
      'themeOrder': ['Home', 'Errands', 'Work'],
    });
    final to = await open([], themeOrder: ['Work', 'Home']);

    await backupOf(to).restore(zip);

    expect(to.listSettings.themeOrder, ['Work', 'Home', 'Errands']);
  });

  test('turns away a file that is not a backup', () async {
    final to = await open([]);
    final noThoughts = ZipEncoder().encodeBytes(
      Archive()..add(ArchiveFile.string('notes.txt', 'hello')),
    );
    final badThoughts = ZipEncoder().encodeBytes(
      Archive()..add(ArchiveFile.string('thoughts.json', '{"id": 1}')),
    );

    for (final file in [
      Uint8List.fromList([1, 2, 3]),
      noThoughts,
      badThoughts,
    ]) {
      await expectLater(
        backupOf(to).restore(file),
        throwsA(isA<FormatException>()),
      );
    }
    expect(to.store.thoughts, isEmpty);
  });

  test('remembers when a copy was last saved', () async {
    final app = await open([]);
    final backup = backupOf(app);
    await backup.load();
    expect(backup.savedAt, isNull);

    await backup.saved();
    final reopened = backupOf(app);
    await reopened.load();

    expect(reopened.savedAt, isNotNull);
    expect(
      DateTime.now().difference(reopened.savedAt!),
      lessThan(const Duration(minutes: 1)),
    );
  });

  test('names the file after the day', () {
    expect(
      Backup.fileName(DateTime(2026, 3, 7, 23, 59)),
      'headroom-2026-03-07.zip',
    );
  });
}
