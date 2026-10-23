import 'dart:collection';
import 'dart:math' as math;

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
  /// deleted at the next [load]. Keeps what the AI gave the thought, which it
  /// is not asked about again.
  void update(String id, {required String text, required List<String> images}) {
    final index = _thoughts.indexWhere((t) => t.id == id);
    final trimmed = text.trim();
    if (index == -1 || (trimmed.isEmpty && images.isEmpty)) return;
    _thoughts[index] = _thoughts[index].copyWith(text: trimmed, images: images);
    _changed();
  }

  /// Gives the thought what the AI found for it, but not [themes] when the
  /// person chose its own.
  void annotate(
    String id, {
    required List<String> themes,
    String? title,
    List<String> subtasks = const [],
  }) {
    final index = _thoughts.indexWhere((t) => t.id == id);
    if (index == -1) return;
    final thought = _thoughts[index];
    _thoughts[index] = thought.copyWith(
      themes: thought.themesChosen ? null : themes,
      title: title,
      subtasks: [for (final text in subtasks) (text: text, done: false)],
    );
    _changed();
  }

  /// Puts the thought in the [themes] the person chose, none when empty.
  void chooseThemes(String id, List<String> themes) {
    final index = _thoughts.indexWhere((t) => t.id == id);
    if (index == -1) return;
    _thoughts[index] = _thoughts[index].copyWith(
      themes: themes,
      themesChosen: true,
    );
    _changed();
  }

  /// Ticks off the thought's subtask at [index], or back on.
  void toggleSubtask(String id, int index) {
    final at = _thoughts.indexWhere((t) => t.id == id);
    if (at == -1) return;
    final thought = _thoughts[at];
    if (index >= thought.subtasks.length) return;
    _thoughts[at] = thought.copyWith(
      subtasks: [
        for (final (i, subtask) in thought.subtasks.indexed)
          i == index ? (text: subtask.text, done: !subtask.done) : subtask,
      ],
    );
    _changed();
  }

  /// Moves every thought of [from] to [to], which may already hold some.
  void renameTheme(String from, String to) {
    if (from == to) return;
    var changed = false;
    for (final (index, thought) in _thoughts.indexed) {
      if (!thought.themes.contains(from)) continue;
      final ranks = {...thought.ranks};
      final rank = ranks.remove(from);
      if (rank != null && !thought.themes.contains(to)) ranks[to] = rank;
      _thoughts[index] = thought.copyWith(
        themes: {for (final theme in thought.themes) theme == from ? to : theme}
            .toList(),
        ranks: ranks,
      );
      changed = true;
    }
    if (changed) _changed();
  }

  /// Replaces the thoughts [ids] with one holding [text] and all their
  /// images and themes, with the highest rank each held in a theme. It takes
  /// the id of the newest, and no title or subtasks, which were about the
  /// old text. Returns what [unmerge] needs, or null when fewer than two of
  /// the thoughts are left.
  Merged? merge(List<String> ids, String text) {
    final trimmed = text.trim();
    final originals = [
      for (final (index, thought) in _thoughts.indexed)
        if (ids.contains(thought.id)) (index: index, thought: thought),
    ];
    if (originals.length < 2 || trimmed.isEmpty) return null;
    final newest = originals.first;
    final themes = {for (final o in originals) ...o.thought.themes}.toList();
    final merged = Thought(
      id: newest.thought.id,
      text: trimmed,
      images: {for (final o in originals) ...o.thought.images}.toList(),
      createdAt: newest.thought.createdAt,
      themes: themes,
      themesChosen: originals.any((o) => o.thought.themesChosen),
      ranks: {
        for (final theme in themes.isEmpty ? const [''] : themes)
          theme: originals.map((o) => o.thought.rankIn(theme)).reduce(math.max),
      },
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

  /// Puts the thoughts [ids] of [theme] in this order, highest first, by
  /// sharing out the ranks they hold in it among them. The other thoughts,
  /// and the other themes, keep theirs.
  void reorder(String theme, List<String> ids) {
    final indices = [
      for (final id in ids)
        if (_thoughts.indexWhere((t) => t.id == id) case final i when i != -1)
          i,
    ];
    final ranks = [for (final i in indices) _thoughts[i].rankIn(theme)]
      ..sort((a, b) => b.compareTo(a));
    var changed = false;
    for (final (place, i) in indices.indexed) {
      final thought = _thoughts[i];
      if (thought.rankIn(theme) == ranks[place]) continue;
      _thoughts[i] = thought.copyWith(
        ranks: {...thought.ranks, theme: ranks[place]},
      );
      changed = true;
    }
    if (changed) _changed();
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
