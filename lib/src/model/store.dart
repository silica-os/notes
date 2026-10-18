// Where the notes live: one Markdown file per note (markdown.dart, docs/format.md) under
// `$XDG_DATA_HOME/notes` (`~/.local/share/notes`):
//
//   <root>/<id>.md                 a note in the default folder ("Notes")
//   <root>/<Folder>/<id>.md        a note in a folder of the user
//   <root>/.trash/<id>.md          a note in Recently Deleted (its header says where it was)
//   <root>/.attachments/<id>/      the files attached to note <id>
//
// Files are written whole to a temporary file and renamed over the old one, so a note is never
// half written. Notes in Recently Deleted for more than 30 days are removed at start.

import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'markdown.dart';
import 'rich.dart';

/// The folder key of the default folder.
const String defaultFolder = '';

/// A note: its file, header and text.
class Note {
  Note({
    required this.id,
    required this.folder,
    required this.header,
    required this.text,
    this.trashed = false,
  });

  final String id;

  /// The folder ([defaultFolder] or a folder name); for a trashed note, where it was.
  String folder;
  NoteHeader header;
  NoteText text;
  bool trashed;

  DateTime get created => header.created;
  DateTime get modified => header.modified;
  bool get pinned => header.pinned;

  /// The first line with text: the note's title ('' for an empty note).
  String get title {
    for (var i = 0; i < text.paras.length; i++) {
      final t = text.lineText(i);
      if (t.isNotEmpty) return t;
    }
    return '';
  }

  /// The text after the title, on one line.
  String get preview {
    final out = <String>[];
    var seenTitle = false;
    for (var i = 0; i < text.paras.length && out.length < 4; i++) {
      final t = text.lineText(i);
      if (t.isEmpty) continue;
      if (!seenTitle) {
        seenTitle = true;
        continue;
      }
      out.add(t);
    }
    return out.join(' ');
  }

  /// Whether the note has a checklist.
  bool get hasChecklist =>
      text.paras.any((p) => p.style == ParaStyle.checklist);

  /// The tags written in the note (`#word`), without the `#`, lower case.
  Set<String> get tags => tagsIn(text.text);

  /// Whether [query] (lower case) is in the title or the text.
  bool matches(String query) =>
      query.isEmpty || text.plainText().toLowerCase().contains(query);
}

final RegExp _tag = RegExp(
  r'(?<![\p{L}\p{N}_#&])#([\p{L}\p{N}_-]+)',
  unicode: true,
);

/// The tags in [text].
Set<String> tagsIn(String text) => {
  for (final m in _tag.allMatches(text))
    if (!RegExp(r'^\d+$').hasMatch(m.group(1)!)) m.group(1)!.toLowerCase(),
};

/// Why a folder name cannot be used.
enum FolderNameProblem { empty, invalid, taken }

