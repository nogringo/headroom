import 'package:headroom/thought.dart';
import 'package:headroom/thought_storage.dart';

class InMemoryStorage implements ThoughtStorage {
  InMemoryStorage([List<Thought> initial = const []])
    : saved = List.of(initial);

  List<Thought> saved;
  bool failWrites = false;

  @override
  Future<List<Thought>> read() async => List.of(saved);

  @override
  Future<void> write(List<Thought> thoughts) async {
    if (failWrites) throw StateError('disk full');
    saved = List.of(thoughts);
  }
}
