import 'dart:collection';

import 'package:flutter/foundation.dart';

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
  }

  Thought? add(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final now = DateTime.now();
    final thought = Thought(
      id: '${now.microsecondsSinceEpoch}',
      text: trimmed,
      createdAt: now,
    );
    _thoughts.insert(0, thought);
    _changed();
    return thought;
  }

  void update(String id, String text) {
    final trimmed = text.trim();
    final index = _thoughts.indexWhere((t) => t.id == id);
    if (index == -1 || trimmed.isEmpty) return;
    _thoughts[index] = _thoughts[index].copyWith(text: trimmed);
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
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'headroom',
          ),
        );
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
