import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'report_error.dart';
import 'thought.dart';
import 'thought_storage.dart';
import 'thought_store.dart';
import 'tidy_client.dart';

/// Has the AI the person set up describe each thought they note: its themes,
/// and a title and subtasks when it needs some. Asked, it looks for thoughts
/// to clean up and keeps them in [suggestions] for the person to accept or
/// decline. It asks nothing else, to keep the bill small.
class Tidier extends ChangeNotifier {
  Tidier(this._store, this._storage, {http.Client? client})
    : _client = TidyClient(client ?? http.Client());

  final ThoughtStore _store;
  final ThoughtStorage _storage;
  final TidyClient _client;

  /// The most thoughts sent to show how the person sorts.
  static const examples = 20;

  AiSettings? _settings;
  var _suggestions = <Suggestion>[];
  var _declined = <Suggestion>[];

  /// Thoughts noted but not described yet, oldest first. Saved, so one noted
  /// offline goes at the next launch.
  var _queue = <String>[];

  /// Set while a clean-up waits or runs.
  Completer<int?>? _cleanUp;
  var _running = false;
  var _cleaning = false;
  var _cleanUpFailed = false;
  TidyFailure? _failure;
  String? _failureMessage;

  /// Bumped by [configure], so a reply to the settings before is ignored.
  var _generation = 0;

  AiSettings? get settings => _settings;
  bool get cleaning => _cleaning;
  TidyFailure? get failure => _failure;

  /// What the service said about the [failure], when it said something.
  String? get failureMessage => _failureMessage;

  /// Whether the [failure] stopped a clean-up, which [cleanUp] tries again.
  bool get cleanUpFailed => _cleanUpFailed;
  List<Suggestion> get suggestions => UnmodifiableListView(_suggestions);
  List<Suggestion> get declined => UnmodifiableListView(_declined);

  /// Whether [thought] is waiting for the themes the AI is about to give it.
  bool willSort(Thought thought) =>
      _settings != null && _failure == null && _queue.contains(thought.id);

  Future<void> load() async {
    try {
      if (await _storage.readValue('ai') case final String json) {
        _settings = AiSettings.fromJson(jsonDecode(json));
      }
      if (await _storage.readValue('tidy') case final String json) {
        final state = jsonDecode(json) as Map<String, dynamic>;
        _suggestions = _suggestionsIn(state['suggestions']);
        _declined = _suggestionsIn(state['declined']);
        _queue = [...?(state['queue'] as List<dynamic>?)?.cast<String>()];
      }
    } catch (error, stack) {
      reportError(error, stack);
    }
    _store.addListener(_storeChanged);
    _storeChanged();
    _run();
  }

  @override
  void dispose() {
    _store.removeListener(_storeChanged);
    super.dispose();
  }

  /// Null turns the AI off and forgets the suggestions.
  Future<void> configure(AiSettings? settings) async {
    _settings = settings;
    _generation++;
    _failure = null;
    _failureMessage = null;
    _cleanUpFailed = false;
    if (settings == null) {
      _suggestions = [];
      _queue = [];
      _cleanUp?.complete(null);
      _cleanUp = null;
    }
    notifyListeners();
    _run();
    try {
      await _storage.writeValue(
        'ai',
        settings == null ? null : jsonEncode(settings),
      );
      await _saveState();
    } catch (error, stack) {
      reportError(error, stack);
    }
  }

  /// Takes a backup's AI unless one is set up here, and the clean-ups it
  /// declined. Returns whether it took the AI.
  Future<bool> restore(AiSettings? settings, List<Suggestion> declined) async {
    _declined.addAll([
      for (final suggestion in declined)
        if (!_declined.any((d) => d.covers(suggestion))) suggestion,
    ]);
    _suggestions.removeWhere((s) => _declined.any((d) => d.covers(s)));
    if (settings != null && _settings == null) {
      await configure(settings);
      return true;
    }
    notifyListeners();
    await _saveState();
    return false;
  }

  Future<List<String>> models(AiSettings settings) => _client.models(settings);

  /// Has the AI describe [thought], just noted.
  void noted(Thought thought) {
    if (_settings == null || thought.text.isEmpty) return;
    _queue.add(thought.id);
    _saveState();
    _run();
  }

  /// Has the AI look over every thought for some to merge or delete. Returns
  /// how many new suggestions it made, or null when it failed.
  Future<int?> cleanUp() {
    if (_settings == null) return Future.value();
    final request = _cleanUp ??= Completer();
    _cleanUpFailed = false;
    _run();
    return request.future;
  }

  void retry() => _run();

  /// Not suggested again, nor anything it [Suggestion.covers].
  void decline(Suggestion suggestion) {
    _suggestions.remove(suggestion);
    _declined.add(suggestion);
    notifyListeners();
    _saveState();
  }

