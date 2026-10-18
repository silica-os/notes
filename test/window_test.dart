// The window's main flows: a new note, folders, search, the gallery, checklists, deleting
// and recovering, and the menus the app publishes.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/src/app.dart';
import 'package:notes/src/model/markdown.dart';
import 'package:notes/src/model/rich.dart';
import 'package:notes/src/model/store.dart';
import 'package:notes/src/portal.dart';
import 'package:notes/src/settings.dart';
import 'package:notes/src/window.dart';
import 'package:silica_ui/silica_ui.dart' show SilicaMenuDelegate;

class FakeDialogs implements FileDialogs {
  List<String>? next;
  String? lastTitle;

  @override
  Future<List<String>?> open({
    required String title,
    bool multiple = true,
  }) async {
    lastTitle = title;
    return next;
  }

  @override
  Future<String?> save({required String title, required String name}) async =>
      null;
}

void main() {
  late Directory dir;
  late NotesStore store;
  late NotesSettings settings;
  late FakeDialogs dialogs;
  late List<MethodCall> menuCalls;
  final window = GlobalKey<NotesWindowState>();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('notes_window');
    store = NotesStore('${dir.path}/notes')..load();
    settings = NotesSettings(null);
    dialogs = FakeDialogs();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1120, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    menuCalls = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SilicaMenuDelegate.defaultChannel,
      (call) async {
        menuCalls.add(call);
        return true;
      },
    );
    await tester.pumpWidget(
      NotesApp(
        store: store,
        settings: settings,
        dialogs: dialogs,
        locale: const Locale('en'),
        windowKey: window,
      ),
    );
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Note seed(String folder, String text, {Duration ago = Duration.zero}) {
    final note = store.create(folder, text: readMarkdown(text));
    note.header.modified = DateTime.now().subtract(ago);
    store.save(note);
    return note;
  }

  final noteField = find.descendant(
    of: find.byKey(const ValueKey('editor')),
    matching: find.byType(EditableText),
  );

  List<Map<Object?, Object?>> menus() =>
      ((menuCalls.lastWhere((c) => c.method == 'setMenus').arguments
                  as Map)['menus']
              as List)
          .cast<Map<Object?, Object?>>();

  List<String> labels(String menu) => [
    for (final i
        in (menus().firstWhere((m) => m['label'] == menu)['items'] as List))
      if (i is Map && i['label'] is String) i['label'] as String,
  ];

  testWidgets('an empty store says so; a new note is written to disk', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('No Notes'), findsOneWidget);
    expect(find.text('No Note Selected'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('new note')));
    await settle(tester);
    expect(find.byKey(const ValueKey('editor')), findsOneWidget);
    await tester.enterText(noteField, 'Shopping\nmilk');
    await settle(tester);
    expect(find.text('Shopping'), findsWidgets);
    expect(find.text('milk'), findsWidgets);
    window.currentState!.flush();
    final files = Directory(
      '${dir.path}/notes',
    ).listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    expect(files.single.readAsStringSync(), contains('# Shopping\nmilk'));
    expect(find.text('1 note'), findsOneWidget);
  });

  testWidgets('a new empty note is dropped when another note is chosen', (
    tester,
  ) async {
    final kept = seed(defaultFolder, '# Kept');
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('new note')));
    await settle(tester);
    expect(store.notes, hasLength(2));
    await tester.tap(find.byKey(ValueKey('row ${kept.id}')));
    await settle(tester);
    expect(store.notes.single.id, kept.id);
  });

  testWidgets('folders: create, choose, move a note, rename, delete', (
    tester,
  ) async {
    final note = seed(defaultFolder, '# Lemon cake\nzest');
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('new folder')));
    await settle(tester);
    expect(find.byKey(const ValueKey('alert')), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('alert field')),
        matching: find.byType(EditableText),
      ),
      'Recipes',
    );
    await tester.tap(find.byKey(const ValueKey('alert Create')));
    await settle(tester);
    expect(store.folders, ['Recipes']);
    expect(find.byKey(const ValueKey('place folder Recipes')), findsOneWidget);
    expect(find.text('No Notes'), findsOneWidget);
    // A taken name is refused with a reason.
    await tester.tap(find.byKey(const ValueKey('new folder')));
    await settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('alert field')),
        matching: find.byType(EditableText),
      ),
      'recipes',
    );
    await tester.tap(find.byKey(const ValueKey('alert Create')));
    await settle(tester);
    expect(
      find.text('A folder with this name already exists.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('alert Cancel')));
    await settle(tester);
    store.move(note, 'Recipes');
    await settle(tester);
    expect(find.byKey(ValueKey('row ${note.id}')), findsOneWidget);
    expect(store.renameFolder('Recipes', 'Cakes'), isTrue);
    await settle(tester);
    expect(find.byKey(const ValueKey('place folder Cakes')), findsOneWidget);
    store.deleteFolder('Cakes');
    await settle(tester);
    expect(find.byKey(const ValueKey('place trash')), findsOneWidget);
  });

  testWidgets('search finds notes in every folder and marks the matches', (
    tester,
  ) async {
    store.createFolder('Work');
    seed(defaultFolder, '# Lemon cake\nthree lemons');
    seed('Work', '# Meeting\nbring a lemon');
    seed(defaultFolder, '# Shopping\nbread');
    await pump(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('search field')),
        matching: find.byType(EditableText),
      ),
      'lemon',
    );
    await settle(tester);
    expect(find.text('Searching'), findsOneWidget);
    expect(find.text('All notes, 2 results'), findsOneWidget);
    expect(find.text('Best Matches'), findsOneWidget);
    expect(window.currentState!.editor.highlight, 'lemon');
    await tester.tap(find.byKey(const ValueKey('place all')));
    await settle(tester);
    expect(find.text('All Notes'), findsWidgets);
    expect(find.text('3 notes'), findsOneWidget);
  });

  testWidgets('the gallery shows cards; a double click opens the note', (
    tester,
  ) async {
    final a = seed(defaultFolder, '# First\none');
    seed(defaultFolder, '# Second\ntwo');
    await pump(tester);
    window.currentState!.setView(NotesView.gallery);
    await settle(tester);
    expect(find.byKey(const ValueKey('gallery')), findsOneWidget);
    expect(find.byKey(ValueKey('card ${a.id}')), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('card ${a.id}')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(ValueKey('card ${a.id}')));
    await settle(tester);
    expect(settings.view, NotesView.list);
    expect(window.currentState!.selectedNote?.id, a.id);
  });

  testWidgets('checklists: the toolbar makes one, a click ticks an item', (
    tester,
  ) async {
    seed(defaultFolder, '# Shopping\nmilk');
    await pump(tester);
    final state = window.currentState!;
    state.editor.selection = TextSelection.collapsed(
      offset: state.editor.text.length,
    );
    state.setParaStyle(ParaStyle.checklist, toggle: true);
    await settle(tester);
    expect(find.byKey(const ValueKey('check 1')), findsOneWidget);
    expect(find.text('0 of 1 done'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('check 1')));
    await settle(tester);
    expect(state.selectedNote!.text.paras[1].checked, isTrue);
    expect(find.text('1 of 1 done'), findsOneWidget);
    state.flush();
    expect(
      File(store.pathOf(state.selectedNote!)).readAsStringSync(),
      contains('- [x] milk'),
    );
  });

  testWidgets(
    'deleting moves a note to Recently Deleted; it can be recovered',
    (tester) async {
      final note = seed(defaultFolder, '# Old idea');
      await pump(tester);
      final state = window.currentState!;
      state.deleteNote();
      await settle(tester);
      expect(note.trashed, isTrue);
      expect(find.text('No Notes'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('place trash')));
      await settle(tester);
      expect(find.byKey(ValueKey('row ${note.id}')), findsOneWidget);
      // A deleted note cannot be changed: typing offers to recover it.
      await tester.tap(noteField);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await settle(tester);
      expect(find.text('Recover this note?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('alert Recover')));
      await settle(tester);
      expect(note.trashed, isFalse);
    },
  );

  testWidgets('attachments come from the file dialog', (tester) async {
    final file = File('${dir.path}/receipt.pdf')..writeAsBytesSync([1, 2, 3]);
    final note = seed(defaultFolder, '# Bills');
    await pump(tester);
    dialogs.next = [file.path];
    await window.currentState!.attachFile();
    await settle(tester);
    expect(dialogs.lastTitle, 'Attach File');
    expect(note.text.attachments, ['receipt.pdf']);
    expect(find.text('receipt.pdf'), findsOneWidget);
    // Add Photo takes pictures only.
    dialogs.next = [file.path];
    await window.currentState!.attachFile(photo: true);
    await settle(tester);
    expect(find.text('Not a picture: receipt.pdf.'), findsOneWidget);
  });

  testWidgets('the menus follow the state', (tester) async {
    seed(defaultFolder, '# One');
    await pump(tester);
    await settle(tester);
    expect(labels('File'), containsAll(['New Note', 'New Folder', 'Pin Note']));
    expect(
      labels('Format'),
      containsAll(['Title', 'Heading', 'Checklist', 'Mark as Checked']),
    );
    expect(
      labels('View'),
      containsAll(['as List', 'as Gallery', 'Hide Folders']),
    );
    window.currentState!.togglePin();
    await settle(tester);
    expect(labels('File'), contains('Unpin Note'));
  });

  testWidgets('Italian', (tester) async {
    tester.view.physicalSize = const Size(1120, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      NotesApp(
        store: store,
        settings: settings,
        dialogs: dialogs,
        locale: const Locale('it'),
      ),
    );
    await tester.pump();
    expect(find.text('Tutte le note'), findsWidgets);
    expect(find.text('Nessuna nota selezionata'), findsOneWidget);
  });
}