/// The notes on disk.
class NotesStore extends ChangeNotifier {
  NotesStore(this.root, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// The store of the user: `$XDG_DATA_HOME/notes`.
  factory NotesStore.forUser(Map<String, String> env) {
    final home = env['HOME'] ?? '.';
    final data = env['XDG_DATA_HOME'] ?? '$home/.local/share';
    return NotesStore('$data/notes');
  }

  /// The folder holding everything.
  final String root;
  final DateTime Function() _clock;
  final Random _random = Random();

  final List<Note> _notes = [];
  final List<String> _folders = [];

  /// A file that could not be written: the note stays in memory (the window says so).
  String? lastError;

  /// Every note, Recently Deleted too.
  List<Note> get notes => List.unmodifiable(_notes);

  /// The folders of the user, sorted (the default folder is not listed).
  List<String> get folders => List.unmodifiable(_folders);

  DateTime get now => _clock();

  static const String trashDir = '.trash';
  static const String attachmentsDir = '.attachments';

  /// How long a note stays in Recently Deleted.
  static const Duration keepDeleted = Duration(days: 30);

  String _dir(String folder) => folder.isEmpty ? root : '$root/$folder';

  String _path(Note n) =>
      n.trashed ? '$root/$trashDir/${n.id}.md' : '${_dir(n.folder)}/${n.id}.md';

  /// The folder of note [id]'s attachments.
  String attachmentFolder(String id) => '$root/$attachmentsDir/$id';

  /// The file of attachment [name] of note [id].
  String attachmentPath(String id, String name) =>
      '${attachmentFolder(id)}/$name';

  /// The file of [note] (Share).
  String pathOf(Note note) => _path(note);

  /// Reads every note again.
  void load() {
    _notes.clear();
    _folders.clear();
    final dir = Directory(root);
    try {
      dir.createSync(recursive: true);
      for (final e in dir.listSync(followLinks: false)) {
        final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (e is File && name.endsWith('.md')) {
          _read(e, defaultFolder, trashed: false);
        } else if (e is Directory && !name.startsWith('.')) {
          _folders.add(name);
          for (final f in e.listSync(followLinks: false)) {
            if (f is File && f.path.endsWith('.md')) {
              _read(f, name, trashed: false);
            }
          }
        }
      }
      final trash = Directory('$root/$trashDir');
      if (trash.existsSync()) {
        for (final f in trash.listSync(followLinks: false)) {
          if (f is File && f.path.endsWith('.md')) {
            _read(f, defaultFolder, trashed: true);
          }
        }
      }
    } on FileSystemException catch (e) {
      lastError = e.message;
    }
    _folders.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    _purgeOld();
    notifyListeners();
  }

  void _read(File file, String folder, {required bool trashed}) {
    try {
      final name = file.uri.pathSegments.last;
      final id = name.substring(0, name.length - 3);
      final (header, text) = readNoteFile(
        file.readAsStringSync(),
        file.lastModifiedSync(),
      );
      _notes.add(
        Note(
          id: id,
          folder: trashed ? (header.folder ?? defaultFolder) : folder,
          header: header,
          text: text,
          trashed: trashed,
        ),
      );
    } on FileSystemException {
      // Unreadable: left alone.
    } on FormatException {
      // Not UTF-8: left alone.
    }
  }

  void _purgeOld() {
    final limit = now.subtract(keepDeleted);
    for (final n in [..._notes]) {
      final deleted = n.header.deleted;
      if (n.trashed && deleted != null && deleted.isBefore(limit)) {
        purge(n, notify: false);
      }
    }
  }

  String _newId() {
    final t = now.microsecondsSinceEpoch.toRadixString(36);
    final r = _random.nextInt(1 << 20).toRadixString(36).padLeft(4, '0');
    var id = '$t$r';
    while (_notes.any((n) => n.id == id)) {
      id = '$id${_random.nextInt(36).toRadixString(36)}';
    }
    return id;
  }

  /// A new empty note in [folder], saved.
  Note create(String folder, {NoteText? text}) {
    final t = now;
    final note = Note(
      id: _newId(),
      folder: folder,
      header: NoteHeader(created: t, modified: t),
      text: text ?? NoteText.empty(),
    );
    _notes.add(note);
    save(note);
    return note;
  }

  /// Writes [note] to its file.
  void save(Note note, {bool notify = true}) {
    final path = _path(note);
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      final staged = File('$path.new');
      staged.writeAsStringSync(writeNoteFile(note.header, note.text));
      staged.renameSync(path);
      lastError = null;
    } on FileSystemException catch (e) {
      lastError = e.message;
    }
    if (notify) notifyListeners();
  }

  /// [note] with new [text], modified now, saved.
  void update(Note note, NoteText text) {
    if (note.text == text) return;
    note.text = text;
    note.header.modified = now;
    save(note);
  }

  void _move(Note note, void Function() change) {
    final from = _path(note);
    change();
    final to = _path(note);
    if (from == to) return;
    try {
      File(to).parent.createSync(recursive: true);
      File(from).renameSync(to);
    } on FileSystemException {
      // The old file is gone or cannot move: write the note anew.
    }
    save(note, notify: false);
  }

  /// Pins or unpins [note].
  void setPinned(Note note, bool pinned) {
    note.header.pinned = pinned;
    save(note);
  }

  /// Moves [note] to [folder] (out of Recently Deleted too).
  void move(Note note, String folder) {
    _move(note, () {
      note.folder = folder;
      note.trashed = false;
      note.header.folder = null;
      note.header.deleted = null;
    });
    notifyListeners();
  }

  /// Moves [note] to Recently Deleted, or removes it if it is there already.
  void delete(Note note) {
    if (note.trashed) {
      purge(note);
      return;
    }
    _move(note, () {
      note.trashed = true;
      note.header.folder = note.folder;
      note.header.deleted = now;
    });
    notifyListeners();
  }

  /// Removes [note] and its attachments for good.
  void purge(Note note, {bool notify = true}) {
    try {
      final f = File(_path(note));
      if (f.existsSync()) f.deleteSync();
      final a = Directory(attachmentFolder(note.id));
      if (a.existsSync()) a.deleteSync(recursive: true);
    } on FileSystemException catch (e) {
      lastError = e.message;
    }
    _notes.remove(note);
    if (notify) notifyListeners();
  }

