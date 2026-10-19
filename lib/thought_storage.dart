import 'dart:convert';

import 'thought.dart';

abstract interface class ThoughtStorage {
  Future<List<Thought>> read();
  Future<void> write(List<Thought> thoughts);
}

String encodeThoughts(List<Thought> thoughts) => jsonEncode(thoughts);

List<Thought> decodeThoughts(String json) => [
  for (final item in jsonDecode(json) as List<dynamic>)
    Thought.fromJson(item as Map<String, dynamic>),
];
