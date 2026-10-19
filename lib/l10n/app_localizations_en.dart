// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get captureHint => 'What\'s on your mind?';

  @override
  String get captureButton => 'Note it';

  @override
  String get emptyList => 'What you note shows up here.';

  @override
  String get saveFailed =>
      'Couldn\'t save to this device. Retrying on your next change.';

  @override
  String get thoughtDeleted => 'Thought deleted';

  @override
  String get undo => 'Undo';

  @override
  String get delete => 'Delete';

  @override
  String get editTitle => 'Edit thought';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get justNow => 'just now';

  @override
  String minutesAgo(int count) {
    return '$count min ago';
  }

  @override
  String hoursAgo(int count) {
    return '$count h ago';
  }

  @override
  String get yesterday => 'yesterday';

  @override
  String daysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }
}
