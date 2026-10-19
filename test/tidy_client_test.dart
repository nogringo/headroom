import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/thought.dart';
import 'package:headroom/tidy_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'ai_replies.dart';

void main() {
  final thoughts = [
    Thought(
      id: 'c',
      text: 'Acheter du lait',
      createdAt: DateTime(2026, 10, 20, 9),
    ),
    Thought(id: 'b', text: 'lait !!', createdAt: DateTime(2026, 10, 19, 18)),
    Thought(
      id: 'a',
      text: 'Dentiste mardi 14h',
      createdAt: DateTime(2026, 10, 6, 8),
      theme: 'Santé',
    ),
  ];

  test('sends the numbered list and reads the reply back by id', () async {
    late http.Request sent;
    final client = TidyClient(
      MockClient((request) async {
        sent = request;
        return chatReply(
          '<think>Two are about {milk}.</think>\n```json\n'
          '${jsonEncode({
            'themes': {'1': ' Courses ', '2': 'Courses', '3': 'Ignored', '9': 'Unknown'},
            'merges': [
              {
                'thoughts': [1, 2],
                'text': 'Acheter du lait',
              },
              {
                'thoughts': [1, 42],
                'text': 'Not enough thoughts left',
              },
            ],
            'outdated': [3, 7],
          })}\n```',
        );
      }),
    );

    final tidied = await client.tidy(
      testAi,
      thoughts: thoughts,
      toSort: {'c', 'b'},
      now: DateTime(2026, 10, 20, 10),
    );

    expect(sent.url, Uri.parse('https://ai.example/v1/chat/completions'));
    expect(sent.headers['authorization'], 'Bearer secret');
    expect(
      sent.headers,
      isNot(contains('anthropic-dangerous-direct-browser-access')),
    );
    expect((jsonDecode(sent.body) as Map)['model'], 'tidy-1');
    final list = sentList(sent);
    expect(list.toSort, [1, 2]);
    expect(list.thoughts.last, {
      'n': 3,
      'noted': '2026-10-06, Tuesday',
      'text': 'Dentiste mardi 14h',
      'theme': 'Santé',
    });
    expect(list.thoughts.first, isNot(contains('theme')));

    expect(tidied.themes, {'c': 'Courses', 'b': 'Courses'});
    expect(tidied.suggestions, hasLength(2));
    final merge = tidied.suggestions.first as Merge;
    expect(merge.ids, ['c', 'b']);
    expect(merge.text, 'Acheter du lait');
    expect((tidied.suggestions.last as Outdated).id, 'a');
  });

  test('asks Claude the way a browser may, and lists its models', () async {
    final requests = <http.Request>[];
    final client = TidyClient(
      MockClient((request) async {
        requests.add(request);
        return request.method == 'GET'
            ? http.Response(
                jsonEncode({
                  'data': [
                    {'id': 'claude-opus-5-5'},
                    {'id': 'claude-haiku-5-5'},
                  ],
                }),
                200,
              )
            : chatReply({'themes': {}});
      }),
    );
    const claude = AiSettings(
      baseUrl: 'https://api.anthropic.com/v1/',
      apiKey: 'sk-ant',
      model: 'claude-haiku-5-5',
    );

    await client.tidy(
      claude,
      thoughts: thoughts,
      toSort: {},
      now: DateTime(2026),
    );
    final models = await client.models(claude);

    final [chat, listing] = requests;
    expect(chat.url.path, '/v1/chat/completions');
    expect(chat.headers['authorization'], 'Bearer sk-ant');
    expect(chat.headers['anthropic-dangerous-direct-browser-access'], 'true');
    expect(listing.url.path, '/v1/models');
    expect(listing.headers['x-api-key'], 'sk-ant');
    expect(listing.headers, isNot(contains('authorization')));
    expect(models, ['claude-haiku-5-5', 'claude-opus-5-5']);
  });

  test('sends no key when none is set', () async {
    late http.Request sent;
    final client = TidyClient(
      MockClient((request) async {
        sent = request;
        return chatReply({'themes': {}});
      }),
    );

    await client.tidy(
      const AiSettings(
        baseUrl: 'http://localhost:11434/v1',
        apiKey: '',
        model: 'llama',
      ),
      thoughts: thoughts,
      toSort: {},
      now: DateTime(2026),
    );

    expect(sent.headers, isNot(contains('authorization')));
  });

  test('tells why a request failed', () async {
    Future<TidyFailure> failureFor(http.Response response) async {
      final client = TidyClient(MockClient((_) async => response));
      try {
        await client.tidy(
          testAi,
          thoughts: thoughts,
          toSort: {},
          now: DateTime(2026),
        );
      } on TidyException catch (error) {
        return error.failure;
      }
      fail('No failure for ${response.statusCode} ${response.body}');
    }

    expect(await failureFor(http.Response('', 401)), TidyFailure.rejectedKey);
    expect(await failureFor(http.Response('', 404)), TidyFailure.notFound);
    expect(await failureFor(http.Response('', 429)), TidyFailure.limited);
    expect(await failureFor(http.Response('', 500)), TidyFailure.failed);
    expect(await failureFor(http.Response('<html>', 200)), TidyFailure.failed);
    expect(await failureFor(chatReply('No JSON here')), TidyFailure.failed);

    final offline = TidyClient(
      MockClient((request) async => throw http.ClientException('offline')),
    );
    await expectLater(
      offline.tidy(testAi, thoughts: thoughts, toSort: {}, now: DateTime(2026)),
      throwsA(
        isA<TidyException>().having(
          (e) => e.failure,
          'failure',
          TidyFailure.unreachable,
        ),
      ),
    );
  });

  test('passes on what the service said about a failure', () async {
    Future<String?> messageFor(http.Response response) async {
      final client = TidyClient(MockClient((_) async => response));
      try {
        await client.tidy(
          testAi,
          thoughts: thoughts,
          toSort: {},
          now: DateTime(2026),
        );
      } on TidyException catch (error) {
        return error.message;
      }
      fail('No failure for ${response.statusCode} ${response.body}');
    }

    final zai = jsonEncode({
      'error': {
        'code': '1113',
        'message':
            'Insufficient balance or no resource package. Please recharge.',
      },
    });
    expect(
      await messageFor(http.Response(zai, 429)),
      'Insufficient balance or no resource package. Please recharge.',
    );
    expect(
      await messageFor(
        http.Response(jsonEncode({'error': 'model "llama" not found'}), 404),
      ),
      'model "llama" not found',
    );
    expect(await messageFor(http.Response('Bad gateway', 502)), isNull);
  });

  test('suggestions round-trip through JSON', () {
    const merge = Merge(['a', 'b'], 'Both');
    const outdated = Outdated('c');

    final read = [
      for (final s in [merge, outdated])
        Suggestion.fromJson(jsonDecode(jsonEncode(s)) as Map<String, dynamic>),
    ];

    expect((read.first as Merge).ids, ['a', 'b']);
    expect((read.first as Merge).text, 'Both');
    expect((read.last as Outdated).id, 'c');
    expect(merge.covers(const Merge(['b'], 'Part')), isTrue);
    expect(merge.covers(const Merge(['b', 'd'], 'Other')), isFalse);
    expect(outdated.covers(const Outdated('c')), isTrue);
    expect(outdated.covers(const Merge(['c'], 'c')), isFalse);
  });
}
