import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'thought.dart';

abstract interface class ThoughtStorage {
  Future<List<Thought>> read();
  Future<void> write(List<Thought> thoughts);

  /// Returns the name to put in [Thought.images], the same for the same bytes.
  Future<String> saveImage(Uint8List bytes);
  Future<Uint8List> readImage(String name);
  Future<void> deleteImagesExcept(Set<String> keep);

  /// Small documents kept beside the thoughts, such as settings. Null when
  /// [name] was never written, or was written null.
  Future<String?> readValue(String name);
  Future<void> writeValue(String name, String? value);
}

String encodeThoughts(List<Thought> thoughts) => jsonEncode(thoughts);

List<Thought> decodeThoughts(String json) => [
  for (final item in jsonDecode(json) as List<dynamic>)
    Thought.fromJson(item as Map<String, dynamic>),
];

/// Names an image after its content, so pasting the same image twice gives
/// the same name. Hashed off the UI thread where the platform allows it.
Future<String> imageNameFor(Uint8List bytes) => compute(_hash, bytes);

String _hash(Uint8List bytes) => '${sha256.convert(bytes)}';
