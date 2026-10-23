import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/thought.dart';
import 'package:headroom/thought_store.dart';
import 'package:headroom/tidier.dart';
import 'package:headroom/tidy_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'ai_replies.dart';
import 'in_memory_storage.dart';

void main() {
  late InMemoryStorage storage;
  late ThoughtStore store;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) reply;

  Future<Tidier> open() async {
    final tidier = Tidier(
      store,
      storage,
      client: MockClient((request) {
        requests.add(request);
        return reply(request);
      }),
    );
    addTearDown(tidier.dispose);
    await tidier.load();
    await pumpEventQueue();
    return tidier;
  }

  Future<Tidier> start(
    List<Thought> thoughts, {
    AiSettings? ai = testAi,
  }) async {
    storage = InMemoryStorage(thoughts);
    if (ai != null) storage.values['ai'] = jsonEncode(ai);
    store = ThoughtStore(storage);
    await store.load();
    return open();
  }

  Future<Thought> note(Tidier tidier, String text) async {
    final thought = store.add(text)!;
    tidier.noted(thought);
    await pumpEventQueue();
    return store.thoughts.firstWhere((t) => t.id == thought.id);
  }

  setUp(() {
    requests = [];
    reply = (request) async => describedAs(['Errands']);
  });

  test('describes each thought as it is noted', () async {
    final tidier = await start([]);
    expect(requests, isEmpty);
    reply = (request) async => describedAs(
      ['Errands', 'Home'],
      title: 'Groceries',
      subtasks: ['Bread', 'Milk'],
    );

    final groceries = await note(tidier, 'Buy bread and milk for the week');

    expect(requests, hasLength(1));
    expect(sentInput(requests.single)['thought'], groceries.text);
    expect(groceries.themes, ['Errands', 'Home']);
    expect(groceries.themesChosen, isFalse);
    expect(groceries.title, 'Groceries');
    expect(groceries.subtasks, [
      (text: 'Bread', done: false),
      (text: 'Milk', done: false),
    ]);
    expect(tidier.willSort(groceries), isFalse);
    expect(tidier.failure, isNull);

    reply = (request) async => describedAs(['Work']);
    final build = await note(tidier, 'Fix the build');
    expect(requests, hasLength(2));
    expect(sentInput(requests.last)['themes'], ['Errands', 'Home']);
    expect(build.themes, ['Work']);
    expect(build.title, isNull);
    expect(build.subtasks, isEmpty);

    tidier.noted(store.add('', images: ['photo'])!);
    await pumpEventQueue();
    expect(requests, hasLength(2), reason: 'Images alone are not sent');
  });

  test('asks nothing at launch, on an edit, or about older thoughts', () async {
    final tidier = await start([
      Thought(id: '1', text: 'Buy bread', createdAt: DateTime.now()),
      Thought(
        id: '2',
        text: 'Fix the build',
        createdAt: DateTime.now(),
        themes: ['Work'],
      ),
    ]);

    store.update('2', text: 'Fix the tests', images: []);
    await pumpEventQueue();

    expect(requests, isEmpty);
    expect(store.thoughts.last.themes, ['Work']);
    expect(tidier.willSort(store.thoughts.first), isFalse);
  });

  test('does nothing until set up', () async {
    final tidier = await start([], ai: null);

    await note(tidier, 'Buy bread');
    expect(requests, isEmpty);

    await tidier.configure(testAi);
    await pumpEventQueue();
    expect(requests, isEmpty, reason: 'Thoughts noted before stay as they are');
    expect(jsonDecode(storage.values['ai']!), testAi.toJson());

    expect((await note(tidier, 'Call the garage')).themes, ['Errands']);
  });

  test('shows the AI the themes the person chose', () async {
    final now = DateTime.now();
    final tidier = await start([
      Thought(id: '2', text: 'Dune', createdAt: now, themes: ['Books']),
      Thought(
        id: '1',
        text: 'Read Dune',
        createdAt: now,
        themes: ['Books', 'Fun'],
        themesChosen: true,
      ),
    ]);

    await note(tidier, 'Read Foundation');

    expect(sentInput(requests.single), {
      'themes': ['Books', 'Fun'],
      'sortedByOwner': [
        {
          'text': 'Read Dune',
          'themes': ['Books', 'Fun'],
        },
      ],
      'thought': 'Read Foundation',
    });
  });

  test('leaves alone themes chosen while it was asking', () async {
    final tidier = await start([]);
    reply = (request) async {
      store.chooseThemes(store.thoughts.single.id, ['Bakery']);
      return describedAs(['Errands'], title: 'Bread');
    };

    final thought = await note(tidier, 'Buy bread');

    expect(thought.themes, ['Bakery']);
    expect(thought.title, 'Bread');
  });

  test('describes a thought noted offline at the next launch', () async {
    reply = (request) async => throw http.ClientException('offline');
    final offline = await start([]);

    final thought = await note(offline, 'Buy bread');

    expect(offline.failure, TidyFailure.unreachable);
    expect(thought.themes, isEmpty);
    expect(offline.willSort(thought), isFalse);

    reply = (request) async => describedAs(['Errands']);
    final online = await open();

    expect(requests, hasLength(2));
    expect(store.thoughts.single.themes, ['Errands']);
    expect(online.failure, isNull);
    expect(jsonDecode(storage.values['tidy']!), isNot(contains('queue')));
  });

  test('reports a failure until a retry works', () async {
    reply = (request) async => http.Response(
      jsonEncode({
        'error': {'message': 'Invalid API key'},
      }),
      401,
    );
    final tidier = await start([]);

    await note(tidier, 'Buy bread');

    expect(tidier.failure, TidyFailure.rejectedKey);
    expect(tidier.failureMessage, 'Invalid API key');
    expect(requests, hasLength(1));

    reply = (request) async => describedAs(['Errands']);
    tidier.retry();
    await pumpEventQueue();
    expect(tidier.failure, isNull);
    expect(tidier.failureMessage, isNull);
    expect(store.thoughts.single.themes, ['Errands']);
  });

  test('reports an unreadable reply as an error', () async {
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);
    reply = (request) async => chatReply('Sorry, I cannot help.');
    final tidier = await start([]);

    await note(tidier, 'Buy bread');

    expect(tidier.failure, TidyFailure.failed);
    expect(reported, hasLength(1));
  });

  test('cleans up only when asked, and keeps what it found', () async {
    final now = DateTime.now();
    reply = (request) async => chatReply({
      'merges': [
        {
          'thoughts': [1, 2],
          'text': 'Buy bread',
        },
      ],
      'outdated': [3],
    });
    final tidier = await start([
      Thought(id: '3', text: 'Buy bread', createdAt: now, themes: ['Errands']),
      Thought(id: '2', text: 'bread!', createdAt: now, themes: ['Errands']),
      Thought(id: '1', text: 'Dentist Monday', createdAt: now),
    ]);
    expect(requests, isEmpty);

    expect(await tidier.cleanUp(), 2);
    expect(isCleanUp(requests.single), isTrue);
    expect(tidier.cleaning, isFalse);
    final [merge as Merge, outdated as Outdated] = tidier.suggestions;
    expect(merge.ids, ['3', '2']);
    expect(outdated.id, '1');

    final reloaded = Tidier(store, storage, client: MockClient(reply));
    addTearDown(reloaded.dispose);
    await reloaded.load();
    expect(reloaded.suggestions, hasLength(2));

    tidier.decline(outdated);
    store.merge(merge.ids, merge.text);
    expect(tidier.suggestions, isEmpty);

    // Declined once, never again, even when the AI proposes it anew.
    reply = (request) async => chatReply({
      'outdated': [
        for (final t in sentInput(request)['thoughts'] as List<dynamic>)
          if (t['text'] == 'Dentist Monday') t['n'],
      ],
    });
    expect(await tidier.cleanUp(), 0);
    expect(tidier.suggestions, isEmpty);
  });

  test('ignores a suggestion about a thought edited meanwhile', () async {
    final tidier = await start([
      Thought(id: '1', text: 'Dentist Monday', createdAt: DateTime.now()),
    ]);
    reply = (request) async {
      store.update('1', text: 'Dentist next Monday', images: []);
      return chatReply({
        'outdated': [1],
      });
    };

    expect(await tidier.cleanUp(), 0);
    expect(tidier.suggestions, isEmpty);
  });

  test('a failed clean-up says so, and goes again when asked', () async {
    reply = (request) async => http.Response('', 429);
    final tidier = await start([
      Thought(id: '1', text: 'Dentist Monday', createdAt: DateTime.now()),
    ]);

    expect(await tidier.cleanUp(), isNull);
    expect(tidier.failure, TidyFailure.limited);
    expect(tidier.cleanUpFailed, isTrue);

    reply = (request) async => chatReply({
      'outdated': [1],
    });
    expect(await tidier.cleanUp(), 1);
    expect(tidier.failure, isNull);
    expect(tidier.cleanUpFailed, isFalse);
  });

  test('turning off forgets the settings and the suggestions', () async {
    reply = (request) async => chatReply({
      'outdated': [1],
    });
    final tidier = await start([
      Thought(
        id: '1',
        text: 'Dentist',
        createdAt: DateTime.now(),
        themes: ['Health'],
      ),
    ]);
    await tidier.cleanUp();
    expect(tidier.suggestions, hasLength(1));

    await tidier.configure(null);

    expect(tidier.settings, isNull);
    expect(tidier.suggestions, isEmpty);
    expect(await tidier.cleanUp(), isNull);
    expect(storage.values, isNot(contains('ai')));
    expect(store.thoughts.single.themes, ['Health']);
  });
}
