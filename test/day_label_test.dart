import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/day_label.dart';
import 'package:headroom/l10n/app_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(initializeDateFormatting);

  // A Monday.
  final now = DateTime(2026, 10, 19, 15, 0);
  final en = lookupAppLocalizations(const Locale('en'));
  final fr = lookupAppLocalizations(const Locale('fr'));

  String label(int daysAgo, AppLocalizations l10n) =>
      dayLabel(DateTime(2026, 10, 19 - daysAgo, 9, 30), now, l10n);

  test('English', () {
    expect(label(0, en), 'Today');
    expect(label(1, en), 'Yesterday');
    expect(label(4, en), 'Thursday');
    expect(label(6, en), 'Tuesday');
    expect(label(7, en), 'October 12');
    expect(dayLabel(DateTime(2025, 3, 2), now, en), 'March 2, 2025');
  });

  test('French', () {
    expect(label(0, fr), "Aujourd'hui");
    expect(label(1, fr), 'Hier');
    expect(label(4, fr), 'Jeudi');
    expect(label(7, fr), '12 octobre');
    expect(dayLabel(DateTime(2025, 3, 2), now, fr), '2 mars 2025');
  });

  test('just after midnight, a thought from late last night is yesterday', () {
    final midnight = DateTime(2026, 10, 19, 0, 5);
    expect(dayLabel(DateTime(2026, 10, 18, 23, 55), midnight, en), 'Yesterday');
  });
}
