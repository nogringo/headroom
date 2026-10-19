import 'dart:convert';
import 'dart:typed_data';

import 'thought.dart';

abstract interface class ThoughtStorage {
  Future<List<Thought>> read();
  Future<void> write(List<Thought> thoughts);

  /// Returns the name to put in [Thought.image].
  Future<String> saveImage(Uint8List bytes);
  Future<Uint8List> readImage(String name);
  Future<void> deleteImagesExcept(Set<String> keep);
}

String encodeThoughts(List<Thought> thoughts) => jsonEncode(thoughts);

List<Thought> decodeThoughts(String json) => [
  for (final item in jsonDecode(json) as List<dynamic>)
    Thought.fromJson(item as Map<String, dynamic>),
];

var _imageCount = 0;

// The counter keeps names apart on the web, where the clock ticks in milliseconds.
String newImageName() =>
    '${DateTime.now().microsecondsSinceEpoch}-${_imageCount++}';
