import 'dart:convert';

import 'report_error.dart';
import 'thought_storage.dart';

/// Where the list was last left, so the app opens there again.
class ListSettings {
  ListSettings(this._storage);

  final ThoughtStorage _storage;
  String? _theme;

  /// The theme the list keeps to, '' for the thoughts without one. Null
  /// lists them all.
  String? get theme => _theme;

  set theme(String? value) {
    _theme = value;
    _save();
  }

  Future<void> load() async {
    try {
      if (await _storage.readValue('list') case final String json) {
        _theme = (jsonDecode(json) as Map<String, dynamic>)['theme'] as String?;
      }
    } catch (error, stack) {
      reportError(error, stack);
    }
  }

  Future<void> _save() async {
    try {
      await _storage.writeValue('list', jsonEncode({'theme': ?_theme}));
    } catch (error, stack) {
      reportError(error, stack);
    }
  }
}
