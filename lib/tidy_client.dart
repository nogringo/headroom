import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'thought.dart';

/// Any service that speaks OpenAI's Chat Completions: OpenAI, Claude, Gemini,
/// Mistral, OpenRouter, or a local model served by Ollama or LM Studio.
class AiSettings {
  const AiSettings({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  factory AiSettings.fromJson(Map<String, dynamic> json) => AiSettings(
    baseUrl: json['baseUrl'] as String,
    apiKey: json['apiKey'] as String? ?? '',
    model: json['model'] as String,
  );

  /// Up to the API version, such as https://api.openai.com/v1.
  final String baseUrl;

  /// Empty for a local model that needs none.
  final String apiKey;
  final String model;

  Map<String, Object> toJson() => {
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
  };
}

/// A clean-up the AI proposes. Nothing changes until the person accepts it.
sealed class Suggestion {
  const Suggestion();

  factory Suggestion.fromJson(Map<String, dynamic> json) => switch (json) {
    {'merge': final List<dynamic> ids, 'text': final String text} => Merge(
      ids.cast<String>(),
      text,
    ),
    {'outdated': final String id} => Outdated(id),
    _ => throw FormatException('Unknown suggestion', json),
  };

  List<String> get ids;

  /// Whether accepting or declining this settles [other] too.
  bool covers(Suggestion other);

  Map<String, Object> toJson();
}

/// Thoughts that repeat each other, and the one that would replace them.
final class Merge extends Suggestion {
  const Merge(this.ids, this.text);

  @override
  final List<String> ids;
  final String text;

  @override
  bool covers(Suggestion other) =>
      other is Merge && other.ids.every(ids.contains);

  @override
  Map<String, Object> toJson() => {'merge': ids, 'text': text};
}

/// A thought that looks out of date.
final class Outdated extends Suggestion {
  const Outdated(this.id);

  final String id;

  @override
  List<String> get ids => [id];

  @override
  bool covers(Suggestion other) => other is Outdated && other.id == id;

  @override
  Map<String, Object> toJson() => {'outdated': id};
}

enum TidyFailure { unreachable, rejectedKey, notFound, limited, failed }

class TidyException implements Exception {
  const TidyException(this.failure, [this.detail, this.message]);

  final TidyFailure failure;
  final Object? detail;

  /// The service's own words, when it gave some. A 429 can mean a rate
  /// limit as well as no credit left.
  final String? message;

  @override
  String toString() => 'TidyException(${failure.name}, $detail)';
}

/// Themes by thought id, and what could be cleaned up.
typedef Tidied = ({Map<String, String> themes, List<Suggestion> suggestions});

class TidyClient {
  TidyClient(this._http);

  final http.Client _http;

  /// Reasoning models can think for a while over a long list.
  static const timeout = Duration(minutes: 3);

  /// Sends every thought as context and asks for the themes of [toSort].
  Future<Tidied> tidy(
    AiSettings settings, {
    required List<Thought> thoughts,
    required Set<String> toSort,
    required DateTime now,
  }) async {
    // Numbers rather than ids, which models copy back less reliably.
    final ids = [for (final thought in thoughts) thought.id];
    final day = DateFormat('yyyy-MM-dd, EEEE', 'en_US');
    final list = {
      'today': day.format(now),
      'toSort': [
        for (final (index, id) in ids.indexed)
          if (toSort.contains(id)) index + 1,
      ],
      'thoughts': [
        for (final (index, thought) in thoughts.indexed)
          {
            'n': index + 1,
            'noted': day.format(thought.createdAt),
            'text': thought.text,
            'theme': ?thought.theme,
            if (thought.themeChosen) 'byOwner': true,
          },
      ],
    };
    final reply = await _call(settings, 'chat/completions', {
      'model': settings.model,
      'messages': [
        {'role': 'system', 'content': _instructions},
        {'role': 'user', 'content': jsonEncode(list)},
      ],
    });
    return _read(_contentOf(reply), ids, toSort);
  }

  /// The models the service offers, for picking one by name.
  Future<List<String>> models(AiSettings settings) async {
    final reply = await _call(settings, 'models');
    return [
      if (reply['data'] case final List<dynamic> data)
        for (final model in data)
          if (model case {'id': final String id}) id,
    ]..sort();
  }

  Future<Map<String, dynamic>> _call(
    AiSettings settings,
    String path, [
    Map<String, Object>? body,
  ]) async {
    final base = settings.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/$path');
    final key = settings.apiKey;
    final claude = uri.host == 'api.anthropic.com';
    final headers = {
      if (body != null) 'content-type': 'application/json',
      // Claude answers a browser only when asked to.
      if (claude) 'anthropic-dangerous-direct-browser-access': 'true',
      if (key.isNotEmpty)
        // Claude lists its models only through its own API, keyed differently.
        ...(claude && body == null
            ? {'x-api-key': key, 'anthropic-version': '2023-06-01'}
            : {'authorization': 'Bearer $key'}),
    };

    final http.Response response;
    try {
      final request = body == null
          ? _http.get(uri, headers: headers)
          : _http.post(uri, headers: headers, body: jsonEncode(body));
      response = await request.timeout(timeout);
    } on TimeoutException catch (error) {
      throw TidyException(TidyFailure.unreachable, error);
    } on http.ClientException catch (error) {
      throw TidyException(TidyFailure.unreachable, error);
    }

    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    final failure = switch (response.statusCode) {
      >= 200 && < 300 => null,
      401 || 403 => TidyFailure.rejectedKey,
      404 => TidyFailure.notFound,
      429 => TidyFailure.limited,
      _ => TidyFailure.failed,
    };
    if (failure != null) {
      throw TidyException(
        failure,
        '${response.statusCode} $text',
        _errorMessageIn(text),
      );
    }
    try {
      if (jsonDecode(text) case final Map<String, dynamic> json) return json;
    } on FormatException {
      // Reported below with the body.
    }
    throw TidyException(TidyFailure.failed, text);
  }
}

String? _errorMessageIn(String body) {
  try {
    return switch (jsonDecode(body)) {
      {'error': {'message': final String message}} ||
      // Ollama's own shape.
      {'error': final String message} => message.trim(),
      _ => null,
    };
  } on FormatException {
    return null;
  }
}

String _contentOf(Map<String, dynamic> reply) => switch (reply) {
  {'choices': [{'message': {'content': final String content}}, ...]} => content,
  {'choices': [{'message': {'content': final List<dynamic> parts}}, ...]} => [
    for (final part in parts)
      if (part case {'text': final String text}) text,
  ].join(),
  _ => throw TidyException(TidyFailure.failed, reply),
};

Tidied _read(String content, List<String> ids, Set<String> toSort) {
  // Some local models think out loud before answering.
  final text = content.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  Object? json;
  if (start != -1 && end > start) {
    try {
      json = jsonDecode(text.substring(start, end + 1));
    } on FormatException {
      // Reported below with the content.
    }
  }
  if (json is! Map<String, dynamic>) {
    throw TidyException(TidyFailure.failed, content);
  }

  String? idOf(Object? number) => switch (number) {
    final int n when n >= 1 && n <= ids.length => ids[n - 1],
    final String n => idOf(int.tryParse(n)),
    _ => null,
  };

  return (
    themes: {
      if (json['themes'] case final Map<String, dynamic> themes)
        for (final MapEntry(:key, :value) in themes.entries)
          if ((idOf(key), value) case (final String id, final String theme)
              when toSort.contains(id) && theme.trim().isNotEmpty)
            id: theme.trim(),
    },
    suggestions: [
      if (json['merges'] case final List<dynamic> merges)
        for (final merge in merges)
          if (merge case {
            'thoughts': final List<dynamic> numbers,
            'text': final String merged,
          })
            if ({for (final n in numbers) ?idOf(n)} case final group
                when group.length >= 2 && merged.trim().isNotEmpty)
              Merge(group.toList(), merged.trim()),
      if (json['outdated'] case final List<dynamic> outdated)
        for (final n in outdated)
          if (idOf(n) case final String id) Outdated(id),
    ],
  );
}

const _instructions = '''
You keep a personal list of quick notes tidy. Its owner jots thoughts down in a hurry to get them out of their head: errands, ideas, reminders, things to remember. You receive the whole list as JSON. Each thought has a number, the day it was noted, its text, and its theme when it already has one. A theme marked "byOwner" was chosen by the owner, often to correct yours: those show how the owner wants the list sorted.

Do three things.

1. Give a theme to each thought numbered in "toSort". Sort it the way the owner sorted similar thoughts. Reuse an existing theme whenever one fits. Create a new theme only for a subject none of them covers, and name it so it can hold future thoughts too: one to three words, in the language the thoughts are written in, starting with a capital letter. A list usually needs a handful of themes, not one per thought.

2. Find thoughts that repeat each other or say nearly the same thing. For each such group, write the one thought that would replace them: keep every detail from each, in the owner's words and language, about as short as the originals. Thoughts that merely share a subject are not repeats.

3. Find thoughts that are clearly out of date today: an appointment or event whose day has passed, an errand tied to a date gone by. When in doubt, leave the thought out.

Reply with one JSON object and nothing else, in this shape:
{"themes": {"<number>": "<theme>"}, "merges": [{"thoughts": [<number>, <number>], "text": "<the merged thought>"}], "outdated": [<number>]}
Use empty lists when nothing needs merging or nothing is out of date.''';
