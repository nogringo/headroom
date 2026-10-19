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
  String get today => 'Aujourd\'hui';

  @override
  String get yesterday => 'Hier';

  @override
  String get pasteImage => 'Coller l\'image';

  @override
  String get noImageInClipboard => 'Aucune image dans le presse-papier.';

  @override
  String get imageNotAdded => 'Impossible d\'ajouter l\'image.';

  @override
  String get removeImage => 'Retirer l\'image';

  @override
  String get imageLabel => 'Image';

  @override
  String get previousImage => 'Image précédente';

  @override
  String get nextImage => 'Image suivante';

  @override
  String get imageAlreadyAdded => 'Image déjà ajoutée.';

  @override
  String get copyImage => 'Copier l\'image';

  @override
  String get imageCopied => 'Image copiée';

  @override
  String get imageNotCopied => 'Impossible de copier l\'image.';

  @override
  String get byDay => 'Par jour';

  @override
  String get byTheme => 'Par thème';

  @override
  String get noTheme => 'Sans thème';

  @override
  String get tidySettings => 'Rangement par IA';

  @override
  String get tidying => 'Rangement en cours';

  @override
  String get tidyIntro =>
      'Une IA de ton choix range tes pensées par thème au fil de l\'eau, et repère celles à fusionner ou à effacer. Tout service compatible avec l\'API d\'OpenAI fonctionne, y compris un modèle qui tourne sur ton ordinateur.';

  @override
  String get tidyAddress => 'Adresse de l\'API';

  @override
  String get tidyAddressInvalid =>
      'Saisis une adresse qui commence par https:// ou http://';

  @override
  String get tidyKey => 'Clé API';

  @override
  String get tidyKeyHelp => 'Inutile pour un modèle local';

  @override
  String get showKey => 'Afficher la clé';

  @override
  String get hideKey => 'Masquer la clé';

  @override
  String get tidyModel => 'Modèle';

  @override
  String get tidyPrivacy =>
      'Le texte de tes pensées est envoyé à ce service. Les images restent sur l\'appareil.';

  @override
  String get turnOff => 'Désactiver';

  @override
  String get tidyUnreachable => 'Rangement en pause : service IA injoignable.';

  @override
  String get tidyRejectedKey => 'Rangement en pause : clé API refusée.';

  @override
  String get tidyNotFound =>
      'Rangement en pause : adresse ou modèle introuvable.';

  @override
  String get tidyLimited =>
      'Rangement en pause : limite ou crédit épuisé chez le service IA.';

  @override
  String get tidyFailed =>
      'Rangement en pause : réponse inattendue du service IA.';

  @override
  String get retry => 'Réessayer';

  @override
  String get cleanUp => 'Ménage';

  @override
  String suggestionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count propositions',
      one: '1 proposition',
    );
    return '$_temp0';
  }

  @override
  String get mergeIntro => 'Ces pensées se répètent :';

  @override
  String get mergeResult => 'Fusionnées, elles deviendraient :';

  @override
  String get keepApart => 'Garder séparées';

  @override
  String get merge => 'Fusionner';

  @override
  String get outdatedIntro => 'Cette pensée semble dépassée :';

  @override
  String get keep => 'Garder';

  @override
  String get thoughtsMerged => 'Pensées fusionnées';
}
