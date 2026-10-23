import 'dart:convert';

import 'package:headroom/tidy_client.dart';
import 'package:http/http.dart' as http;

const testAi = AiSettings(
  baseUrl: 'https://ai.example/v1',
  apiKey: 'secret',
  model: 'tidy-1',
);

/// A Chat Completions reply whose message holds [content], encoded as JSON
/// unless it is already a string.
http.Response chatReply(Object content) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {
          'role': 'assistant',
          'content': content is String ? content : jsonEncode(content),
        },
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// What a request sent after the instructions: one thought to describe, or
/// the list to clean up.
Map<String, dynamic> sentInput(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  final messages = body['messages'] as List<dynamic>;
  return jsonDecode(
    (messages.last as Map<String, dynamic>)['content'] as String,
  ) as Map<String, dynamic>;
}

/// Whether [request] asks to clean up the list rather than describe a
/// thought.
bool isCleanUp(http.Request request) =>
    sentInput(request).containsKey('thoughts');

/// The AI's description of a thought.
http.Response describedAs(
  List<String> themes, {
  String title = '',
  List<String> subtasks = const [],
}) => chatReply({'themes': themes, 'title': title, 'subtasks': subtasks});
