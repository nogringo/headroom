import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
  ];

  /// Placeholder of the capture field, shown while it is empty.
  ///
  /// In en, this message translates to:
  /// **'What\'s on your mind?'**
  String get captureHint;

  /// Tooltip and accessibility label of the button that saves the typed thought.
  ///
  /// In en, this message translates to:
  /// **'Note it'**
  String get captureButton;

  /// Accessibility label of the capture field and of the edit dialog's field, read before what they hold.
  ///
  /// In en, this message translates to:
  /// **'Thought'**
  String get thoughtField;

  /// Announced to screen readers once the typed thought is saved, since the field only empties.
  ///
  /// In en, this message translates to:
  /// **'Thought noted'**
  String get thoughtNoted;

  /// Shown in place of the list when no thought has been noted yet.
  ///
  /// In en, this message translates to:
  /// **'What you note shows up here.'**
  String get emptyList;

  /// Inline error shown when writing thoughts to disk failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save to this device. Retrying on your next change.'**
  String get saveFailed;

  /// Snackbar message after swiping a thought away.
  ///
  /// In en, this message translates to:
  /// **'Thought deleted'**
  String get thoughtDeleted;

  /// Snackbar action that brings back the thought just deleted.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// Label revealed behind a thought while swiping it, and its accessibility action.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Accessibility label of the dialog opened by tapping a thought.
  ///
  /// In en, this message translates to:
  /// **'Edit thought'**
  String get editTitle;

  /// Closes the edit dialog without saving.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Saves the edited thought and closes the dialog.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Heading above the thoughts noted today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// Heading above the thoughts noted on the previous calendar day. Older days show a weekday, then a date.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// Context menu item of the capture field that attaches the image from the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste image'**
  String get pasteImage;

  /// Snackbar shown when "Paste image" finds no image in the clipboard.
  ///
  /// In en, this message translates to:
  /// **'No image in the clipboard.'**
  String get noImageInClipboard;

  /// Snackbar shown when a pasted image could not be saved.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add the image.'**
  String get imageNotAdded;

  /// Tooltip of the button that removes the pasted image before sending.
  ///
  /// In en, this message translates to:
  /// **'Remove image'**
  String get removeImage;

  /// Accessibility label of a thought's image. Tapping it shows the image full screen.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get imageLabel;

  /// Accessibility label of one of a thought's images when it has several.
  ///
  /// In en, this message translates to:
  /// **'Image {index} of {count}'**
  String imagePosition(int index, int count);

  /// Button of the full screen viewer that shows the thought's previous image.
  ///
  /// In en, this message translates to:
  /// **'Previous image'**
  String get previousImage;

  /// Button of the full screen viewer that shows the thought's next image.
  ///
  /// In en, this message translates to:
  /// **'Next image'**
  String get nextImage;

  /// Shown when the pasted image is already among the images being added.
  ///
  /// In en, this message translates to:
  /// **'Image already added.'**
  String get imageAlreadyAdded;

  /// Button of the full screen viewer that copies the image shown to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy image'**
  String get copyImage;

  /// Label the copy button takes for two seconds after a successful copy.
  ///
  /// In en, this message translates to:
  /// **'Image copied'**
  String get imageCopied;

  /// Shown in the full screen viewer when copying the image failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t copy the image.'**
  String get imageNotCopied;

  /// Item of a thought's right-click menu that opens it to edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// Item of a thought's right-click menu that copies its text, as written rather than its title, to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get copyText;

  /// Shown when copying a thought's text from its menu failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t copy the text.'**
  String get textNotCopied;

  /// Item of a theme's right-click menu in the sidebar, and its accessibility action. Takes the theme off its thoughts, which are kept.
  ///
  /// In en, this message translates to:
  /// **'Delete theme'**
  String get deleteTheme;

  /// Snackbar message after deleting a theme, with Undo.
  ///
  /// In en, this message translates to:
  /// **'Theme deleted. Its thoughts stay.'**
  String get themeDeleted;

  /// Sidebar entry that lists every thought under the day it was noted.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get allThoughts;

  /// Sidebar entry for the thoughts without a theme.
  ///
  /// In en, this message translates to:
  /// **'No theme'**
  String get noTheme;

  /// Tooltip of the edit dialog's button that shows the thought's themes and opens a menu to change them.
  ///
  /// In en, this message translates to:
  /// **'Themes'**
  String get themes;

  /// Tooltip of the themes shown under a thought in the list of every thought, which opens a menu to change them.
  ///
  /// In en, this message translates to:
  /// **'Change themes'**
  String get changeThemes;

  /// Label of the edit dialog's themes button while the thought has none.
  ///
  /// In en, this message translates to:
  /// **'Choose themes'**
  String get chooseThemes;

  /// Item of the theme menu that asks for the name of a theme to create.
  ///
  /// In en, this message translates to:
  /// **'New theme...'**
  String get newThemeItem;

  /// Title of the dialog that asks for a new theme's name.
  ///
  /// In en, this message translates to:
  /// **'New theme'**
  String get newTheme;

  /// Tooltip of the sidebar button beside the open theme, and title of the dialog it opens.
  ///
  /// In en, this message translates to:
  /// **'Rename theme'**
  String get renameTheme;

  /// Label of the field that holds a theme's name.
  ///
  /// In en, this message translates to:
  /// **'Theme name'**
  String get themeName;

  /// Shown under the field while renaming a theme to the name of another, which merges the two.
  ///
  /// In en, this message translates to:
  /// **'Its thoughts will join {theme}, which already exists.'**
  String themesJoin(String theme);

  /// Confirms a theme's new name.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// Confirms a new theme's name.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// Sidebar entry and tooltip of the button that opens the settings page, and that page's title.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Title of the settings section that sets up the AI.
  ///
  /// In en, this message translates to:
  /// **'AI tidying'**
  String get tidySettings;

  /// Shown under a new thought while the AI is sorting it.
  ///
  /// In en, this message translates to:
  /// **'Tidying'**
  String get tidying;

  /// Button that asks the AI to look over every thought for some to merge or delete.
  ///
  /// In en, this message translates to:
  /// **'Clean up'**
  String get cleanUpAction;

  /// Label of the same button while the AI looks over the thoughts.
  ///
  /// In en, this message translates to:
  /// **'Cleaning up'**
  String get cleaningUp;

  /// Shown when the AI looked over every thought and found nothing to merge or delete.
  ///
  /// In en, this message translates to:
  /// **'No repeated or out-of-date thoughts.'**
  String get nothingToCleanUp;

  /// Shown when the AI found clean-ups about thoughts outside the open theme. The list of every thought shows them.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 suggestion, in All} other{{count} suggestions, in All}}'**
  String suggestionsElsewhere(int count);

  /// Action beside the suggestions found elsewhere, which opens the list of every thought.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get show;

  /// First paragraph of the AI tidying settings.
  ///
  /// In en, this message translates to:
  /// **'An AI of your choice sorts each thought by theme as you note it, and gives it a title and subtasks when it needs some. When you ask, it spots the thoughts to merge or delete. Any service compatible with OpenAI\'s API works, including a model running on your computer.'**
  String get tidyIntro;

  /// Label of the field holding the base URL of the AI service.
  ///
  /// In en, this message translates to:
  /// **'API address'**
  String get tidyAddress;

  /// Shown under the address field when it does not hold a web address.
  ///
  /// In en, this message translates to:
  /// **'Enter an address starting with https:// or http://'**
  String get tidyAddressInvalid;

  /// Label of the field holding the key of the AI service.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get tidyKey;

  /// Helper text under the API key field.
  ///
  /// In en, this message translates to:
  /// **'Not needed for a local model'**
  String get tidyKeyHelp;

  /// Tooltip of the button that reveals the API key.
  ///
  /// In en, this message translates to:
  /// **'Show key'**
  String get showKey;

  /// Tooltip of the button that hides the API key.
  ///
  /// In en, this message translates to:
  /// **'Hide key'**
  String get hideKey;

  /// Label of the field holding the name of the AI model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get tidyModel;

  /// Privacy note at the bottom of the AI tidying settings.
  ///
  /// In en, this message translates to:
  /// **'The text of your thoughts is sent to this service. Images stay on this device.'**
  String get tidyPrivacy;

  /// Button of the AI tidying settings that stops tidying and forgets the settings.
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get turnOff;

  /// Inline error when the AI service could not be reached.
  ///
  /// In en, this message translates to:
  /// **'Tidying paused: can\'t reach the AI service.'**
  String get tidyUnreachable;

  /// Inline error when the AI service refused the API key.
  ///
  /// In en, this message translates to:
  /// **'Tidying paused: the API key was refused.'**
  String get tidyRejectedKey;

  /// Inline error when the AI service answered 404.
  ///
  /// In en, this message translates to:
  /// **'Tidying paused: address or model not found.'**
  String get tidyNotFound;

  /// Inline error when the AI service answered 429, which means a rate limit or no credit left. The service's own message shows below it.
  ///
  /// In en, this message translates to:
  /// **'Tidying paused: the AI service\'s limit or credit is used up.'**
  String get tidyLimited;

  /// Inline error when the AI service failed or its reply could not be read.
  ///
  /// In en, this message translates to:
  /// **'Tidying paused: the AI service answered unexpectedly.'**
  String get tidyFailed;

  /// Button next to a tidying error that tries again.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Title of the card proposing to merge or delete thoughts.
  ///
  /// In en, this message translates to:
  /// **'Clean-up'**
  String get cleanUp;

  /// How many clean-ups the AI proposes, shown on the card.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 suggestion} other{{count} suggestions}}'**
  String suggestionCount(int count);

  /// Above the thoughts the AI proposes to merge.
  ///
  /// In en, this message translates to:
  /// **'These thoughts repeat each other:'**
  String get mergeIntro;

  /// Above the thought that would replace them.
  ///
  /// In en, this message translates to:
  /// **'Merged, they would read:'**
  String get mergeResult;

  /// Declines the proposed merge.
  ///
  /// In en, this message translates to:
  /// **'Keep apart'**
  String get keepApart;

  /// Accepts the proposed merge.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get merge;

  /// Above the thought the AI proposes to delete.
  ///
  /// In en, this message translates to:
  /// **'This thought looks out of date:'**
  String get outdatedIntro;

  /// Declines deleting the thought the AI found out of date.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get keep;

  /// Snackbar message after merging thoughts, with an undo action.
  ///
  /// In en, this message translates to:
  /// **'Thoughts merged'**
  String get thoughtsMerged;

  /// Title of the settings section that saves and restores a copy.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get backup;

  /// First paragraph of the backup settings.
  ///
  /// In en, this message translates to:
  /// **'A copy of your thoughts and their images, to keep wherever you like, on a cloud drive or a USB stick. Your AI\'s API key stays out of it.'**
  String get backupIntro;

  /// Shown in the backup settings before any copy was saved from this device.
  ///
  /// In en, this message translates to:
  /// **'No copy saved yet'**
  String get noBackupYet;

  /// How long ago a copy was last saved from this device, in calendar days.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =0{Last copy saved today} =1{Last copy saved yesterday} other{Last copy saved {days} days ago}}'**
  String lastBackup(int days);

  /// Button of the backup settings that saves a zip of every thought where the person picks.
  ///
  /// In en, this message translates to:
  /// **'Save a copy'**
  String get saveBackup;

  /// Button of the backup settings that opens a saved copy and adds back what it holds.
  ///
  /// In en, this message translates to:
  /// **'Restore a copy'**
  String get restoreBackup;

  /// Under the restore button: a restore merges, it never replaces.
  ///
  /// In en, this message translates to:
  /// **'Restoring adds the thoughts missing here, and deletes nothing.'**
  String get restoreHelp;

  /// Shown in the backup settings after a restore.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nothing new: every thought was already here.} =1{1 thought restored.} other{{count} thoughts restored.}}'**
  String restored(int count);

  /// Added after a restore that set up the AI. Backups never hold the API key.
  ///
  /// In en, this message translates to:
  /// **'AI tidying is set up again. Enter your API key in it again if the service needs one.'**
  String get aiRestored;

  /// Error in the backup settings when making or writing the copy failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the copy.'**
  String get backupNotSaved;

  /// Error in the backup settings when the file picked for a restore can't be read as a backup.
  ///
  /// In en, this message translates to:
  /// **'This file isn\'t a Headroom copy, or it\'s damaged.'**
  String get notABackup;

  /// Error in the backup settings when a readable copy could not be written to this device.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t restore the copy.'**
  String get restoreFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
