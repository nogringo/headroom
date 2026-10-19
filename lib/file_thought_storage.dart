import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'thought.dart';
import 'thought_storage.dart';

Future<ThoughtStorage> openThoughtStorage() async {
  final directory = await getApplicationSupportDirectory();
  return FileThoughtStorage(File('${directory.path}/thoughts.json'));
}

class FileThoughtStorage implements ThoughtStorage {
  FileThoughtStorage(this.file);

  final File file;

  @override
  Future<List<Thought>> read() async {
    if (!await file.exists()) return [];
    return decodeThoughts(await file.readAsString());
  }

  @override
  Future<void> write(List<Thought> thoughts) async {
    // Write then rename, so a crash mid-write never leaves a truncated file.
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(encodeThoughts(thoughts), flush: true);
    await temp.rename(file.path);
  }
}
