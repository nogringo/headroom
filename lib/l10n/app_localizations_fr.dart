// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get captureHint => 'Qu\'est-ce que tu as en tête ?';

  @override
  String get captureButton => 'Noter';

  @override
  String get emptyList => 'Ce que tu notes s\'affiche ici.';

  @override
  String get saveFailed =>
      'Échec de l\'enregistrement sur l\'appareil. Nouvel essai à la prochaine modification.';

  @override
  String get thoughtDeleted => 'Pensée effacée';

  @override
  String get undo => 'Annuler';

  @override
  String get delete => 'Effacer';

  @override
  String get editTitle => 'Modifier la pensée';

  @override
  String get cancel => 'Annuler';

  @override
  String get save => 'Enregistrer';

  @override
  String get justNow => 'à l\'instant';

  @override
  String minutesAgo(int count) {
    return 'il y a $count min';
  }

  @override
  String hoursAgo(int count) {
    return 'il y a $count h';
  }

  @override
  String get yesterday => 'hier';

  @override
  String daysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'il y a $count jours',
      one: 'il y a 1 jour',
    );
    return '$_temp0';
  }
}
