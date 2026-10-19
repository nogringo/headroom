import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/l10n/app_localizations.dart';
import 'package:headroom/relative_time.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(initializeDateFormatting);

  final now = DateTime(2026, 10, 19, 15, 0);
  final en = lookupAppLocalizations(const Locale('en'));
  final fr = lookupAppLocalizations(const Locale('fr'));

  String age(Duration ago, AppLocalizations l10n) =>
      relativeTime(now.subtract(ago), now, l10n);

  test('English', () {
    expect(age(const Duration(seconds: 20), en), 'just now');
    expect(age(const Duration(minutes: 12), en), '12 min ago');
    expect(age(const Duration(hours: 3), en), '3 h ago');
    expect(age(const Duration(hours: 20), en), 'yesterday');
    expect(age(const Duration(days: 4), en), '4 days ago');
    expect(age(const Duration(days: 10), en), 'Oct 9');
    expect(relativeTime(DateTime(2025, 3, 2), now, en), 'Mar 2, 2025');
  });

  test('French', () {
    expect(age(const Duration(seconds: 20), fr), "à l'instant");
    expect(age(const Duration(minutes: 12), fr), 'il y a 12 min');
    expect(age(const Duration(hours: 3), fr), 'il y a 3 h');
    expect(age(const Duration(hours: 20), fr), 'hier');
    expect(age(const Duration(days: 4), fr), 'il y a 4 jours');
    expect(age(const Duration(days: 10), fr), '9 oct.');
    expect(relativeTime(DateTime(2025, 3, 2), now, fr), '2 mars 2025');
  });
}
