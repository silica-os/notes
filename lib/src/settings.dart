// What Notes keeps between launches, in `$XDG_CONFIG_HOME/notes/settings`, one `key=value`
// per line: the view (list or gallery), the sort order, grouping by date, whether the folders
// are shown and the last place open. Under `flutter test` nothing is written.

import 'dart:io';

import 'package:flutter/foundation.dart';

/// How the notes are shown.
enum NotesView { list, gallery }

/// What the notes are sorted by.
enum NotesSort { edited, created, title }

class NotesSettings extends ChangeNotifier {
  NotesSettings(this.path);

  factory NotesSettings.forUser(Map<String, String> env) {
    final home = env['HOME'] ?? '.';
    final config = env['XDG_CONFIG_HOME'] ?? '$home/.config';
    return NotesSettings(
      env.containsKey('FLUTTER_TEST') ? null : '$config/notes/settings',
    )..load();
  }

  /// The file; null keeps everything in memory (tests).
  final String? path;

  NotesView _view = NotesView.list;
  NotesSort _sort = NotesSort.edited;
  bool _groupByDate = true;
  bool _sidebar = true;

  /// The place open when the app closed (`all`, `folder:<name>`, …).
  String place = 'all';

  NotesView get view => _view;
  set view(NotesView v) => _change(() => _view = v);

  NotesSort get sort => _sort;
  set sort(NotesSort v) => _change(() => _sort = v);

  bool get groupByDate => _groupByDate;
  set groupByDate(bool v) => _change(() => _groupByDate = v);

  bool get sidebar => _sidebar;
  set sidebar(bool v) => _change(() => _sidebar = v);

  void _change(VoidCallback f) {
    f();
    save();
    notifyListeners();
  }

  void load() {
    final p = path;
    if (p == null) return;
    try {
      final file = File(p);
      if (!file.existsSync()) return;
      for (final line in file.readAsLinesSync()) {
        final eq = line.indexOf('=');
        if (eq <= 0) continue;
        final key = line.substring(0, eq).trim();
        final value = line.substring(eq + 1).trim();
        switch (key) {
          case 'view':
            _view = NotesView.values.asNameMap()[value] ?? _view;
          case 'sort':
            _sort = NotesSort.values.asNameMap()[value] ?? _sort;
          case 'group-by-date':
            _groupByDate = value != 'false';
          case 'sidebar':
            _sidebar = value != 'false';
          case 'place':
            place = value;
        }
      }
    } on FileSystemException {
      // Unreadable: the defaults.
    } on FormatException {
      // Not text: the next save rewrites it.
    }
  }

  void save() {
    final p = path;
    if (p == null) return;
    try {
      final file = File(p);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        'view=${_view.name}\n'
        'sort=${_sort.name}\n'
        'group-by-date=$_groupByDate\n'
        'sidebar=$_sidebar\n'
        'place=$place\n',
      );
    } on FileSystemException {
      // A read-only home: the app keeps working.
    }
  }
}
