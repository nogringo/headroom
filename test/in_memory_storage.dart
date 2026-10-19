import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:headroom/thought.dart';
import 'package:headroom/thought_storage.dart';

class InMemoryStorage implements ThoughtStorage {
  InMemoryStorage([List<Thought> initial = const []])
    : saved = List.of(initial);

  List<Thought> saved;
  final images = <String, Uint8List>{};
  bool failWrites = false;

  @override
  Future<List<Thought>> read() async => List.of(saved);

  @override
  Future<void> write(List<Thought> thoughts) async {
    if (failWrites) throw StateError('disk full');
    saved = List.of(thoughts);
  }

  @override
  Future<String> saveImage(Uint8List bytes) async {
    // Named by content like the real storages, without their isolate hop.
    final name = '${sha256.convert(bytes)}';
    images[name] = bytes;
    return name;
  }

  @override
  Future<Uint8List> readImage(String name) async =>
      images[name] ?? (throw StateError('No image named $name'));

  @override
  Future<void> deleteImagesExcept(Set<String> keep) async =>
      images.removeWhere((name, _) => !keep.contains(name));
}
