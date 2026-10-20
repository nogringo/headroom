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
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get pasteImage => 'Paste image';

  @override
  String get noImageInClipboard => 'No image in the clipboard.';

  @override
  String get imageNotAdded => 'Couldn\'t add the image.';

  @override
  String get removeImage => 'Remove image';

  @override
  String get imageLabel => 'Image';

  @override
  String get previousImage => 'Previous image';

  @override
  String get nextImage => 'Next image';

  @override
  String get imageAlreadyAdded => 'Image already added.';

  @override
  String get copyImage => 'Copy image';

  @override
  String get imageCopied => 'Image copied';

  @override
  String get imageNotCopied => 'Couldn\'t copy the image.';

  @override
  String get allThoughts => 'All';

  @override
  String get noTheme => 'No theme';

  @override
  String get tidySettings => 'AI tidying';

  @override
  String get tidying => 'Tidying';

  @override
  String get tidyIntro =>
      'An AI of your choice sorts your thoughts by theme as you note them, and spots the ones to merge or delete. Any service compatible with OpenAI\'s API works, including a model running on your computer.';

  @override
  String get tidyAddress => 'API address';

  @override
  String get tidyAddressInvalid =>
      'Enter an address starting with https:// or http://';

  @override
  String get tidyKey => 'API key';

  @override
  String get tidyKeyHelp => 'Not needed for a local model';

  @override
  String get showKey => 'Show key';

  @override
  String get hideKey => 'Hide key';

  @override
  String get tidyModel => 'Model';

  @override
  String get tidyPrivacy =>
      'The text of your thoughts is sent to this service. Images stay on this device.';

  @override
  String get turnOff => 'Turn off';

  @override
  String get tidyUnreachable => 'Tidying paused: can\'t reach the AI service.';

  @override
  String get tidyRejectedKey => 'Tidying paused: the API key was refused.';

  @override
  String get tidyNotFound => 'Tidying paused: address or model not found.';

  @override
  String get tidyLimited =>
      'Tidying paused: the AI service\'s limit or credit is used up.';

  @override
  String get tidyFailed =>
      'Tidying paused: the AI service answered unexpectedly.';

  @override
  String get retry => 'Retry';

  @override
  String get cleanUp => 'Clean-up';

  @override
  String suggestionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count suggestions',
      one: '1 suggestion',
    );
    return '$_temp0';
  }

  @override
  String get mergeIntro => 'These thoughts repeat each other:';

  @override
  String get mergeResult => 'Merged, they would read:';

  @override
  String get keepApart => 'Keep apart';

  @override
  String get merge => 'Merge';

  @override
  String get outdatedIntro => 'This thought looks out of date:';

  @override
  String get keep => 'Keep';

  @override
  String get thoughtsMerged => 'Thoughts merged';
}
