import 'package:intl/intl.dart';

import 'l10n/app_localizations.dart';

String relativeTime(DateTime then, DateTime now, AppLocalizations l10n) {
  final elapsed = now.difference(then);
  if (elapsed.inMinutes < 1) return l10n.justNow;
  if (elapsed.inHours < 1) return l10n.minutesAgo(elapsed.inMinutes);

  // UTC dates so a DST change never turns one calendar day into 23 hours.
  final days = DateTime.utc(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime.utc(then.year, then.month, then.day)).inDays;
  if (days == 0) return l10n.hoursAgo(elapsed.inHours);
  if (days == 1) return l10n.yesterday;
  if (days < 7) return l10n.daysAgo(days);

  final format = then.year == now.year
      ? DateFormat.MMMd(l10n.localeName)
      : DateFormat.yMMMd(l10n.localeName);
  return format.format(then);
}
