import 'package:intl/intl.dart';

import 'l10n/app_localizations.dart';

/// The heading above the thoughts noted on [day].
String dayLabel(DateTime day, DateTime now, AppLocalizations l10n) {
  // UTC dates so a DST change never turns one calendar day into 23 hours.
  final days = DateTime.utc(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime.utc(day.year, day.month, day.day)).inDays;
  if (days == 0) return l10n.today;
  if (days == 1) return l10n.yesterday;

  final format = switch (days) {
    > 1 && < 7 => DateFormat.EEEE(l10n.localeName),
    _ when day.year == now.year => DateFormat.MMMMd(l10n.localeName),
    _ => DateFormat.yMMMMd(l10n.localeName),
  };
  final label = format.format(day);
  // French weekdays and months are lowercase.
  return label[0].toUpperCase() + label.substring(1);
}
