import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'report_error.dart';
import 'stored_image.dart';
import 'thought.dart';
import 'thought_storage.dart';

class ThoughtStore extends ChangeNotifier {
  ThoughtStore(this._storage);

  final ThoughtStorage _storage;
  final List<Thought> _thoughts = [];
  Future<void> _pendingWrite = Future.value();
  bool _saveFailed = false;

  /// Newest first.
  List<Thought> get thoughts => UnmodifiableListView(_thoughts);

  bool get saveFailed => _saveFailed;

  Future<void> load() async {
    _thoughts
      ..clear()
      ..addAll(await _storage.read());
    notifyListeners();
    // Drops images pasted but never sent, and those of deleted thoughts.
    // Done here rather than on delete so that undo keeps working.
    try {
      await _storage.deleteImagesExcept({for (final t in _thoughts) ?t.image});
    } catch (error, stack) {
      reportError(error, stack);
    }
  }

  /// Returns the name to pass to [add].
  Future<String> saveImage(Uint8List bytes) => _storage.saveImage(bytes);

  ImageProvider imageNamed(String name) => StoredImage(_storage, name);

  /// Needs a non-blank [text], an [image], or both.
  Thought? add(String text, {String? image}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty && image == null) return null;
    final now = DateTime.now();
    final thought = Thought(
      id: '${now.microsecondsSinceEpoch}',
      text: trimmed,
      image: image,
      createdAt: now,
    );
    _thoughts.insert(0, thought);
    _changed();
    return thought;
  }

  /// Needs a non-blank [text], an [image], or both. A replaced or removed
  /// image is deleted at the next [load].
  void update(String id, {required String text, required String? image}) {
    final index = _thoughts.indexWhere((t) => t.id == id);
    final trimmed = text.trim();
    if (index == -1 || (trimmed.isEmpty && image == null)) return;
    final thought = _thoughts[index];
    _thoughts[index] = Thought(
      id: thought.id,
      text: trimmed,
      image: image,
      createdAt: thought.createdAt,
    );
    _changed();
  }

  /// Returns the index the thought was at, to pass back to [restore].
  int remove(String id) {
    final index = _thoughts.indexWhere((t) => t.id == id);
    if (index == -1) return -1;
    _thoughts.removeAt(index);
    _changed();
    return index;
  }

  /// Returns the index the thought was put back at.
  int restore(Thought thought, int index) {
    final at = index.clamp(0, _thoughts.length);
    _thoughts.insert(at, thought);
    _changed();
    return at;
  }

  /// Completes once every change made so far has been written.
  Future<void> flush() => _pendingWrite;

  void _changed() {
    notifyListeners();
    final snapshot = List.of(_thoughts);
    // Each write carries the full list, so a failed write is healed by the next one.
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        await _storage.write(snapshot);
        _setSaveFailed(false);
      } catch (error, stack) {
        reportError(error, stack);
        _setSaveFailed(true);
      }
    });
  }

  void _setSaveFailed(bool value) {
    if (_saveFailed == value) return;
    _saveFailed = value;
    notifyListeners();
  }
}
