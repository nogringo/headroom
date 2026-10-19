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

/// Sorts new thoughts into themes and looks for some to clean up, on its own,
/// with the AI the person set up. Themes apply at once; clean-ups wait in
/// [suggestions] for the person to accept or decline.
class Tidier extends ChangeNotifier {
  Tidier(
    this._store,
    this._storage, {
    http.Client? client,
    this.delay = const Duration(seconds: 2),
  }) : _client = TidyClient(client ?? http.Client());

  final ThoughtStore _store;
  final ThoughtStorage _storage;
  final TidyClient _client;

  /// From a change to the pass it triggers, so a burst of thoughts goes in one.
  final Duration delay;

  /// The most thoughts sorted in one pass, which keeps replies short.
  static const batch = 50;

  /// How often the whole list is looked over when nothing new comes in.
  static const recheck = Duration(days: 1);

  AiSettings? _settings;
  var _suggestions = <Suggestion>[];
  var _declined = <Suggestion>[];
  DateTime? _checkedAt;
  var _working = false;
  var _pending = false;
  TidyFailure? _failure;
  String? _failureMessage;
  Timer? _timer;

  /// Bumped by [configure], so a pass started before is ignored.
  var _generation = 0;

  /// Thoughts the AI was asked to sort but left out. Not asked again until
  /// the app restarts, or every pass would ask.
  final _unsorted = <String>{};

  AiSettings? get settings => _settings;
  bool get working => _working;
  TidyFailure? get failure => _failure;

  /// What the service said about the [failure], when it said something.
  String? get failureMessage => _failureMessage;
  List<Suggestion> get suggestions => UnmodifiableListView(_suggestions);

  Future<void> load() async {
    try {
      if (await _storage.readValue('ai') case final String json) {
        _settings = AiSettings.fromJson(jsonDecode(json));
      }
      if (await _storage.readValue('tidy') case final String json) {
        final state = jsonDecode(json) as Map<String, dynamic>;
        _checkedAt = DateTime.tryParse(state['checkedAt'] as String? ?? '');
        _suggestions = _suggestionsIn(state['suggestions']);
        _declined = _suggestionsIn(state['declined']);
      }
    } catch (error, stack) {
      reportError(error, stack);
    }
    _store.addListener(_storeChanged);
    _storeChanged();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _store.removeListener(_storeChanged);
    super.dispose();
  }

  /// Null turns tidying off and forgets the suggestions.
  Future<void> configure(AiSettings? settings) async {
    _settings = settings;
    _generation++;
    _failure = null;
    _failureMessage = null;
    _unsorted.clear();
    if (settings == null) _suggestions = [];
    notifyListeners();
    _schedule(now: true);
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

  Future<List<String>> models(AiSettings settings) => _client.models(settings);

  void retry() => _schedule(now: true);

  /// Not suggested again, nor anything it [Suggestion.covers].
  void decline(Suggestion suggestion) {
    _suggestions.remove(suggestion);
    _declined.add(suggestion);
    notifyListeners();
    _saveState();
  }

  void _storeChanged() {
    final ids = {for (final thought in _store.thoughts) thought.id};
    final kept = [
      for (final s in _suggestions)
        if (s.ids.every(ids.contains)) s,
    ];
    if (kept.length != _suggestions.length) {
      _suggestions = kept;
      notifyListeners();
      _saveState();
    }
    _schedule();
  }

  bool get _due {
    final thoughts = _store.thoughts.where((t) => t.text.isNotEmpty);
    if (_settings == null || thoughts.isEmpty) return false;
    final checkedAt = _checkedAt;
    return thoughts.any((t) => t.theme == null && !_unsorted.contains(t.id)) ||
        checkedAt == null ||
        DateTime.now().difference(checkedAt) >= recheck;
  }

  void _schedule({bool now = false}) {
    if (!_due) return;
    _timer?.cancel();
    _timer = Timer(now ? Duration.zero : delay, _run);
  }

  Future<void> _run() async {
    final settings = _settings;
    if (settings == null) return;
    if (_working) {
      _pending = true;
      return;
    }
    final generation = _generation;
    final thoughts = [
      for (final thought in _store.thoughts)
        if (thought.text.isNotEmpty) thought,
    ];
    // Oldest first, so a long backlog is sorted in the order it was noted.
    final toSort = thoughts.reversed
        .where((t) => t.theme == null && !_unsorted.contains(t.id))
        .take(batch)
        .map((t) => t.id)
        .toSet();
    _working = true;
    _failure = null;
    _failureMessage = null;
    notifyListeners();
    try {
      final tidied = await _client.tidy(
        settings,
        thoughts: thoughts,
        toSort: toSort,
        now: DateTime.now(),
      );
      if (generation == _generation) _apply(tidied, thoughts, toSort);
    } on TidyException catch (error, stack) {
      if (generation == _generation) {
        _failure = error.failure;
        _failureMessage = error.message;
        // A wrong key or address is the person's to fix, not a bug.
        if (error.failure == TidyFailure.failed) reportError(error, stack);
      }
    } catch (error, stack) {
      if (generation == _generation) _failure = TidyFailure.failed;
      reportError(error, stack);
    } finally {
      _working = false;
      notifyListeners();
    }
    if (_failure == null || _pending) {
      _pending = false;
      _schedule(now: true);
    }
  }

  void _apply(Tidied tidied, List<Thought> sent, Set<String> toSort) {
    // A thought edited during the pass was sorted on its old text.
    final sentText = {for (final thought in sent) thought.id: thought.text};
    final current = {
      for (final thought in _store.thoughts) thought.id: thought.text,
    };
    _unsorted.addAll(toSort.where((id) => !tidied.themes.containsKey(id)));
    for (final suggestion in tidied.suggestions) {
      if (suggestion.ids.any((id) => current[id] != sentText[id])) continue;
      if ([..._suggestions, ..._declined].any((s) => s.covers(suggestion))) {
        continue;
      }
      _suggestions.add(suggestion);
    }
    _checkedAt = DateTime.now();
    _store.setThemes({
      for (final MapEntry(:key, :value) in tidied.themes.entries)
        if (current[key] == sentText[key]) key: value,
    });
    notifyListeners();
    _saveState();
  }

  Future<void> _saveState() async {
    final ids = {for (final thought in _store.thoughts) thought.id};
    _declined.removeWhere((s) => !s.ids.any(ids.contains));
    try {
      await _storage.writeValue(
        'tidy',
        jsonEncode({
          'checkedAt': ?_checkedAt?.toUtc().toIso8601String(),
          'suggestions': _suggestions,
          'declined': _declined,
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
