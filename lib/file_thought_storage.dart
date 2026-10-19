import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'thought.dart';
import 'thought_storage.dart';

Future<ThoughtStorage> openThoughtStorage() async =>
    FileThoughtStorage(await getApplicationSupportDirectory());

class FileThoughtStorage implements ThoughtStorage {
  FileThoughtStorage(this.directory);

  final Directory directory;

  File get _thoughts => File('${directory.path}/thoughts.json');
  Directory get _images => Directory('${directory.path}/images');

  @override
  Future<List<Thought>> read() async {
    if (!await _thoughts.exists()) return [];
    return decodeThoughts(await _thoughts.readAsString());
  }

  @override
  Future<void> write(List<Thought> thoughts) =>
      _writeAtomically(_thoughts, utf8.encode(encodeThoughts(thoughts)));

  @override
  Future<String> saveImage(Uint8List bytes) async {
    final name = await imageNameFor(bytes);
    final file = File('${_images.path}/$name');
    if (!await file.exists()) {
      await _images.create(recursive: true);
      await _writeAtomically(file, bytes);
    }
    return name;
  }

  @override
  Future<Uint8List> readImage(String name) =>
      File('${_images.path}/$name').readAsBytes();

  @override
  Future<void> deleteImagesExcept(Set<String> keep) async {
    if (!await _images.exists()) return;
    await for (final entity in _images.list()) {
      if (!keep.contains(entity.uri.pathSegments.last)) await entity.delete();
    }
  }

  File _value(String name) => File('${directory.path}/$name.json');

  @override
  Future<String?> readValue(String name) async {
    final file = _value(name);
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> writeValue(String name, String? value) async {
    final file = _value(name);
    if (value != null) {
      await _writeAtomically(file, utf8.encode(value));
    } else if (await file.exists()) {
      await file.delete();
    }
  }
}

// Write then rename, so a crash mid-write never leaves a truncated file.
Future<void> _writeAtomically(File file, List<int> bytes) async {
  final temp = File('${file.path}.tmp');
  await temp.writeAsBytes(bytes, flush: true);
  await temp.rename(file.path);
}
