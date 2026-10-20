import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'report_error.dart';
import 'thought_storage.dart';

/// Where the list was last left, so the app opens there again, and the order
/// the person put the themes in.
class ListSettings extends ChangeNotifier {
  ListSettings(this._storage);

  final ThoughtStorage _storage;
  String? _theme;
  var _themeOrder = <String>[];

  /// The theme the list keeps to, '' for the thoughts without one. Null
  /// lists them all.
  String? get theme => _theme;

  set theme(String? value) {
    _theme = value;
    _changed();
  }

  /// The themes as the person ordered them. Empty until they do.
  List<String> get themeOrder => UnmodifiableListView(_themeOrder);

  set themeOrder(List<String> value) {
    _themeOrder = List.of(value);
    _changed();
  }

  /// Gives [to] the place of [from], unless [to] already has one.
  void renameTheme(String from, String to) {
    final index = _themeOrder.indexOf(from);
    if (index == -1) return;
    if (_themeOrder.contains(to)) {
      _themeOrder.removeAt(index);
    } else {
      _themeOrder[index] = to;
    }
    _changed();
  }

  /// Places the themes of a backup's [order] that this one lacks after
  /// its own, in the backup's order.
  void restoreThemeOrder(List<String> order) {
    final missing = [
      for (final theme in order)
        if (!_themeOrder.contains(theme)) theme,
    ];
    if (missing.isEmpty) return;
    _themeOrder.addAll(missing);
    _changed();
  }

  Future<void> load() async {
    try {
      if (await _storage.readValue('list') case final String json) {
        final settings = jsonDecode(json) as Map<String, dynamic>;
        _theme = settings['theme'] as String?;
        _themeOrder = [
          ...?(settings['themeOrder'] as List<dynamic>?)?.cast<String>(),
        ];
      }
    } catch (error, stack) {
      reportError(error, stack);
    }
  }

  void _changed() {
    notifyListeners();
    _save();
  }

  Future<void> _save() async {
    try {
      await _storage.writeValue(
        'list',
        jsonEncode({
          'theme': ?_theme,
          if (_themeOrder.isNotEmpty) 'themeOrder': _themeOrder,
        }),
      );
    } catch (error, stack) {
      reportError(error, stack);
    }
  }
}
