import 'package:web/web.dart' as web;

import 'thought.dart';
import 'thought_storage.dart';

Future<ThoughtStorage> openThoughtStorage() async => WebThoughtStorage();

class WebThoughtStorage implements ThoughtStorage {
  WebThoughtStorage({this.key = 'headroom.thoughts'});

  final String key;

  @override
  Future<List<Thought>> read() async {
    final json = web.window.localStorage.getItem(key);
    return json == null ? [] : decodeThoughts(json);
  }

  @override
  Future<void> write(List<Thought> thoughts) async =>
      web.window.localStorage.setItem(key, encodeThoughts(thoughts));
}