  void _storeChanged() {
    final ids = {for (final thought in _store.thoughts) thought.id};
    final suggestions = [
      for (final s in _suggestions)
        if (s.ids.every(ids.contains)) s,
    ];
    final queue = [
      for (final id in _queue)
        if (ids.contains(id)) id,
    ];
    if (suggestions.length == _suggestions.length &&
        queue.length == _queue.length) {
      return;
    }
    _suggestions = suggestions;
    _queue = queue;
    notifyListeners();
    _saveState();
  }

  /// Works through the queue, then the clean-up asked for, until done or
  /// stopped by a failure.
  Future<void> _run() async {
    if (_running) return;
    _running = true;
    _failure = null;
    _failureMessage = null;
    notifyListeners();
    try {
      while (_failure == null) {
        final settings = _settings;
        if (settings == null) break;
        if (_queue.isNotEmpty) {
          await _describe(settings, _queue.first);
        } else if (_cleanUp != null) {
          await _lookForCleanUps(settings);
        } else {
          break;
        }
      }
    } finally {
      if (_failure != null && _cleanUp != null) {
        _cleanUp!.complete(null);
        _cleanUp = null;
        _cleanUpFailed = true;
      }
      _running = false;
      notifyListeners();
    }
  }

  Future<void> _describe(AiSettings settings, String id) async {
    final generation = _generation;
    final thought = _store.thoughts.where((t) => t.id == id).firstOrNull;
    if (thought == null || thought.text.isEmpty) {
      _queue.remove(id);
      await _saveState();
      return;
    }
    final described = await _asking(
      generation,
      () => _client.describe(
        settings,
        thought,
        themes: _store.themes.toList(),
        chosen: [
          for (final t in _store.thoughts)
            if (t.themesChosen && t.themes.isNotEmpty) t,
        ].take(examples).toList(),
      ),
    );
    if (described == null) return;
    // Applied even to a thought edited meanwhile: it is not asked about again.
    _store.annotate(
      id,
      themes: described.themes,
      title: described.title,
      subtasks: described.subtasks,
    );
    _queue.remove(id);
    notifyListeners();
    await _saveState();
  }

  Future<void> _lookForCleanUps(AiSettings settings) async {
    final generation = _generation;
    final sent = [
      for (final thought in _store.thoughts)
        if (thought.text.isNotEmpty) thought,
    ];
    _cleaning = true;
    notifyListeners();
    final found = sent.isEmpty
        ? <Suggestion>[]
        : await _asking(
            generation,
            () =>
                _client.cleanUp(settings, thoughts: sent, now: DateTime.now()),
          );
    _cleaning = false;
    if (found == null) return;
    // A thought edited meanwhile was looked at in its old words.
    final sentText = {for (final thought in sent) thought.id: thought.text};
    final current = {
      for (final thought in _store.thoughts) thought.id: thought.text,
    };
    var added = 0;
    for (final suggestion in found) {
      if (suggestion.ids.any((id) => current[id] != sentText[id])) continue;
      if ([..._suggestions, ..._declined].any((s) => s.covers(suggestion))) {
        continue;
      }
      _suggestions.add(suggestion);
      added++;
    }
    _cleanUp?.complete(added);
    _cleanUp = null;
    notifyListeners();
    await _saveState();
  }

  /// The reply to [ask], or null when it failed, which sets [failure], or
  /// came for settings since replaced.
  Future<T?> _asking<T>(int generation, Future<T> Function() ask) async {
    try {
      final reply = await ask();
      return generation == _generation ? reply : null;
    } on TidyException catch (error, stack) {
      if (generation != _generation) return null;
      _failure = error.failure;
      _failureMessage = error.message;
      // A wrong key or address is the person's to fix, not a bug.
      if (error.failure == TidyFailure.failed) reportError(error, stack);
    } catch (error, stack) {
      if (generation == _generation) _failure = TidyFailure.failed;
      reportError(error, stack);
    }
    return null;
  }

  Future<void> _saveState() async {
    final ids = {for (final thought in _store.thoughts) thought.id};
    _declined.removeWhere((s) => !s.ids.any(ids.contains));
    try {
      await _storage.writeValue(
        'tidy',
        jsonEncode({
          'suggestions': _suggestions,
          'declined': _declined,
          if (_queue.isNotEmpty) 'queue': _queue,
        }),
      );
    } catch (error, stack) {
      reportError(error, stack);
    }
  }
}

List<Suggestion> _suggestionsIn(Object? json) => [
  if (json case final List<dynamic> list)
    for (final item in list) Suggestion.fromJson(item as Map<String, dynamic>),
];
