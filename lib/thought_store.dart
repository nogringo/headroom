import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'report_error.dart';
import 'stored_image.dart';
import 'thought.dart';
import 'thought_storage.dart';

/// The thought a [ThoughtStore.merge] made, and those it replaced with the
/// index each was at, in list order.
typedef Merged = ({
  Thought merged,
  List<({int index, Thought thought})> originals,
});

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
      await _storage.deleteImagesExcept({
        for (final t in _thoughts) ...t.images,
      });
    } catch (error, stack) {
      reportError(error, stack);
    }
  }

  /// Returns the name to pass to [add].
  Future<String> saveImage(Uint8List bytes) => _storage.saveImage(bytes);

  ImageProvider imageNamed(String name) => StoredImage(_storage, name);

  Future<Uint8List> readImage(String name) => _storage.readImage(name);

  /// Needs a non-blank [text], some [images], or both.
  Thought? add(String text, {List<String> images = const []}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty && images.isEmpty) return null;
    final now = DateTime.now();
    final thought = Thought(
      id: '${now.microsecondsSinceEpoch}',
      text: trimmed,
      images: images,
      createdAt: now,
    );
    _thoughts.insert(0, thought);
    _changed();
    return thought;
  }

  /// Needs a non-blank [text], some [images], or both. A removed image is
  /// deleted at the next [load]. New text drops the theme the AI gave, to be
  /// sorted again.
  void update(String id, {required String text, required List<String> images}) {
    final index = _thoughts.indexWhere((t) => t.id == id);
    final trimmed = text.trim();
    if (index == -1 || (trimmed.isEmpty && images.isEmpty)) return;
    final thought = _thoughts[index];
    final keepsTheme = thought.themeChosen || trimmed == thought.text;
    _thoughts[index] = Thought(
      id: thought.id,
      text: trimmed,
      images: images,
      createdAt: thought.createdAt,
      theme: keepsTheme ? thought.theme : null,
      themeChosen: thought.themeChosen,
    );
    _changed();
  }

  /// Gives each thought named in [themes] the theme the AI found for it.
  /// Unknown ids and themes the person chose are skipped.
  void setThemes(Map<String, String> themes) {
    var changed = false;
    for (final (index, thought) in _thoughts.indexed) {
      final theme = themes[thought.id];
      if (theme == null || theme == thought.theme || thought.themeChosen) {
        continue;
      }
      _thoughts[index] = _withTheme(thought, theme);
      changed = true;
    }
    if (changed) _changed();
  }

  /// Puts the thought in the [theme] the person chose. Null hands it back to
  /// the AI.
  void chooseTheme(String id, String? theme) {
    final index = _thoughts.indexWhere((t) => t.id == id);
    if (index == -1) return;
    _thoughts[index] = _withTheme(
      _thoughts[index],
      theme,
      chosen: theme != null,
    );
    _changed();
  }

  /// Moves every thought of [from] to [to], which may already hold some.
  void renameTheme(String from, String to) {
    if (from == to) return;
    var changed = false;
    for (final (index, thought) in _thoughts.indexed) {
      if (thought.theme != from) continue;
      _thoughts[index] = _withTheme(thought, to, chosen: thought.themeChosen);
      changed = true;
    }
    if (changed) _changed();
  }

  /// Replaces the thoughts [ids] with one holding [text] and all their
  /// images. It takes the place, id and theme of the newest. Returns what
  /// [unmerge] needs, or null when fewer than two of the thoughts are left.
  Merged? merge(List<String> ids, String text) {
    final trimmed = text.trim();
    final originals = [
      for (final (index, thought) in _thoughts.indexed)
        if (ids.contains(thought.id)) (index: index, thought: thought),
    ];
    if (originals.length < 2 || trimmed.isEmpty) return null;
    final newest = originals.first;
    final merged = Thought(
      id: newest.thought.id,
      text: trimmed,
      images: {for (final o in originals) ...o.thought.images}.toList(),
      createdAt: newest.thought.createdAt,
      theme: newest.thought.theme,
      themeChosen: newest.thought.themeChosen,
    );
    for (final o in originals.reversed) {
      _thoughts.removeAt(o.index);
    }
    _thoughts.insert(newest.index, merged);
    _changed();
    return (merged: merged, originals: originals);
  }

  /// Puts back the thoughts a [merge] replaced.
  void unmerge(Merged merged) {
    _thoughts.removeWhere((t) => t.id == merged.merged.id);
    for (final o in merged.originals) {
      _thoughts.insert(o.index.clamp(0, _thoughts.length), o.thought);
    }
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

  /// Adds the [thoughts] whose id isn't in the list, each in its place by
  /// date. Returns how many it added.
  int addMissing(Iterable<Thought> thoughts) {
    final ids = {for (final t in _thoughts) t.id};
    var added = 0;
    for (final thought in thoughts) {
      if (!ids.add(thought.id)) continue;
      final older = _thoughts.indexWhere(
        (t) => t.createdAt.isBefore(thought.createdAt),
      );
      _thoughts.insert(older == -1 ? _thoughts.length : older, thought);
      added++;
    }
    if (added > 0) _changed();
    return added;
  }

  /// Returns the index the thought was put back at.
  int restore(Thought thought, int index) {
    final at = index.clamp(0, _thoughts.length);
    _thoughts.insert(at, thought);
    _changed();
    return at;
  }

  Thought _withTheme(Thought thought, String? theme, {bool chosen = false}) =>
      Thought(
        id: thought.id,
        text: thought.text,
        images: thought.images,
        createdAt: thought.createdAt,
        theme: theme,
        themeChosen: chosen,
      );

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
