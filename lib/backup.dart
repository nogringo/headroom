import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import 'list_settings.dart';
import 'report_error.dart';
import 'thought.dart';
import 'thought_storage.dart';
import 'thought_store.dart';
import 'tidier.dart';
import 'tidy_client.dart';

/// How many thoughts a [Backup.restore] added, and whether it set up the AI.
typedef Restored = ({int thoughts, bool ai});

typedef _Contents = ({
  List<Thought> thoughts,
  Map<String, Uint8List> images,
  AiSettings? ai,
  List<Suggestion> declined,
  List<String> themeOrder,
});

/// A zip of the thoughts, their images, the AI's settings without its key,
/// the clean-ups declined and the themes' order, laid out like the storage
/// on disk.
class Backup {
  Backup(this._store, this._tidier, this._listSettings, this._storage);

  final ThoughtStore _store;
  final Tidier _tidier;
  final ListSettings _listSettings;
  final ThoughtStorage _storage;
  DateTime? _savedAt;

  /// When a copy was last saved from this device. Null if never.
  DateTime? get savedAt => _savedAt;

  /// Named after [now]'s day, so the copies sort by date.
  static String fileName(DateTime now) =>
      'headroom-${now.toIso8601String().substring(0, 10)}.zip';

  Future<void> load() async {
    try {
      if (await _storage.readValue('backup') case final String json) {
        final state = jsonDecode(json) as Map<String, dynamic>;
        _savedAt = DateTime.tryParse(state['savedAt'] as String? ?? '')
            ?.toLocal();
      }
    } catch (error, stack) {
      reportError(error, stack);
    }
  }

  Future<Uint8List> create() async {
    final thoughts = _store.thoughts;
    final files = {'thoughts.json': utf8.encode(encodeThoughts(thoughts))};
    for (final name in {for (final t in thoughts) ...t.images}) {
      try {
        final bytes = await _store.readImage(name);
        files['images/$name${_extensionOf(bytes)}'] = bytes;
      } catch (error, stack) {
        // A copy missing one lost image beats no copy.
        reportError(error, stack);
      }
    }
    if (_tidier.settings case final ai?) {
      // Not the key, which has no place in a file left in a cloud.
      files['ai.json'] = utf8.encode(
        jsonEncode({'baseUrl': ai.baseUrl, 'model': ai.model}),
      );
    }
    if (_tidier.declined.isNotEmpty) {
      files['tidy.json'] = utf8.encode(
        jsonEncode({'declined': _tidier.declined}),
      );
    }
    // Not the theme open, which belongs to this device.
    if (_listSettings.themeOrder.isNotEmpty) {
      files['list.json'] = utf8.encode(
        jsonEncode({'themeOrder': _listSettings.themeOrder}),
      );
    }
    return compute(_zip, files);
  }

  /// Remembers that the copy [create] made was saved.
  Future<void> saved() async {
    final now = DateTime.now();
    _savedAt = now;
    try {
      await _storage.writeValue(
        'backup',
        jsonEncode({'savedAt': now.toUtc().toIso8601String()}),
      );
    } catch (error, stack) {
      reportError(error, stack);
    }
  }

  /// Adds the thoughts missing here, with their images, and never removes
  /// or changes one. Takes the AI and the declined clean-ups as
  /// [Tidier.restore] does, and the themes' order as
  /// [ListSettings.restoreThemeOrder] does. Throws a [FormatException] when
  /// [zip] is not a backup.
  Future<Restored> restore(Uint8List zip) async {
    final contents = await _read(zip);
    // Saved under the name of their content, whatever the zip calls them.
    final names = {
      for (final MapEntry(key: name, value: bytes) in contents.images.entries)
        name: await _store.saveImage(bytes),
    };
    final added = _store.addMissing([
      for (final t in contents.thoughts)
        t.copyWith(images: [for (final name in t.images) names[name] ?? name]),
    ]);
    _listSettings.restoreThemeOrder(contents.themeOrder);
    final ai = await _tidier.restore(contents.ai, contents.declined);
    return (thoughts: added, ai: ai);
  }
}

Future<_Contents> _read(Uint8List zip) async {
  try {
    final files = await compute(_unzip, zip);
    Object? json(String name) => switch (files[name]) {
      final bytes? => jsonDecode(utf8.decode(bytes)),
      null => null,
    };
    final thoughts = files['thoughts.json'];
    if (thoughts == null) throw const FormatException('No thoughts.json');
    return (
      thoughts: decodeThoughts(utf8.decode(thoughts)),
      images: {
        for (final MapEntry(key: path, value: bytes) in files.entries)
          if (path.startsWith('images/'))
            path.substring('images/'.length).split('.').first: bytes,
      },
      ai: switch (json('ai.json')) {
        final Map<String, dynamic> ai => AiSettings.fromJson(ai),
        _ => null,
      },
      declined: [
        if (json('tidy.json') case {'declined': final List<dynamic> declined})
          for (final item in declined)
            Suggestion.fromJson(item as Map<String, dynamic>),
      ],
      themeOrder: [
        if (json('list.json') case {'themeOrder': final List<dynamic> order})
          for (final theme in order) theme as String,
      ],
    );
  } on FormatException {
    rethrow;
  } catch (error) {
    throw FormatException('Unreadable backup: $error');
  }
}

/// So the images open from the unzipped copy. [_read] drops it again.
String _extensionOf(Uint8List bytes) => switch (bytes) {
  [0x89, 0x50, 0x4E, 0x47, ...] => '.png',
  [0xFF, 0xD8, 0xFF, ...] => '.jpg',
  [0x47, 0x49, 0x46, ...] => '.gif',
  [0x52, 0x49, 0x46, 0x46, _, _, _, _, 0x57, 0x45, 0x42, 0x50, ...] => '.webp',
  _ => '',
};

Uint8List _zip(Map<String, Uint8List> files) {
  final archive = Archive();
  for (final MapEntry(key: name, value: bytes) in files.entries) {
    archive.add(
      // Images come compressed already.
      name.startsWith('images/')
          ? ArchiveFile.noCompress(name, bytes.length, bytes)
          : ArchiveFile.bytes(name, bytes),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

Map<String, Uint8List> _unzip(Uint8List zip) => {
  for (final file in ZipDecoder().decodeBytes(zip))
    if (file.isFile) file.name: file.content,
};