  /// A copy of [note] in the same folder, with its attachments.
  Note duplicate(Note note) {
    final copy = create(note.folder, text: note.text);
    try {
      final from = Directory(attachmentFolder(note.id));
      if (from.existsSync()) {
        final to = Directory(attachmentFolder(copy.id))
          ..createSync(recursive: true);
        for (final f in from.listSync()) {
          if (f is File) f.copySync('${to.path}/${f.uri.pathSegments.last}');
        }
      }
    } on FileSystemException catch (e) {
      lastError = e.message;
    }
    return copy;
  }

  /// Copies [source] into [note]'s attachments; returns the name it got, null if it failed.
  String? attach(Note note, String source) {
    try {
      final file = File(source);
      if (!file.existsSync()) return null;
      final dir = Directory(attachmentFolder(note.id))
        ..createSync(recursive: true);
      final base = file.uri.pathSegments.last;
      final dot = base.lastIndexOf('.');
      final stem = dot > 0 ? base.substring(0, dot) : base;
      final ext = dot > 0 ? base.substring(dot) : '';
      var name = base;
      var n = 2;
      while (File('${dir.path}/$name').existsSync()) {
        name = '$stem $n$ext';
        n++;
      }
      file.copySync('${dir.path}/$name');
      return name;
    } on FileSystemException catch (e) {
      lastError = e.message;
      return null;
    }
  }

  /// Removes attachments no longer in [note]'s text.
  void pruneAttachments(Note note) {
    final dir = Directory(attachmentFolder(note.id));
    try {
      if (!dir.existsSync()) return;
      final used = note.text.attachments.toSet();
      for (final f in dir.listSync()) {
        if (f is File && !used.contains(f.uri.pathSegments.last)) {
          f.deleteSync();
        }
      }
      if (dir.listSync().isEmpty) dir.deleteSync();
    } on FileSystemException {
      // Kept.
    }
  }

  /// Why [name] cannot name a new folder (or folder [current] renamed); null if it can.
  FolderNameProblem? checkFolderName(String name, {String? current}) {
    final n = name.trim();
    if (n.isEmpty) return FolderNameProblem.empty;
    if (n.contains('/') || n.startsWith('.') || n.contains('\x00')) {
      return FolderNameProblem.invalid;
    }
    if (n == current) return null;
    if (_folders.any((f) => f.toLowerCase() == n.toLowerCase())) {
      return FolderNameProblem.taken;
    }
    return null;
  }

  /// A name for a new folder that is not taken: [base], then "[base] 2"…
  String freeFolderName(String base) {
    var name = base;
    var n = 2;
    while (checkFolderName(name) != null) {
      name = '$base $n';
      n++;
    }
    return name;
  }

  /// Creates folder [name]; false if it cannot.
  bool createFolder(String name) {
    final n = name.trim();
    if (checkFolderName(n) != null) return false;
    try {
      Directory(_dir(n)).createSync(recursive: true);
    } on FileSystemException catch (e) {
      lastError = e.message;
      return false;
    }
    _folders
      ..add(n)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    notifyListeners();
    return true;
  }

  /// Renames folder [from] to [to]; false if it cannot.
  bool renameFolder(String from, String to) {
    final n = to.trim();
    if (from == n) return true;
    if (checkFolderName(n, current: from) != null || !_folders.contains(from)) {
      return false;
    }
    try {
      Directory(_dir(from)).renameSync(_dir(n));
    } on FileSystemException catch (e) {
      lastError = e.message;
      return false;
    }
    _folders
      ..remove(from)
      ..add(n)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final note in _notes) {
      if (note.folder == from) {
        note.folder = n;
        if (note.trashed) {
          note.header.folder = n;
          save(note, notify: false);
        }
      }
    }
    notifyListeners();
    return true;
  }

  /// Deletes folder [name]: its notes go to Recently Deleted.
  void deleteFolder(String name) {
    if (!_folders.contains(name)) return;
    for (final note in [..._notes]) {
      if (note.folder == name && !note.trashed) delete(note);
    }
    for (final note in _notes) {
      // Notes already deleted from it come back to the default folder.
      if (note.folder != name) continue;
      note.folder = defaultFolder;
      if (note.trashed) {
        note.header.folder = defaultFolder;
        save(note, notify: false);
      }
    }
    try {
      final dir = Directory(_dir(name));
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } on FileSystemException catch (e) {
      lastError = e.message;
    }
    _folders.remove(name);
    notifyListeners();
  }

  /// Every trashed note removed.
  void emptyTrash() {
    for (final n in [..._notes]) {
      if (n.trashed) purge(n, notify: false);
    }
    notifyListeners();
  }
}
