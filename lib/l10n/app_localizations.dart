import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_it.dart';

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
    Locale('it'),
  ];

  /// No description provided for @addPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add Photo'**
  String get addPhoto;

  /// No description provided for @addPhotoMenu.
  ///
  /// In en, this message translates to:
  /// **'Add Photo…'**
  String get addPhotoMenu;

  /// No description provided for @allNotes.
  ///
  /// In en, this message translates to:
  /// **'All Notes'**
  String get allNotes;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get appTitle;

  /// No description provided for @attachFile.
  ///
  /// In en, this message translates to:
  /// **'Attach File'**
  String get attachFile;

  /// No description provided for @attachFileMenu.
  ///
  /// In en, this message translates to:
  /// **'Attach File…'**
  String get attachFileMenu;

  /// No description provided for @bestMatches.
  ///
  /// In en, this message translates to:
  /// **'Best Matches'**
  String get bestMatches;

  /// No description provided for @bold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get bold;

  /// No description provided for @bulletedList.
  ///
  /// In en, this message translates to:
  /// **'Bulleted List'**
  String get bulletedList;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @checklist.
  ///
  /// In en, this message translates to:
  /// **'Checklist'**
  String get checklist;

  /// No description provided for @checklists.
  ///
  /// In en, this message translates to:
  /// **'Checklists'**
  String get checklists;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @cut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get cut;

  /// No description provided for @dashedList.
  ///
  /// In en, this message translates to:
  /// **'Dashed List'**
  String get dashedList;

  /// No description provided for @decreaseIndent.
  ///
  /// In en, this message translates to:
  /// **'Decrease Indent'**
  String get decreaseIndent;

  /// No description provided for @defaultFolder.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get defaultFolder;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteEmptyFolderMessage.
  ///
  /// In en, this message translates to:
  /// **'The folder is empty.'**
  String get deleteEmptyFolderMessage;

  /// No description provided for @deleteFolder.
  ///
  /// In en, this message translates to:
  /// **'Delete Folder'**
  String get deleteFolder;

  /// No description provided for @deleteForever.
  ///
  /// In en, this message translates to:
  /// **'Delete Permanently'**
  String get deleteForever;

  /// No description provided for @deleteForeverMessage.
  ///
  /// In en, this message translates to:
  /// **'You can’t undo this action.'**
  String get deleteForeverMessage;

  /// No description provided for @deleteForeverTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this note permanently?'**
  String get deleteForeverTitle;

  /// No description provided for @duplicateNote.
  ///
  /// In en, this message translates to:
  /// **'Duplicate Note'**
  String get duplicateNote;

  /// No description provided for @emptyRecentlyDeleted.
  ///
  /// In en, this message translates to:
  /// **'Empty Recently Deleted'**
  String get emptyRecentlyDeleted;

  /// No description provided for @emptyTrashMessage.
  ///
  /// In en, this message translates to:
  /// **'The notes in Recently Deleted are removed permanently. You can’t undo this action.'**
  String get emptyTrashMessage;

  /// No description provided for @emptyTrashTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete all the notes in Recently Deleted?'**
  String get emptyTrashTitle;

  /// No description provided for @folderNameEmpty.
  ///
  /// In en, this message translates to:
  /// **'Type a name for the folder.'**
  String get folderNameEmpty;

  /// No description provided for @folderNameInvalid.
  ///
  /// In en, this message translates to:
  /// **'A folder name can’t contain “/” or start with a dot.'**
  String get folderNameInvalid;

  /// No description provided for @folderNameTaken.
  ///
  /// In en, this message translates to:
  /// **'A folder with this name already exists.'**
  String get folderNameTaken;

  /// No description provided for @folders.
  ///
  /// In en, this message translates to:
  /// **'Folders'**
  String get folders;

  /// No description provided for @format.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get format;

  /// No description provided for @groupByDate.
  ///
  /// In en, this message translates to:
  /// **'Group by Date'**
  String get groupByDate;

  /// No description provided for @hideFolders.
  ///
  /// In en, this message translates to:
  /// **'Hide Folders'**
  String get hideFolders;

  /// No description provided for @increaseIndent.
  ///
  /// In en, this message translates to:
  /// **'Increase Indent'**
  String get increaseIndent;

  /// No description provided for @italic.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get italic;

  /// No description provided for @markAsChecked.
  ///
  /// In en, this message translates to:
  /// **'Mark as Checked'**
  String get markAsChecked;

  /// No description provided for @menuEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get menuEdit;

  /// No description provided for @menuFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get menuFile;

  /// No description provided for @menuFont.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get menuFont;

  /// No description provided for @menuFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get menuFormat;

  /// No description provided for @menuHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get menuHelp;

  /// No description provided for @menuIndentation.
  ///
  /// In en, this message translates to:
  /// **'Indentation'**
  String get menuIndentation;

  /// No description provided for @menuView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get menuView;

  /// No description provided for @menuWindow.
  ///
  /// In en, this message translates to:
  /// **'Window'**
  String get menuWindow;

  /// No description provided for @moveTo.
  ///
  /// In en, this message translates to:
  /// **'Move To'**
  String get moveTo;

  /// No description provided for @newFolder.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get newFolder;

  /// No description provided for @newFolderName.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get newFolderName;

  /// No description provided for @newNote.
  ///
  /// In en, this message translates to:
  /// **'New Note'**
  String get newNote;

  /// No description provided for @noAdditionalText.
  ///
  /// In en, this message translates to:
  /// **'No additional text'**
  String get noAdditionalText;

  /// No description provided for @noFileDialog.
  ///
  /// In en, this message translates to:
  /// **'The file dialog isn’t available.'**
  String get noFileDialog;

  /// No description provided for @noNoteSelected.
  ///
  /// In en, this message translates to:
  /// **'No Note Selected'**
  String get noNoteSelected;

  /// No description provided for @noNotes.
  ///
  /// In en, this message translates to:
  /// **'No Notes'**
  String get noNotes;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No Results'**
  String get noResults;

  /// No description provided for @notesSection.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notesSection;

  /// No description provided for @numberedList.
  ///
  /// In en, this message translates to:
  /// **'Numbered List'**
  String get numberedList;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @otherResults.
  ///
  /// In en, this message translates to:
  /// **'Other Results'**
  String get otherResults;

  /// No description provided for @paste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// No description provided for @pinNote.
  ///
  /// In en, this message translates to:
  /// **'Pin Note'**
  String get pinNote;

  /// No description provided for @pinned.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get pinned;

  /// No description provided for @previous30Days.
  ///
  /// In en, this message translates to:
  /// **'Previous 30 Days'**
  String get previous30Days;

  /// No description provided for @previous7Days.
  ///
  /// In en, this message translates to:
  /// **'Previous 7 Days'**
  String get previous7Days;

  /// No description provided for @recentlyDeleted.
  ///
  /// In en, this message translates to:
  /// **'Recently Deleted'**
  String get recentlyDeleted;

  /// No description provided for @recentlyEdited.
  ///
  /// In en, this message translates to:
  /// **'Recently Edited'**
  String get recentlyEdited;

  /// No description provided for @recover.
  ///
  /// In en, this message translates to:
  /// **'Recover'**
  String get recover;

  /// No description provided for @recoverMessage.
  ///
  /// In en, this message translates to:
  /// **'Notes in Recently Deleted can’t be changed. Recover the note to change it.'**
  String get recoverMessage;

  /// No description provided for @recoverTitle.
  ///
  /// In en, this message translates to:
  /// **'Recover this note?'**
  String get recoverTitle;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @renameFolder.
  ///
  /// In en, this message translates to:
  /// **'Rename Folder'**
  String get renameFolder;

  /// No description provided for @renameFolderItem.
  ///
  /// In en, this message translates to:
  /// **'Rename Folder…'**
  String get renameFolderItem;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @searchNotes.
  ///
  /// In en, this message translates to:
  /// **'Search Notes'**
  String get searchNotes;

  /// No description provided for @searching.
  ///
  /// In en, this message translates to:
  /// **'Searching'**
  String get searching;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAll;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @shareCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get shareCopy;

  /// No description provided for @showFolders.
  ///
  /// In en, this message translates to:
  /// **'Show Folders'**
  String get showFolders;

  /// No description provided for @smartFolders.
  ///
  /// In en, this message translates to:
  /// **'Smart Folders'**
  String get smartFolders;

  /// No description provided for @sortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort Notes By'**
  String get sortBy;

  /// No description provided for @sortCreated.
  ///
  /// In en, this message translates to:
  /// **'Date Created'**
  String get sortCreated;

  /// No description provided for @sortEdited.
  ///
  /// In en, this message translates to:
  /// **'Date Edited'**
  String get sortEdited;

  /// No description provided for @sortTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get sortTitle;

  /// No description provided for @strikethrough.
  ///
  /// In en, this message translates to:
  /// **'Strikethrough'**
  String get strikethrough;

  /// No description provided for @styleBody.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get styleBody;

  /// No description provided for @styleHeading.
  ///
  /// In en, this message translates to:
  /// **'Heading'**
  String get styleHeading;

  /// No description provided for @styleMono.
  ///
  /// In en, this message translates to:
  /// **'Monostyled'**
  String get styleMono;

  /// No description provided for @styleSubheading.
  ///
  /// In en, this message translates to:
  /// **'Subheading'**
  String get styleSubheading;

  /// No description provided for @styleTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get styleTitle;

  /// No description provided for @tags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tags;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @underline.
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get underline;

  /// No description provided for @unpinNote.
  ///
  /// In en, this message translates to:
  /// **'Unpin Note'**
  String get unpinNote;

  /// No description provided for @viewAsGallery.
  ///
  /// In en, this message translates to:
  /// **'as Gallery'**
  String get viewAsGallery;

  /// No description provided for @viewAsList.
  ///
  /// In en, this message translates to:
  /// **'as List'**
  String get viewAsList;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @attachFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t attach {files}.'**
  String attachFailed(String files);

  /// No description provided for @checklistDone.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} done'**
  String checklistDone(int done, int total);

  /// No description provided for @dateAtTime.
  ///
  /// In en, this message translates to:
  /// **'{date} at {time}'**
  String dateAtTime(String date, String time);

  /// No description provided for @deleteFolderMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Its note goes to Recently Deleted.} other{Its {count} notes go to Recently Deleted.}}'**
  String deleteFolderMessage(int count);

  /// No description provided for @deleteFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete the folder “{name}”?'**
  String deleteFolderTitle(String name);

  /// No description provided for @notAnImage.
  ///
  /// In en, this message translates to:
  /// **'Not a picture: {files}.'**
  String notAnImage(String files);

  /// No description provided for @noteCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No notes} =1{1 note} other{{count} notes}}'**
  String noteCount(int count);

  /// No description provided for @searchResults.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{All notes, no results} =1{All notes, 1 result} other{All notes, {count} results}}'**
  String searchResults(int count);
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
      <String>['en', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
