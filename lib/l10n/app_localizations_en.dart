// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get addPhoto => 'Add Photo';

  @override
  String get addPhotoMenu => 'Add Photo…';

  @override
  String get allNotes => 'All Notes';

  @override
  String get appTitle => 'Notes';

  @override
  String get attachFile => 'Attach File';

  @override
  String get attachFileMenu => 'Attach File…';

  @override
  String get bestMatches => 'Best Matches';

  @override
  String get bold => 'Bold';

  @override
  String get bulletedList => 'Bulleted List';

  @override
  String get cancel => 'Cancel';

  @override
  String get checklist => 'Checklist';

  @override
  String get checklists => 'Checklists';

  @override
  String get clear => 'Clear';

  @override
  String get copy => 'Copy';

  @override
  String get create => 'Create';

  @override
  String get cut => 'Cut';

  @override
  String get dashedList => 'Dashed List';

  @override
  String get decreaseIndent => 'Decrease Indent';

  @override
  String get defaultFolder => 'Notes';

  @override
  String get delete => 'Delete';

  @override
  String get deleteEmptyFolderMessage => 'The folder is empty.';

  @override
  String get deleteFolder => 'Delete Folder';

  @override
  String get deleteForever => 'Delete Permanently';

  @override
  String get deleteForeverMessage => 'You can’t undo this action.';

  @override
  String get deleteForeverTitle => 'Delete this note permanently?';

  @override
  String get duplicateNote => 'Duplicate Note';

  @override
  String get emptyRecentlyDeleted => 'Empty Recently Deleted';

  @override
  String get emptyTrashMessage =>
      'The notes in Recently Deleted are removed permanently. You can’t undo this action.';

  @override
  String get emptyTrashTitle => 'Delete all the notes in Recently Deleted?';

  @override
  String get folderNameEmpty => 'Type a name for the folder.';

  @override
  String get folderNameInvalid =>
      'A folder name can’t contain “/” or start with a dot.';

  @override
  String get folderNameTaken => 'A folder with this name already exists.';

  @override
  String get folders => 'Folders';

  @override
  String get format => 'Format';

  @override
  String get groupByDate => 'Group by Date';

  @override
  String get hideFolders => 'Hide Folders';

  @override
  String get increaseIndent => 'Increase Indent';

  @override
  String get italic => 'Italic';

  @override
  String get markAsChecked => 'Mark as Checked';

  @override
  String get menuEdit => 'Edit';

  @override
  String get menuFile => 'File';

  @override
  String get menuFont => 'Font';

  @override
  String get menuFormat => 'Format';

  @override
  String get menuHelp => 'Help';

  @override
  String get menuIndentation => 'Indentation';

  @override
  String get menuView => 'View';

  @override
  String get menuWindow => 'Window';

  @override
  String get moveTo => 'Move To';

  @override
  String get newFolder => 'New Folder';

  @override
  String get newFolderName => 'New Folder';

  @override
  String get newNote => 'New Note';

  @override
  String get noAdditionalText => 'No additional text';

  @override
  String get noFileDialog => 'The file dialog isn’t available.';

  @override
  String get noNoteSelected => 'No Note Selected';

  @override
  String get noNotes => 'No Notes';

  @override
  String get noResults => 'No Results';

  @override
  String get notesSection => 'Notes';

  @override
  String get numberedList => 'Numbered List';

  @override
  String get ok => 'OK';

  @override
  String get otherResults => 'Other Results';

  @override
  String get paste => 'Paste';

  @override
  String get pinNote => 'Pin Note';

  @override
  String get pinned => 'Pinned';

  @override
  String get previous30Days => 'Previous 30 Days';

  @override
  String get previous7Days => 'Previous 7 Days';

  @override
  String get recentlyDeleted => 'Recently Deleted';

  @override
  String get recentlyEdited => 'Recently Edited';

  @override
  String get recover => 'Recover';

  @override
  String get recoverMessage =>
      'Notes in Recently Deleted can’t be changed. Recover the note to change it.';

  @override
  String get recoverTitle => 'Recover this note?';

  @override
  String get rename => 'Rename';

  @override
  String get renameFolder => 'Rename Folder';

  @override
  String get renameFolderItem => 'Rename Folder…';

  @override
  String get search => 'Search';

  @override
  String get searchNotes => 'Search Notes';

  @override
  String get searching => 'Searching';

  @override
  String get selectAll => 'Select All';

  @override
  String get share => 'Share';

  @override
  String get shareCopy => 'Copy';

  @override
  String get showFolders => 'Show Folders';

  @override
  String get smartFolders => 'Smart Folders';

  @override
  String get sortBy => 'Sort Notes By';

  @override
  String get sortCreated => 'Date Created';

  @override
  String get sortEdited => 'Date Edited';

  @override
  String get sortTitle => 'Title';

  @override
  String get strikethrough => 'Strikethrough';

  @override
  String get styleBody => 'Body';

  @override
  String get styleHeading => 'Heading';

  @override
  String get styleMono => 'Monostyled';

  @override
  String get styleSubheading => 'Subheading';

  @override
  String get styleTitle => 'Title';

  @override
  String get tags => 'Tags';

  @override
  String get today => 'Today';

  @override
  String get underline => 'Underline';

  @override
  String get unpinNote => 'Unpin Note';

  @override
  String get viewAsGallery => 'as Gallery';

  @override
  String get viewAsList => 'as List';

  @override
  String get yesterday => 'Yesterday';

  @override
  String attachFailed(String files) {
    return 'Couldn’t attach $files.';
  }

  @override
  String checklistDone(int done, int total) {
    return '$done of $total done';
  }

  @override
  String dateAtTime(String date, String time) {
    return '$date at $time';
  }

  @override
  String deleteFolderMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Its $count notes go to Recently Deleted.',
      one: 'Its note goes to Recently Deleted.',
    );
    return '$_temp0';
  }

  @override
  String deleteFolderTitle(String name) {
    return 'Delete the folder “$name”?';
  }

  @override
  String notAnImage(String files) {
    return 'Not a picture: $files.';
  }

  @override
  String noteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notes',
      one: '1 note',
      zero: 'No notes',
    );
    return '$_temp0';
  }

  @override
  String searchResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'All notes, $count results',
      one: 'All notes, 1 result',
      zero: 'All notes, no results',
    );
    return '$_temp0';
  }
}
