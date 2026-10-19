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

/// What a tidy request sent: the list of thoughts and the numbers to sort.
({List<Map<String, dynamic>> thoughts, List<int> toSort}) sentList(
  http.Request request,
) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  final messages = body['messages'] as List<dynamic>;
  final list = jsonDecode(
    (messages.last as Map<String, dynamic>)['content'] as String,
  ) as Map<String, dynamic>;
  return (
    thoughts: (list['thoughts'] as List<dynamic>).cast(),
    toSort: (list['toSort'] as List<dynamic>).cast(),
  );
}

/// Sorts every thought it is asked about into [theme].
http.Response sortAllInto(http.Request request, String theme) => chatReply({
  'themes': {for (final n in sentList(request).toSort) '$n': theme},
  'merges': <Object>[],
  'outdated': <Object>[],
});
