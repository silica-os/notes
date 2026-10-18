// The places of the sidebar (All Notes, the folders, the smart folders, the tags, Recently
// Deleted), which notes each one shows, how they are sorted and grouped by date.

import 'package:flutter/foundation.dart';

import '../settings.dart';
import 'store.dart';

/// A place in the sidebar.
@immutable
sealed class Place {
  const Place();

  /// The key the settings keep.
  String get key;

  /// The place a [key] names; All Notes when it names nothing known.
  static Place parse(String key, List<String> folders) {
    if (key == 'trash') return const TrashPlace();
    if (key == 'recent') return const SmartPlace(SmartKind.recent);
    if (key == 'checklists') return const SmartPlace(SmartKind.checklists);
    if (key == 'default') return const FolderPlace(defaultFolder);
    if (key.startsWith('folder:')) {
      final name = key.substring(7);
      if (folders.contains(name)) return FolderPlace(name);
    }
    if (key.startsWith('tag:')) return TagPlace(key.substring(4));
    return const AllNotes();
  }
}

class AllNotes extends Place {
  const AllNotes();
  @override
  String get key => 'all';
  @override
  bool operator ==(Object other) => other is AllNotes;
  @override
  int get hashCode => 1;
}

class FolderPlace extends Place {
  const FolderPlace(this.folder);
  final String folder;
  @override
  String get key => folder.isEmpty ? 'default' : 'folder:$folder';
  @override
  bool operator ==(Object other) =>
      other is FolderPlace && other.folder == folder;
  @override
  int get hashCode => folder.hashCode;
}

enum SmartKind { recent, checklists }

class SmartPlace extends Place {
  const SmartPlace(this.kind);
  final SmartKind kind;
  @override
  String get key => kind.name;
  @override
  bool operator ==(Object other) => other is SmartPlace && other.kind == kind;
  @override
  int get hashCode => kind.hashCode;
}

class TagPlace extends Place {
  const TagPlace(this.tag);
  final String tag;
  @override
  String get key => 'tag:$tag';
  @override
  bool operator ==(Object other) => other is TagPlace && other.tag == tag;
  @override
  int get hashCode => tag.hashCode;
}

class TrashPlace extends Place {
  const TrashPlace();
  @override
  String get key => 'trash';
  @override
  bool operator ==(Object other) => other is TrashPlace;
  @override
  int get hashCode => 2;
}

/// How long a note counts as recently edited.
const Duration recentlyEdited = Duration(days: 7);

/// The notes [place] shows (or, with a [query], every note that matches it), not sorted.
List<Note> notesIn(
  Place place,
  List<Note> notes,
  DateTime now, {
  String? query,
}) {
  if (query != null) {
    final q = query.toLowerCase();
    return [
      for (final n in notes)
        if (!n.trashed && n.matches(q)) n,
    ];
  }
  return [
    for (final n in notes)
      if (switch (place) {
        AllNotes() => !n.trashed,
        FolderPlace(:final folder) => !n.trashed && n.folder == folder,
        SmartPlace(kind: SmartKind.recent) =>
          !n.trashed && now.difference(n.modified) <= recentlyEdited,
        SmartPlace(kind: SmartKind.checklists) => !n.trashed && n.hasChecklist,
        TagPlace(:final tag) => !n.trashed && n.tags.contains(tag),
        TrashPlace() => n.trashed,
      })
        n,
  ];
}

/// [notes] sorted: pinned first, then by [sort] (newest first for dates, A to Z for titles).
List<Note> sortNotes(List<Note> notes, NotesSort sort) {
  final out = [...notes];
  int byDate(DateTime a, DateTime b) => b.compareTo(a);
  out.sort((a, b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    final c = switch (sort) {
      NotesSort.edited => byDate(a.modified, b.modified),
      NotesSort.created => byDate(a.created, b.created),
      NotesSort.title => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    };
    return c != 0 ? c : a.id.compareTo(b.id);
  });
  return out;
}

/// The date groups of the list.
enum DateGroup { pinned, today, yesterday, week, month, older, notes }

/// A section of the list: its group (for [DateGroup.older] the month in [month]) and notes.
class NoteSection {
  NoteSection(this.group, this.notes, {this.month});
  final DateGroup group;

  /// The first day of the month, for [DateGroup.older].
  final DateTime? month;
  final List<Note> notes;
}

/// [sorted] in sections: Pinned, then by date when [byDate] (the date the sort uses), else
/// one section.
List<NoteSection> sectionNotes(
  List<Note> sorted,
  NotesSort sort,
  DateTime now, {
  required bool byDate,
}) {
  final pinned = [
    for (final n in sorted)
      if (n.pinned) n,
  ];
  final rest = [
    for (final n in sorted)
      if (!n.pinned) n,
  ];
  final out = <NoteSection>[
    if (pinned.isNotEmpty) NoteSection(DateGroup.pinned, pinned),
  ];
  if (!byDate || sort == NotesSort.title) {
    if (rest.isNotEmpty) {
      out.add(NoteSection(DateGroup.notes, rest));
    }
    return out;
  }
  final today = DateTime(now.year, now.month, now.day);
  NoteSection? current;
  for (final n in rest) {
    final d = sort == NotesSort.created ? n.created : n.modified;
    final day = DateTime(d.year, d.month, d.day);
    final ago = today.difference(day).inDays;
    final DateGroup group;
    DateTime? month;
    if (ago <= 0) {
      group = DateGroup.today;
    } else if (ago == 1) {
      group = DateGroup.yesterday;
    } else if (ago <= 7) {
      group = DateGroup.week;
    } else if (ago <= 30) {
      group = DateGroup.month;
    } else {
      group = DateGroup.older;
      month = DateTime(d.year, d.month);
    }
    if (current == null || current.group != group || current.month != month) {
      current = NoteSection(group, [], month: month);
      out.add(current);
    }
    current.notes.add(n);
  }
  return out;
}
