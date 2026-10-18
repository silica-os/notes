// The note format (Markdown subset and header), the store on disk, places and sorting.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes/src/model/markdown.dart';
import 'package:notes/src/model/places.dart';
import 'package:notes/src/model/rich.dart';
import 'package:notes/src/model/store.dart';
import 'package:notes/src/settings.dart';

const o = objectChar;

/// A note text from lines: `(para, [(text, style)])`.
NoteText build(List<(Para, List<(String, Inline)>)> lines) {
  final text = StringBuffer();
  final styles = <Inline>[];
  final paras = <Para>[];
  for (var i = 0; i < lines.length; i++) {
    if (i > 0) {
      text.write('\n');
      styles.add(Inline.plain);
    }
    final (para, chunks) = lines[i];
    paras.add(para);
    if (para.style.isList) {
      text.write(o);
      styles.add(Inline.listMarker);
    }
    for (final (t, s) in chunks) {
      text.write(t);
      styles.addAll(List.filled(t.length, s));
    }
  }
  return NoteText(text.toString(), Runs.fromStyles(styles), paras);
}

void main() {
  group('markdown', () {
    test('every paragraph style and inline style survives a round trip', () {
      const bold = Inline(bold: true);
      const italic = Inline(italic: true);
      const all = Inline(
        bold: true,
        italic: true,
        underline: true,
        strike: true,
      );
      final note = build([
        (Para.title, [('Lemon cake', Inline.plain)]),
        (Para.body, [('A ', Inline.plain), ('soft', bold), (' cake', italic)]),
        (const Para(ParaStyle.heading), [('Ingredients', Inline.plain)]),
        (const Para(ParaStyle.subheading), [('Dry', Inline.plain)]),
        (const Para(ParaStyle.bulleted), [('Eggs', Inline.plain)]),
        (const Para(ParaStyle.bulleted, indent: 1), [('Large', all)]),
        (const Para(ParaStyle.dashed), [('Sugar', Inline.plain)]),
        (const Para(ParaStyle.numbered), [('Whisk', Inline.plain)]),
        (const Para(ParaStyle.numbered), [('Bake', Inline.plain)]),
        (
          const Para(ParaStyle.checklist, checked: true),
          [('Buy', Inline.plain)],
        ),
        (const Para(ParaStyle.checklist), [('Cook', Inline.plain)]),
        (
          const Para(ParaStyle.mono),
          [('let x = 1; # not a heading', Inline.plain)],
        ),
        (const Para(ParaStyle.mono), [('```', Inline.plain)]),
        (Para.body, []),
        (
          Para.body,
          [
            ('see ', Inline.plain),
            (o, const Inline(attachment: 'cake (1).png')),
            (o, const Inline(attachment: 'odd](name.txt')),
          ],
        ),
      ]);
      final md = writeMarkdown(note);
      expect(md, contains('# Lemon cake'));
      expect(md, contains('A **soft*** cake*'));
      expect(md, contains('  - '));
      expect(md, contains('2. Bake'));
      expect(md, contains('- [x] Buy'));
      expect(md, contains('![cake (1).png](attachments/cake%20%281%29.png)'));
      expect(readMarkdown(md), note);
    });

    test('characters that would start a style are escaped', () {
      final note = NoteText.plain(
        '#lemon is a tag\n- not a list\n1. not numbered\n*stars* and ~~tildes~~ <u>\n'
        r'back\slash [link](x) under_score `tick`',
      );
      final md = writeMarkdown(note);
      expect(readMarkdown(md), note);
      expect(md.split('\n').first, r'\#lemon is a tag');
    });

    test('files written by other programs are read as far as they go', () {
      final note = readMarkdown('Shopping\n* eggs\n- [X] milk\n#### four\n\n');
      expect(note.paras.map((p) => p.style).toList(), [
        ParaStyle.body,
        ParaStyle.bulleted,
        ParaStyle.checklist,
        ParaStyle.body,
        ParaStyle.body,
        ParaStyle.body,
      ]);
      expect(note.paras[2].checked, isTrue);
      expect(note.lineText(3), '#### four');
    });

    test(
      'the header keeps the dates, the pin and where a deleted note was',
      () {
        final created = DateTime.utc(2026, 10, 1, 9, 30);
        final modified = DateTime.utc(2026, 10, 16, 10, 22);
        final file = writeNoteFile(
          NoteHeader(
            created: created,
            modified: modified,
            pinned: true,
            folder: 'Recipes',
            deleted: modified,
          ),
          NoteText.plain('Hello', titled: true),
        );
        final (header, text) = readNoteFile(file, DateTime(2000));
        expect(header.created, created.toLocal());
        expect(header.modified, modified.toLocal());
        expect(header.pinned, isTrue);
        expect(header.folder, 'Recipes');
        expect(header.deleted, modified.toLocal());
        expect(text.paras.single, Para.title);
        final (plain, _) = readNoteFile('No header\nat all', DateTime(2001));
        expect(plain.created, DateTime(2001));
      },
    );

    test('plain text writes the markers and numbers', () {
      final note = build([
        (const Para(ParaStyle.numbered), [('a', Inline.plain)]),
        (const Para(ParaStyle.numbered), [('b', Inline.plain)]),
        (const Para(ParaStyle.checklist, checked: true), [('c', Inline.plain)]),
        (const Para(ParaStyle.bulleted, indent: 1), [('d', Inline.plain)]),
      ]);
      expect(note.plainText(), '1. a\n2. b\n☑ c\n  • d');
    });
  });

  group('store', () {
    late Directory dir;
    late DateTime now;
    late NotesStore store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('notes_store');
      now = DateTime(2026, 10, 18, 12);
      store = NotesStore('${dir.path}/notes', clock: () => now)..load();
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('notes are files that load again', () {
      final note = store.create(defaultFolder);
      store.update(note, NoteText.plain('Shopping\nmilk', titled: true));
      expect(File('${dir.path}/notes/${note.id}.md').existsSync(), isTrue);
      final again = NotesStore('${dir.path}/notes')..load();
      expect(again.notes.single.title, 'Shopping');
      expect(again.notes.single.preview, 'milk');
    });

    test('folders are created, renamed and deleted', () {
      expect(store.createFolder('Recipes'), isTrue);
      expect(store.checkFolderName('recipes'), FolderNameProblem.taken);
      expect(store.checkFolderName('.hidden'), FolderNameProblem.invalid);
      expect(store.checkFolderName('  '), FolderNameProblem.empty);
      final note = store.create('Recipes');
      store.update(note, NoteText.plain('Cake', titled: true));
      expect(store.renameFolder('Recipes', 'Cakes'), isTrue);
      expect(note.folder, 'Cakes');
      expect(
        File('${dir.path}/notes/Cakes/${note.id}.md').existsSync(),
        isTrue,
      );
      store.deleteFolder('Cakes');
      expect(store.folders, isEmpty);
      expect(note.trashed, isTrue);
      expect(note.folder, defaultFolder);
      final again = NotesStore('${dir.path}/notes')..load();
      expect(again.notes.single.trashed, isTrue);
    });

    test('deleted notes go to Recently Deleted and leave after 30 days', () {
      final note = store.create(defaultFolder);
      store.update(note, NoteText.plain('Old', titled: true));
      store.delete(note);
      expect(note.trashed, isTrue);
      store.move(note, defaultFolder);
      expect(note.trashed, isFalse);
      store.delete(note);
      now = now.add(const Duration(days: 31));
      store.load();
      expect(store.notes, isEmpty);
    });

    test('attachments are copied with free names and pruned when unused', () {
      final source = File('${dir.path}/photo.png')..writeAsBytesSync([1, 2]);
      final note = store.create(defaultFolder);
      expect(store.attach(note, source.path), 'photo.png');
      expect(store.attach(note, source.path), 'photo 2.png');
      note.text = NoteText(
        o,
        const [Run(1, Inline(attachment: 'photo.png'))],
        [Para.body],
      );
      store.pruneAttachments(note);
      expect(
        File(store.attachmentPath(note.id, 'photo.png')).existsSync(),
        isTrue,
      );
      expect(
        File(store.attachmentPath(note.id, 'photo 2.png')).existsSync(),
        isFalse,
      );
      final copy = store.duplicate(note);
      expect(
        File(store.attachmentPath(copy.id, 'photo.png')).existsSync(),
        isTrue,
      );
    });
  });

  group('places', () {
    Note note(
      String id,
      String text,
      DateTime modified, {
      bool pinned = false,
    }) => Note(
      id: id,
      folder: defaultFolder,
      header: NoteHeader(created: modified, modified: modified, pinned: pinned),
      text: NoteText.plain(text, titled: true),
    );

    test('tags are words after #', () {
      expect(tagsIn('Cake #lemon and #Weekend, not a#b or #12 or C#'), {
        'lemon',
        'weekend',
      });
    });

    test('notes sort pinned first and group by date', () {
      final now = DateTime(2026, 10, 18, 12);
      final notes = [
        note('a', 'Today', now),
        note('b', 'Yesterday', now.subtract(const Duration(days: 1))),
        note('c', 'Week', now.subtract(const Duration(days: 4))),
        note('d', 'Month', now.subtract(const Duration(days: 20))),
        note('e', 'Old', DateTime(2026, 3, 2)),
        note('f', 'Pinned', DateTime(2025, 1, 1), pinned: true),
      ];
      final sorted = sortNotes(notes, NotesSort.edited);
      expect(sorted.first.id, 'f');
      final sections = sectionNotes(
        sorted,
        NotesSort.edited,
        now,
        byDate: true,
      );
      expect(sections.map((s) => s.group).toList(), [
        DateGroup.pinned,
        DateGroup.today,
        DateGroup.yesterday,
        DateGroup.week,
        DateGroup.month,
        DateGroup.older,
      ]);
      expect(sections.last.month, DateTime(2026, 3));
      final byTitle = sortNotes(notes, NotesSort.title);
      expect(byTitle.map((n) => n.title).skip(1).first, 'Month');
      expect(notesIn(const SmartPlace(SmartKind.recent), notes, now).length, 3);
      expect(
        notesIn(const AllNotes(), notes, now, query: 'old').single.id,
        'e',
      );
    });
  });
}
