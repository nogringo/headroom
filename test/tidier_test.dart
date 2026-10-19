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

  Future<Tidier> start(
    List<Thought> thoughts, {
    AiSettings? ai = testAi,
  }) async {
    storage = InMemoryStorage(thoughts);
    if (ai != null) storage.values['ai'] = jsonEncode(ai);
    store = ThoughtStore(storage);
    await store.load();
    final tidier = Tidier(
      store,
      storage,
      delay: Duration.zero,
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

  setUp(() {
    requests = [];
    reply = (request) async => sortAllInto(request, 'Errands');
  });

  test('sorts thoughts as they are noted', () async {
    final tidier = await start([]);
    expect(requests, isEmpty);

    store.add('Buy bread');
    store.add('Call the garage');
    await pumpEventQueue();

    expect(requests, hasLength(1));
    expect(store.thoughts.map((t) => t.theme), ['Errands', 'Errands']);
    expect(tidier.working, isFalse);
    expect(tidier.failure, isNull);

    store.add('', images: ['photo']);
    await pumpEventQueue();
    expect(requests, hasLength(1), reason: 'Images alone are not sent');
  });

  test('does nothing until set up', () async {
    final tidier = await start([
      Thought(id: '1', text: 'Buy bread', createdAt: DateTime.now()),
    ], ai: null);

    expect(requests, isEmpty);

    await tidier.configure(testAi);
    await pumpEventQueue();

    expect(requests, hasLength(1));
    expect(store.thoughts.single.theme, 'Errands');
    expect(jsonDecode(storage.values['ai']!), testAi.toJson());
  });

  test('asks again about an edited thought', () async {
    await start([]);
    final thought = store.add('Buy bread')!;
    await pumpEventQueue();
    reply = (request) async => sortAllInto(request, 'Food');

    store.update(thought.id, text: 'Bake bread', images: []);
    await pumpEventQueue();

    expect(store.thoughts.single.theme, 'Food');
  });

  test('does not ask twice about a thought the AI left out', () async {
    reply = (request) async => chatReply({'themes': {}});
    await start([
      Thought(id: '1', text: 'Buy bread', createdAt: DateTime.now()),
    ]);

    store.add('Call the garage');
    await pumpEventQueue();

    expect(requests.map((r) => sentList(r).toSort), [
      [1],
      [1],
    ]);
  });

  test('keeps suggestions until they are settled', () async {
    final now = DateTime.now();
    reply = (request) async => chatReply({
      'themes': {},
      'merges': [
        {
          'thoughts': [1, 2],
          'text': 'Buy bread',
        },
      ],
      'outdated': [3],
    });
    final tidier = await start([
      Thought(id: '3', text: 'Buy bread', createdAt: now, theme: 'Errands'),
      Thought(id: '2', text: 'bread!', createdAt: now, theme: 'Errands'),
      Thought(id: '1', text: 'Dentist Monday', createdAt: now, theme: 'Health'),
    ]);

    expect(tidier.suggestions, hasLength(2));
    final [merge as Merge, outdated as Outdated] = tidier.suggestions;
    expect(merge.ids, ['3', '2']);
    expect(outdated.id, '1');

    // Reloaded from storage.
    final reloaded = Tidier(store, storage, client: MockClient(reply));
    addTearDown(reloaded.dispose);
    await reloaded.load();
    expect(reloaded.suggestions, hasLength(2));

    tidier.decline(outdated);
    store.merge(merge.ids, merge.text);
    expect(tidier.suggestions, isEmpty);

    // Declined once, never again, even when the AI proposes it anew.
    reply = (request) async => chatReply({
      'themes': {},
      'outdated': [
        for (final t in sentList(request).thoughts)
          if (t['text'] == 'Dentist Monday') t['n'],
      ],
    });
    store.add('Water the plants');
    await pumpEventQueue();
    expect(requests, hasLength(2));
    expect(tidier.suggestions, isEmpty);
  });

  test('ignores a suggestion about a thought edited meanwhile', () async {
    final thought = Thought(
      id: '1',
      text: 'Dentist Monday',
      createdAt: DateTime.now(),
      theme: 'Health',
    );
    final tidier = await start([thought]);
    reply = (request) async {
      store.update('1', text: 'Dentist next Monday', images: []);
      return chatReply({
        'themes': {},
        'outdated': [1],
      });
    };

    tidier.retry();
    await pumpEventQueue();

    expect(tidier.suggestions, isEmpty);
  });

  test('reports a failure and waits for the next change', () async {
    reply = (request) async => http.Response(
      jsonEncode({
        'error': {'message': 'Invalid API key'},
      }),
      401,
    );
    final tidier = await start([
      Thought(id: '1', text: 'Buy bread', createdAt: DateTime.now()),
    ]);

    expect(tidier.failure, TidyFailure.rejectedKey);
    expect(tidier.failureMessage, 'Invalid API key');
    expect(requests, hasLength(1));
    await pumpEventQueue();
    expect(requests, hasLength(1));

    reply = (request) async => sortAllInto(request, 'Errands');
    tidier.retry();
    await pumpEventQueue();
    expect(tidier.failure, isNull);
    expect(tidier.failureMessage, isNull);
    expect(store.thoughts.single.theme, 'Errands');
  });

  test('reports an unreadable reply as an error', () async {
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);
    reply = (request) async => chatReply('Sorry, I cannot help.');

    final tidier = await start([
      Thought(id: '1', text: 'Buy bread', createdAt: DateTime.now()),
    ]);

    expect(tidier.failure, TidyFailure.failed);
    expect(reported, hasLength(1));
  });

  test('turning off forgets the settings and the suggestions', () async {
    reply = (request) async => chatReply({
      'themes': {},
      'outdated': [1],
    });
    final tidier = await start([
      Thought(
        id: '1',
        text: 'Dentist',
        createdAt: DateTime.now(),
        theme: 'Health',
      ),
    ]);
    expect(tidier.suggestions, hasLength(1));

    await tidier.configure(null);

    expect(tidier.settings, isNull);
    expect(tidier.suggestions, isEmpty);
    expect(storage.values, isNot(contains('ai')));
    expect(store.thoughts.single.theme, 'Health');
  });
}
