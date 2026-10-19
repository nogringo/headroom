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
}
