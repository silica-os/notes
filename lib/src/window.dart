// The Notes window (kit `Apps/Notes/Notes`): the sidebar with the smart folders, folders and
// tags; the list of notes (or the gallery of cards) with its title and view controls; the
// editor with the format, insert and share controls and the search field.
//
// Notes are written to disk shortly after each change and when another note is chosen or the
// window closes. An empty note is dropped when it is left.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:silica_ui/silica_ui.dart';

import '../l10n/app_localizations.dart';
import 'editor/note_controller.dart';
import 'editor/note_editor.dart';
import 'menus.dart';
import 'model/places.dart';
import 'model/rich.dart';
import 'model/store.dart';
import 'portal.dart';
import 'settings.dart';
import 'style.dart';

/// A button of an alert.
class _Button {
  const _Button(this.label, this.onPressed, {this.role = AlertRole.normal});
  final String label;
  final VoidCallback onPressed;
  final AlertRole role;
}

/// An alert over the window, with a text field when [field] is given.
class _Alert {
  const _Alert(this.title, this.buttons, {this.message, this.field});
  final String title;
  final String? message;
  final TextEditingController? field;
  final List<_Button> buttons;
}

class NotesWindow extends StatefulWidget {
  const NotesWindow({
    super.key,
    required this.store,
    required this.settings,
    required this.dialogs,
    this.active = true,
  });

  final NotesStore store;
  final NotesSettings settings;
  final FileDialogs dialogs;

  /// Whether the window is the active one.
  final bool active;

  @override
  State<NotesWindow> createState() => NotesWindowState();
}

class NotesWindowState extends State<NotesWindow> implements NotesCommands {
  final NoteEditorController _editor = NoteEditorController();
  final FocusNode _editorFocus = FocusNode(debugLabel: 'note');
  final FocusNode _listFocus = FocusNode(debugLabel: 'notes list');
  final TextEditingController _query = TextEditingController();
  final FocusNode _queryFocus = FocusNode(debugLabel: 'search');
  final ScrollController _editorScroll = ScrollController();
  final GlobalKey _formatKey = GlobalKey(debugLabel: 'format group');
  final GlobalKey _shareKey = GlobalKey(debugLabel: 'share');

  late Place _place = Place.parse(widget.settings.place, widget.store.folders);
  String? _selected;

  /// The search shown in the list (lower case); null when not searching.
  String? _search;
  Timer? _saveTimer;
  Timer? _searchTimer;
  final Set<String> _dirty = {};
  _Alert? _alert;
  bool _shareable = false;
  String? _shareFor;

  NotesStore get _store => widget.store;
  NotesSettings get _settings => widget.settings;
  AppLocalizations get l10n => AppLocalizations.of(context);

  @override
  void initState() {
    super.initState();
    _store.addListener(_storeChanged);
    _settings.addListener(_storeChanged);
    _editor.addListener(_editorChanged);
    _query.addListener(_queryChanged);
    _editorFocus.addListener(_storeChanged);
    final first = _visible.firstOrNull;
    if (first != null) _open(first, focus: false);
  }

  @override
  void dispose() {
    _store.removeListener(_storeChanged);
    _settings.removeListener(_storeChanged);
    _editor.removeListener(_editorChanged);
    flush();
    _leave(_selected);
    _saveTimer?.cancel();
    _searchTimer?.cancel();
    _query.removeListener(_queryChanged);
    _editor.dispose();
    _editorFocus.dispose();
    _listFocus.dispose();
    _query.dispose();
    _queryFocus.dispose();
    _editorScroll.dispose();
    super.dispose();
  }

  void _storeChanged() {
    if (!mounted) return;
    setState(() {
      if (_selected != null && _note(_selected) == null) _selected = null;
      if (_place case FolderPlace(
        :final folder,
      ) when folder.isNotEmpty && !_store.folders.contains(folder)) {
        _place = const AllNotes();
      }
    });
  }

  Note? _note(String? id) =>
      id == null ? null : _store.notes.where((n) => n.id == id).firstOrNull;

  /// The note open in the editor.
  Note? get selectedNote => _note(_selected);

  // MARK: the list

  /// The notes the list shows, in order.
  List<Note> get _visible => sortNotes(
    notesIn(_place, _store.notes, _store.now, query: _search),
    _settings.sort,
  );

  List<NoteSection> get _sections {
    final visible = _visible;
    if (_search != null) {
      // Best matches: the query in the title.
      final q = _search!;
      final best = [
        for (final n in visible)
          if (n.title.toLowerCase().contains(q)) n,
      ];
      final rest = [
        for (final n in visible)
          if (!n.title.toLowerCase().contains(q)) n,
      ];
      return [
        if (best.isNotEmpty) NoteSection(DateGroup.pinned, best),
        if (rest.isNotEmpty) NoteSection(DateGroup.notes, rest),
      ];
    }
    return sectionNotes(
      visible,
      _settings.sort,
      _store.now,
      byDate: _settings.groupByDate,
    );
  }

  String _sectionTitle(NoteSection s) {
    if (_search != null) {
      return s.group == DateGroup.pinned ? l10n.bestMatches : l10n.otherResults;
    }
    final locale = l10n.localeName;
    return switch (s.group) {
      DateGroup.pinned => l10n.pinned,
      DateGroup.today => l10n.today,
      DateGroup.yesterday => l10n.yesterday,
      DateGroup.week => l10n.previous7Days,
      DateGroup.month => l10n.previous30Days,
      DateGroup.older =>
        s.month!.year == _store.now.year
            ? DateFormat.MMMM(locale).format(s.month!)
            : DateFormat.yMMMM(locale).format(s.month!),
      DateGroup.notes => l10n.notesSection,
    };
  }

  String _placeTitle() => switch (_place) {
    AllNotes() => l10n.allNotes,
    FolderPlace(:final folder) => folder.isEmpty ? l10n.defaultFolder : folder,
    SmartPlace(kind: SmartKind.recent) => l10n.recentlyEdited,
    SmartPlace(kind: SmartKind.checklists) => l10n.checklists,
    TagPlace(:final tag) => '#$tag',
    TrashPlace() => l10n.recentlyDeleted,
  };

  /// The date of a row: the time today, Yesterday, the weekday this week, else the date.
  String _rowDate(DateTime d) {
    final now = _store.now;
    final today = DateTime(now.year, now.month, now.day);
    final ago = today.difference(DateTime(d.year, d.month, d.day)).inDays;
    final locale = l10n.localeName;
    if (ago <= 0) return DateFormat.Hm(locale).format(d);
    if (ago == 1) return l10n.yesterday;
    if (ago < 7) return DateFormat.EEEE(locale).format(d);
    return DateFormat.yMd(locale).format(d);
  }

  DateTime _dateOf(Note n) =>
      _settings.sort == NotesSort.created ? n.created : n.modified;

  // MARK: opening and saving

  void _open(Note note, {bool focus = false}) {
    if (_selected != note.id) {
      flush();
      final left = _selected;
      _selected = note.id;
      _leave(left);
      _editor
        ..highlight = _search ?? ''
        ..load(
          note.text,
          selection: TextSelection.collapsed(
            offset: note.text.text.isEmpty ? 0 : note.text.text.length,
          ),
        );
      if (_editorScroll.hasClients) _editorScroll.jumpTo(0);
      _refreshShare();
    }
    if (focus) _editorFocus.requestFocus();
  }

  /// Leaving note [id]: an empty one is dropped, unused attachments removed.
  void _leave(String? id) {
    final note = _note(id);
    if (note == null || note.trashed) return;
    if (note.title.isEmpty && note.text.attachments.isEmpty) {
      _store.purge(note);
      return;
    }
    _store.pruneAttachments(note);
  }

  void _editorChanged() {
    final note = selectedNote;
    if (note == null) {
      setState(() {});
      return;
    }
    final doc = _editor.doc;
    if (note.trashed || note.text == doc) {
      // The selection or the typing style changed: the menus follow.
      setState(() {});
      return;
    }
    note.text = doc;
    note.header.modified = _store.now;
    _dirty.add(note.id);
    _saveTimer?.cancel();
    _saveTimer = Timer(NotesMetrics.saveDelay, flush);
    setState(() {});
  }

  /// Writes the notes changed since the last write.
  void flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    for (final id in [..._dirty]) {
      final note = _note(id);
      if (note != null) _store.save(note, notify: false);
    }
    _dirty.clear();
  }

  // MARK: search

  void _queryChanged() {
    final text = _query.text.trim();
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      _runSearch(text);
    });
  }

  void _runSearch(String text) {
    setState(() {
      _search = text.isEmpty ? null : text.toLowerCase();
      _editor.highlight = _search ?? '';
      final visible = _visible;
      if (_search != null &&
          visible.isNotEmpty &&
          !visible.any((n) => n.id == _selected)) {
        _open(visible.first);
      }
    });
    // The marks in the text follow.
    _editor.refresh();
  }

  void _endSearch() {
    _searchTimer?.cancel();
    _query.clear();
    _runSearch('');
    _listFocus.requestFocus();
  }

  // MARK: commands

  Place get place => _place;

  void _choosePlace(Place place) {
    if (_search != null) {
      _searchTimer?.cancel();
      _query.clear();
      _search = null;
      _editor.highlight = '';
    }
    setState(() => _place = place);
    _settings
      ..place = place.key
      ..save();
    final visible = _visible;
    final note = visible.where((n) => n.id == _selected).firstOrNull;
    if (note == null) {
      if (visible.isNotEmpty) {
        _open(visible.first);
      } else {
        flush();
        final left = _selected;
        _selected = null;
        _leave(left);
        _editor.load(NoteText.empty());
      }
    }
    _listFocus.requestFocus();
  }

  @override
  void newNote() {
    var folder = defaultFolder;
    if (_place case FolderPlace(folder: final f)) folder = f;
    if (_place is TrashPlace || _search != null) {
      if (_search != null) _endSearch();
      _place = const AllNotes();
    }
    if (_settings.view == NotesView.gallery) _settings.view = NotesView.list;
    flush();
    final note = _store.create(folder);
    _open(note, focus: true);
    setState(() {});
  }

  @override
  void newFolder() => _askFolderName(
    title: l10n.newFolder,
    initial: _store.freeFolderName(l10n.newFolderName),
    confirm: l10n.create,
    onName: (name) {
      if (!_store.createFolder(name)) return false;
      _choosePlace(FolderPlace(name.trim()));
      return true;
    },
  );

  void _renameFolder(String folder) => _askFolderName(
    title: l10n.renameFolder,
    initial: folder,
    confirm: l10n.rename,
    current: folder,
    onName: (name) {
      if (!_store.renameFolder(folder, name)) return false;
      if (_place == FolderPlace(folder)) {
        _place = FolderPlace(name.trim());
        _settings
          ..place = _place.key
          ..save();
      }
      return true;
    },
  );

  void _askFolderName({
    required String title,
    required String initial,
    required String confirm,
    required bool Function(String name) onName,
    String? current,
  }) {
    final field = TextEditingController(text: initial)
      ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
    void submit() {
      final problem = _store.checkFolderName(field.text, current: current);
      if (problem != null) {
        setState(
          () => _alert = _Alert(
            title,
            _alert?.buttons ?? const [],
            field: field,
            message: switch (problem) {
              FolderNameProblem.empty => l10n.folderNameEmpty,
              FolderNameProblem.invalid => l10n.folderNameInvalid,
              FolderNameProblem.taken => l10n.folderNameTaken,
            },
          ),
        );
        return;
      }
      if (onName(field.text)) _closeAlert();
    }

    setState(
      () => _alert = _Alert(title, [
        _Button(l10n.cancel, _closeAlert, role: AlertRole.cancel),
        _Button(confirm, submit, role: AlertRole.primary),
      ], field: field),
    );
  }

  void _closeAlert() {
    setState(() => _alert = null);
    _listFocus.requestFocus();
  }

  void _deleteFolder(String folder) {
    final count = _store.notes
        .where((n) => !n.trashed && n.folder == folder)
        .length;
    setState(
      () => _alert = _Alert(
        l10n.deleteFolderTitle(folder),
        [
          _Button(l10n.cancel, _closeAlert, role: AlertRole.cancel),
          _Button(l10n.delete, () {
            flush();
            _store.deleteFolder(folder);
            _closeAlert();
          }, role: AlertRole.destructive),
        ],
        message: count == 0
            ? l10n.deleteEmptyFolderMessage
            : l10n.deleteFolderMessage(count),
      ),
    );
  }

  @override
  void deleteNote() {
    final note = selectedNote;
    if (note == null) return;
    if (note.trashed) {
      setState(
        () => _alert = _Alert(l10n.deleteForeverTitle, [
          _Button(l10n.cancel, _closeAlert, role: AlertRole.cancel),
          _Button(l10n.delete, () {
            _closeAlert();
            _remove(note);
          }, role: AlertRole.destructive),
        ], message: l10n.deleteForeverMessage),
      );
      return;
    }
    _remove(note);
  }

  void _remove(Note note) {
    flush();
    final visible = _visible;
    final at = visible.indexWhere((n) => n.id == note.id);
    _selected = null;
    if (note.title.isEmpty && note.text.attachments.isEmpty) {
      _store.purge(note);
    } else {
      _store.delete(note);
    }
    final rest = _visible;
    if (rest.isEmpty) {
      _editor.load(NoteText.empty());
    } else {
      _open(rest[at.clamp(0, rest.length - 1)]);
    }
    setState(() {});
  }

  @override
  void togglePin() {
    final note = selectedNote;
    if (note == null || note.trashed) return;
    flush();
    _store.setPinned(note, !note.pinned);
  }

  @override
  void duplicateNote() {
    final note = selectedNote;
    if (note == null || note.trashed) return;
    flush();
    final copy = _store.duplicate(note);
    _open(copy);
    setState(() {});
  }

  void _moveNote(Note note, String folder) {
    flush();
    _store.move(note, folder);
    if (_note(_selected) != null && !_visible.any((n) => n.id == _selected)) {
      final first = _visible.firstOrNull;
      if (first != null) {
        _open(first);
      } else {
        _selected = null;
        _editor.load(NoteText.empty());
      }
    }
    setState(() {});
  }

  void _recover(Note note) {
    final folder = _store.folders.contains(note.folder)
        ? note.folder
        : defaultFolder;
    _moveNote(note, folder);
  }

  void _offerRecover() {
    final note = selectedNote;
    if (note == null || !note.trashed || _alert != null) return;
    setState(
      () => _alert = _Alert(l10n.recoverTitle, [
        _Button(l10n.cancel, _closeAlert, role: AlertRole.cancel),
        _Button(l10n.recover, () {
          _closeAlert();
          _recover(note);
        }, role: AlertRole.primary),
      ], message: l10n.recoverMessage),
    );
  }

  @override
  void emptyTrash() {
    setState(
      () => _alert = _Alert(l10n.emptyTrashTitle, [
        _Button(l10n.cancel, _closeAlert, role: AlertRole.cancel),
        _Button(l10n.delete, () {
          _closeAlert();
          final wasTrash = selectedNote?.trashed ?? false;
          _store.emptyTrash();
          if (wasTrash) {
            _selected = null;
            _editor.load(NoteText.empty());
          }
        }, role: AlertRole.destructive),
      ], message: l10n.emptyTrashMessage),
    );
  }

  bool get _editable => selectedNote != null && !selectedNote!.trashed;

  @override
  bool get canEdit => _editable;

  @override
  bool get hasNote => selectedNote != null;

  @override
  bool get noteInTrash => selectedNote?.trashed ?? false;

  @override
  bool get notePinned => selectedNote?.pinned ?? false;

  @override
  bool get trashHasNotes => _store.notes.any((n) => n.trashed);

  @override
  bool get editorFocused => _editorFocus.hasFocus;

  @override
  NoteEditorController get editor => _editor;

  @override
  NotesSettings get settings => _settings;

  @override
  void setParaStyle(ParaStyle style, {bool toggle = false}) {
    if (!_editable) return;
    _editorFocus.requestFocus();
    _editor.setParaStyle(style, toggle: toggle);
  }

  @override
  void toggleTrait(InlineTrait trait) {
    if (!_editable) return;
    _editorFocus.requestFocus();
    _editor.toggleTrait(trait);
  }

  @override
  void markChecked() {
    if (!_editable) return;
    _editor.markChecked();
  }

  @override
  void indent(int delta) {
    if (!_editable) return;
    _editor.indent(delta);
  }

  @override
  void undo() => _editable ? _editor.undo() : null;

  @override
  void redo() => _editable ? _editor.redo() : null;

  @override
  void focusSearch() {
    if (_settings.view == NotesView.gallery || _searchFieldShown) {
      _queryFocus.requestFocus();
    } else {
      setState(() => _searchButtonOpen = true);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _queryFocus.requestFocus(),
      );
    }
  }

  @override
  void toggleSidebar() => _settings.sidebar = !_settings.sidebar;

  @override
  void setView(NotesView view) {
    if (view == _settings.view) return;
    _settings.view = view;
  }

  @override
  Future<void> attachFile({bool photo = false}) async {
    final note = selectedNote;
    if (note == null || note.trashed) return;
    List<String>? files;
    try {
      files = await widget.dialogs.open(
        title: photo ? l10n.addPhoto : l10n.attachFile,
      );
    } on FileDialogUnavailable {
      if (!mounted) return;
      _showMessage(l10n.noFileDialog);
      return;
    }
    if (!mounted || files == null || files.isEmpty) return;
    attachPaths(files, photo: photo);
  }

  /// Attaches [paths] to the open note at the caret (Attach File, drops).
  void attachPaths(List<String> paths, {bool photo = false}) {
    final note = selectedNote;
    if (note == null || note.trashed) return;
    const images = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};
    final failed = <String>[];
    for (final path in paths) {
      final ext = path.contains('.')
          ? path.substring(path.lastIndexOf('.') + 1).toLowerCase()
          : '';
      if (photo && !images.contains(ext)) {
        failed.add(path.split('/').last);
        continue;
      }
      final name = _store.attach(note, path);
      if (name == null) {
        failed.add(path.split('/').last);
        continue;
      }
      _editor.insertAttachment(name);
    }
    _editorFocus.requestFocus();
    if (failed.isNotEmpty) {
      _showMessage(
        photo
            ? l10n.notAnImage(failed.join(', '))
            : l10n.attachFailed(failed.join(', ')),
      );
    }
  }

  void _showMessage(String title) => setState(
    () => _alert = _Alert(title, [
      _Button(l10n.ok, _closeAlert, role: AlertRole.primary),
    ]),
  );

  // MARK: share

  void _refreshShare() {
    final note = selectedNote;
    final key = note == null || note.trashed ? null : note.id;
    if (key == _shareFor) return;
    _shareFor = key;
    _shareable = false;
    if (note == null || key == null) return;
    final uri = Uri.file(_store.pathOf(note));
    unawaited(() async {
      final targets = await SilicaShare.targets([uri]);
      if (!mounted || key != _shareFor || targets.isEmpty) return;
      setState(() => _shareable = true);
    }());
  }

  Future<void> _openShare() async {
    final note = selectedNote;
    final box = _shareKey.currentContext?.findRenderObject();
    if (note == null || box is! RenderBox || !box.attached) return;
    flush();
    final at = box.localToGlobal(Offset(0, box.size.height + 4));
    await showSilicaShareMenu(
      context: context,
      position: at,
      files: [Uri.file(_store.pathOf(note))],
      copyLabel: l10n.shareCopy,
    );
  }

  // MARK: build

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SilicaMenuBar(
      menus: notesMenus(l, this),
      child: Builder(builder: _window),
    );
  }

  Widget _window(BuildContext context) {
    final colors = NotesColors.of(context);
    return WindowActiveScope(
      active: widget.active,
      child: ColoredBox(
        color: colors.window,
        child: Stack(
          children: [
            Positioned.fill(child: _layout(colors)),
            if (_alert case final alert?)
              Positioned.fill(child: _alertView(alert)),
          ],
        ),
      ),
    );
  }

  Widget _alertView(_Alert alert) => Stack(
    children: [
      const Positioned.fill(child: AbsorbPointer(child: AmalfiSheetScrim())),
      Center(
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              for (final b in alert.buttons) {
                if (b.role == AlertRole.cancel) return b.onPressed();
              }
              if (alert.buttons.length == 1) alert.buttons.first.onPressed();
            },
          },
          child: Focus(
            autofocus: alert.field == null,
            child: SizedBox(
              width: AmalfiAlertMetrics.width,
              child: AmalfiAlert(
                key: const ValueKey('alert'),
                icon: Image.asset(
                  'icon/icon.png',
                  width: 56,
                  height: 56,
                  cacheWidth: 112,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) =>
                      const SizedBox(width: 56, height: 56),
                ),
                title: alert.title,
                message: alert.message,
                critical: alert.buttons.any(
                  (b) => b.role == AlertRole.destructive,
                ),
                accessory: alert.field == null
                    ? null
                    : AmalfiTextField(
                        key: const ValueKey('alert field'),
                        controller: alert.field,
                        autofocus: true,
                        width: double.infinity,
                        onSubmitted: (_) => alert.buttons.last.onPressed(),
                      ),
                actions: [
                  for (final b in alert.buttons)
                    KeyedSubtree(
                      key: ValueKey('alert ${b.label}'),
                      child: AmalfiPushButton(
                        label: b.label,
                        onPressed: b.onPressed,
                        variant: switch (b.role) {
                          AlertRole.primary => AmalfiPushButtonVariant.primary,
                          AlertRole.destructive =>
                            AmalfiPushButtonVariant.destructive,
                          _ => AmalfiPushButtonVariant.secondary,
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );

  /// The sidebar slides on [AmalfiSidebarRevealBuilder]'s measured timing; the columns follow
  /// its edge, and the toggle rides it down to the window controls.
  Widget _layout(NotesColors colors) => AmalfiSidebarRevealBuilder(
    visible: _settings.sidebar,
    builder: (context, progress) {
      final shown = NotesMetrics.sidebarWidth * progress;
      final inset = AmalfiToolbarFollow.inset(
        edge: shown,
        closedX: _toggleReserve,
        offset: AmalfiToolbarMetrics.sectionPadding.left,
      );
      final gallery = _settings.view == NotesView.gallery;
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: shown,
            right: 0,
            top: 0,
            bottom: 0,
            child: gallery
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: NotesMetrics.toolbar,
                        child: _galleryToolbar(colors, inset),
                      ),
                      Expanded(child: _gallery(colors)),
                    ],
                  )
                : AmalfiSplitWindowLayout(
                    columns: [
                      AmalfiWindowColumn(
                        width: NotesMetrics.listWidth,
                        toolbar: _listToolbar(colors, inset),
                        child: _list(colors),
                      ),
                      AmalfiWindowColumn(
                        toolbar: _editorToolbar(colors),
                        child: _editorPane(colors),
                      ),
                    ],
                  ),
          ),
          if (progress > 0)
            Positioned(
              left: shown - NotesMetrics.sidebarWidth,
              top: 0,
              bottom: 0,
              width: NotesMetrics.sidebarWidth,
              child: ColoredBox(
                color: colors.sidebar,
                child: Stack(
                  children: [
                    Positioned.fill(child: _sidebar(colors)),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: NotesMetrics.toolbar,
                      child: WindowDragArea(
                        child: AmalfiToolbar.sidebarSection(
                          key: const ValueKey('sidebar bar'),
                          surface: AmalfiToolbarSurface.blur,
                          children: const [
                            SizedBox(
                              width: AmalfiToolbarPieceMetrics.controlsWidth,
                            ),
                            AmalfiSpacerPiece(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          AmalfiToolbarFollower(
            edge: shown,
            height: NotesMetrics.toolbar,
            child: AmalfiToolbarPiece(
              child: AmalfiToolbarButton(
                key: const ValueKey('sidebar toggle'),
                semanticLabel: l10n.showFolders,
                icon: const AmalfiGlyph(AmalfiGlyphs.sidebar),
                onPressed: toggleSidebar,
              ),
            ),
          ),
        ],
      );
    },
  );

  static const double _toggleReserve =
      AmalfiToolbarPieceMetrics.controlsWidth + 44;

  // MARK: sidebar

  Widget _sidebar(NotesColors colors) {
    final notes = _store.notes;
    int count(bool Function(Note) f) => notes.where(f).length;
    final tags = <String>{
      for (final n in notes)
        if (!n.trashed) ...n.tags,
    }.toList()..sort();
    final searching = _search != null;
    Widget row({
      required Key key,
      required String label,
      required Place place,
      AmalfiGlyphData? icon,
      Color? glyph,
      String? badge,
      void Function(Offset)? menu,
    }) => GestureDetector(
      key: ValueKey('menu $key'),
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: menu == null ? null : (d) => menu(d.globalPosition),
      child: _DropTarget(
        accepts: place is FolderPlace,
        onNote: (id) {
          final note = _note(id);
          if (note != null && place is FolderPlace) {
            _moveNote(note, place.folder);
          }
        },
        child: AmalfiSidebarRow(
          key: key,
          label: label,
          icon: icon,
          glyphColor: glyph,
          badge: badge,
          selected: !searching && _place == place,
          onTap: () => _choosePlace(place),
        ),
      ),
    );

    final trashCount = count((n) => n.trashed);
    final children = <Widget>[
      AmalfiSidebarHeader(title: l10n.smartFolders),
      row(
        key: const ValueKey('place recent'),
        label: l10n.recentlyEdited,
        place: const SmartPlace(SmartKind.recent),
        icon: AmalfiGlyphs.clock,
        glyph: colors.smartGlyph,
      ),
      row(
        key: const ValueKey('place checklists'),
        label: l10n.checklists,
        place: const SmartPlace(SmartKind.checklists),
        icon: AmalfiSymbols.load('checklist') ?? AmalfiGlyphs.listBullet,
        glyph: colors.smartGlyph,
      ),
      AmalfiSidebarHeader(title: l10n.folders),
      row(
        key: const ValueKey('place all'),
        label: l10n.allNotes,
        place: const AllNotes(),
        icon: AmalfiSymbols.load('doc-text') ?? AmalfiGlyphs.doc,
        glyph: colors.folderGlyph,
        badge: '${count((n) => !n.trashed)}',
      ),
      row(
        key: const ValueKey('place default'),
        label: l10n.defaultFolder,
        place: const FolderPlace(defaultFolder),
        icon: AmalfiGlyphs.folder,
        glyph: colors.folderGlyph,
        badge: '${count((n) => !n.trashed && n.folder == defaultFolder)}',
      ),
      for (final f in _store.folders)
        row(
          key: ValueKey('place folder $f'),
          label: f,
          place: FolderPlace(f),
          icon: AmalfiGlyphs.folder,
          glyph: colors.folderGlyph,
          badge: '${count((n) => !n.trashed && n.folder == f)}',
          menu: (at) => _folderMenu(f, at),
        ),
      if (trashCount > 0)
        row(
          key: const ValueKey('place trash'),
          label: l10n.recentlyDeleted,
          place: const TrashPlace(),
          icon: AmalfiGlyphs.trash,
          glyph: colors.folderGlyph,
          badge: '$trashCount',
          menu: (at) => showAmalfiMenu(
            context: context,
            position: at,
            entries: [
              AmalfiMenuAction(
                l10n.emptyRecentlyDeleted,
                destructive: true,
                onSelected: emptyTrash,
              ),
            ],
          ),
        ),
      if (tags.isNotEmpty) ...[
        AmalfiSidebarHeader(title: l10n.tags),
        for (final t in tags)
          row(
            key: ValueKey('place tag $t'),
            label: '#$t',
            place: TagPlace(t),
            icon: _dot,
            glyph: colors.tag(t),
          ),
      ],
    ];
    return AmalfiSidebarPanel(
      key: const ValueKey('sidebar'),
      topInset: NotesMetrics.toolbar,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      footer: AmalfiSidebarFooter(
        children: [
          GestureDetector(
            key: const ValueKey('new folder'),
            behavior: HitTestBehavior.opaque,
            onTap: newFolder,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AmalfiGlyph(
                  AmalfiGlyphs.plus,
                  size: 14,
                  color: colors.secondary,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.newFolder,
                  style: AmalfiType.callout(color: colors.secondary),
                ),
              ],
            ),
          ),
        ],
      ),
      children: children,
    );
  }

  /// A 12 pt dot for the tag rows (`components.md`: tag dots centred in the icon box).
  static final AmalfiGlyphData _dot =
      AmalfiGlyphData.fromSvg(
        'tag-dot',
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">'
            '<circle cx="10" cy="10" r="6" fill="#000"/></svg>',
      ) ??
      AmalfiGlyphs.tag;

  Future<void> _folderMenu(String folder, Offset at) => showAmalfiMenu(
    context: context,
    position: at,
    entries: [
      AmalfiMenuAction(
        l10n.newNote,
        onSelected: () {
          _choosePlace(FolderPlace(folder));
          newNote();
        },
      ),
      const AmalfiMenuDivider(),
      AmalfiMenuAction(
        l10n.renameFolderItem,
        onSelected: () => _renameFolder(folder),
      ),
      AmalfiMenuAction(
        l10n.deleteFolder,
        destructive: true,
        onSelected: () => _deleteFolder(folder),
      ),
    ],
  );

  // MARK: toolbars

  Widget _titlePiece() {
    final visible = _visible;
    return AmalfiTitlePiece(
      title: _search != null ? l10n.searching : _placeTitle(),
      subtitle: _search != null
          ? l10n.searchResults(visible.length)
          : l10n.noteCount(visible.length),
    );
  }

  Widget _viewControl() => AmalfiToolbarPiece(
    child: AmalfiSegmentedControl(
      key: const ValueKey('view'),
      toolbar: true,
      size: AmalfiControlSize.large,
      segments: [
        AmalfiSegment.icon(
          const AmalfiGlyph(AmalfiGlyphs.listBullet),
          semanticLabel: l10n.viewAsList,
          tooltip: l10n.viewAsList,
        ),
        AmalfiSegment.icon(
          AmalfiSymbol('square-grid-2x2'),
          semanticLabel: l10n.viewAsGallery,
          tooltip: l10n.viewAsGallery,
        ),
      ],
      selected: {_settings.view == NotesView.list ? 0 : 1},
      onChanged: (s) =>
          setView(s.contains(1) ? NotesView.gallery : NotesView.list),
    ),
  );

  Widget _newNoteButton() => AmalfiToolbarPiece(
    child: AmalfiToolbarButton(
      key: const ValueKey('new note'),
      semanticLabel: l10n.newNote,
      icon: const AmalfiGlyph(AmalfiGlyphs.compose),
      onPressed: newNote,
    ),
  );

  Widget _listToolbar(NotesColors colors, double inset) => WindowDragArea(
    child: AmalfiToolbar.section(
      key: const ValueKey('list bar'),
      padding: EdgeInsets.only(left: inset, right: 8),
      children: [
        Expanded(
          child: Align(alignment: Alignment.centerLeft, child: _titlePiece()),
        ),
        _viewControl(),
        _newNoteButton(),
      ],
    ),
  );

  Widget _galleryToolbar(NotesColors colors, double inset) => WindowDragArea(
    child: AmalfiToolbar.section(
      key: const ValueKey('gallery bar'),
      padding: EdgeInsets.only(left: inset, right: 12),
      children: [
        Expanded(
          child: Align(alignment: Alignment.centerLeft, child: _titlePiece()),
        ),
        _viewControl(),
        _newNoteButton(),
        AmalfiToolbarPiece(child: _searchField()),
      ],
    ),
  );

  bool _searchFieldShown = true;
  bool _searchButtonOpen = false;

  Widget _searchField() => AmalfiSearchField(
    key: const ValueKey('search field'),
    controller: _query,
    focusNode: _queryFocus,
    size: AmalfiFieldSize.toolbar,
    width: 200,
    placeholder: l10n.search,
    semanticLabel: l10n.search,
    clearLabel: l10n.clear,
    onSubmitted: (_) {
      _searchTimer?.cancel();
      _runSearch(_query.text.trim());
    },
    onCleared: _endSearch,
  );

  Widget _editorToolbar(NotesColors colors) => WindowDragArea(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= NotesMetrics.searchFieldMinEditor;
        _searchFieldShown = wide || _searchButtonOpen || _search != null;
        final editable = _editable;
        final para = _editor.currentPara.style;
        return AmalfiToolbar.section(
          key: const ValueKey('editor bar'),
          padding: const EdgeInsets.only(left: 12, right: 16),
          children: [
            if (selectedNote != null) ...[
              AmalfiToolbarPiece(
                child: KeyedSubtree(
                  key: _formatKey,
                  child: AmalfiActionSegments(
                    key: const ValueKey('format group'),
                    segments: [
                      AmalfiSegment.icon(
                        AmalfiSymbol('text-size'),
                        semanticLabel: l10n.format,
                        tooltip: l10n.format,
                        enabled: editable,
                      ),
                      AmalfiSegment.icon(
                        const AmalfiGlyph(AmalfiGlyphs.listBullet),
                        semanticLabel: l10n.bulletedList,
                        tooltip: l10n.bulletedList,
                        enabled: editable,
                      ),
                      AmalfiSegment.icon(
                        AmalfiSymbol('checklist'),
                        semanticLabel: l10n.checklist,
                        tooltip: l10n.checklist,
                        enabled: editable,
                      ),
                    ],
                    selected: {
                      if (para == ParaStyle.bulleted) 1,
                      if (para == ParaStyle.checklist) 2,
                    },
                    onPressed: (i) => switch (i) {
                      0 => _formatMenu(),
                      1 => setParaStyle(ParaStyle.bulleted, toggle: true),
                      _ => setParaStyle(ParaStyle.checklist, toggle: true),
                    },
                  ),
                ),
              ),
              AmalfiToolbarPiece(
                child: AmalfiActionSegments(
                  key: const ValueKey('insert group'),
                  segments: [
                    AmalfiSegment.icon(
                      AmalfiSymbol('paperclip'),
                      semanticLabel: l10n.attachFile,
                      tooltip: l10n.attachFile,
                      enabled: editable,
                    ),
                    AmalfiSegment.icon(
                      const AmalfiGlyph(AmalfiGlyphs.photo),
                      semanticLabel: l10n.addPhoto,
                      tooltip: l10n.addPhoto,
                      enabled: editable,
                    ),
                  ],
                  onPressed: (i) => unawaited(attachFile(photo: i == 1)),
                ),
              ),
            ],
            const AmalfiSpacerPiece(),
            if (_shareable && editable)
              AmalfiToolbarPiece(
                child: KeyedSubtree(
                  key: _shareKey,
                  child: AmalfiToolbarButton(
                    key: const ValueKey('share'),
                    semanticLabel: l10n.share,
                    icon: const AmalfiGlyph(AmalfiGlyphs.share),
                    onPressed: () => unawaited(_openShare()),
                  ),
                ),
              ),
            if (_searchFieldShown)
              AmalfiToolbarPiece(child: _searchField())
            else
              AmalfiToolbarPiece(
                child: AmalfiToolbarButton(
                  key: const ValueKey('search'),
                  semanticLabel: l10n.search,
                  icon: const AmalfiGlyph(AmalfiGlyphs.search),
                  onPressed: focusSearch,
                ),
              ),
          ],
        );
      },
    ),
  );

  /// The Aa menu: the paragraph styles, then the inline ones.
  Future<void> _formatMenu() async {
    final box = _formatKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final at = box.localToGlobal(Offset(0, box.size.height + 4));
    final para = _editor.currentPara.style;
    AmalfiMenuAction style(ParaStyle s, String label) => AmalfiMenuAction(
      label,
      checked: para == s,
      onSelected: () => setParaStyle(s),
    );
    AmalfiMenuAction trait(InlineTrait t, String label) => AmalfiMenuAction(
      label,
      checked: _editor.hasTrait(t),
      onSelected: () => toggleTrait(t),
    );
    await showAmalfiMenu(
      context: context,
      position: at,
      minWidth: 200,
      entries: [
        style(ParaStyle.title, l10n.styleTitle),
        style(ParaStyle.heading, l10n.styleHeading),
        style(ParaStyle.subheading, l10n.styleSubheading),
        style(ParaStyle.body, l10n.styleBody),
        style(ParaStyle.mono, l10n.styleMono),
        const AmalfiMenuDivider(),
        style(ParaStyle.bulleted, l10n.bulletedList),
        style(ParaStyle.dashed, l10n.dashedList),
        style(ParaStyle.numbered, l10n.numberedList),
        const AmalfiMenuDivider(),
        trait(InlineTrait.bold, l10n.bold),
        trait(InlineTrait.italic, l10n.italic),
        trait(InlineTrait.underline, l10n.underline),
        trait(InlineTrait.strike, l10n.strikethrough),
      ],
    );
  }

  // MARK: list

  Widget _emptyState(NotesColors colors, String text, {bool big = false}) =>
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AmalfiSymbol(
              'doc-text',
              size: NotesMetrics.emptyGlyph,
              color: colors.tertiary,
            ),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: big
                  ? AmalfiType.title2(color: colors.tertiary)
                  : AmalfiType.title3(color: colors.tertiary),
            ),
          ],
        ),
      );

  void _moveSelection(int delta) {
    final visible = [for (final s in _sections) ...s.notes];
    if (visible.isEmpty) return;
    final at = visible.indexWhere((n) => n.id == _selected);
    final next = (at < 0 ? 0 : at + delta).clamp(0, visible.length - 1);
    _open(visible[next]);
    setState(() {});
  }

  Widget _list(NotesColors colors) {
    final sections = _sections;
    final body = sections.isEmpty
        ? _emptyState(colors, _search != null ? l10n.noResults : l10n.noNotes)
        : ListView(
            key: const ValueKey('note list'),
            children: [
              for (final s in sections) ...[
                _listHeader(colors, _sectionTitle(s)),
                for (var i = 0; i < s.notes.length; i++)
                  _row(
                    colors,
                    s.notes[i],
                    separator:
                        i < s.notes.length - 1 &&
                        s.notes[i + 1].id != _selected,
                  ),
              ],
            ],
          );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _moveSelection(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _moveSelection(-1),
        const SingleActivator(LogicalKeyboardKey.delete): deleteNote,
        const SingleActivator(LogicalKeyboardKey.backspace): deleteNote,
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (_editable) _editorFocus.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_search != null) _endSearch();
        },
      },
      child: Focus(
        focusNode: _listFocus,
        autofocus: true,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _listFocus.requestFocus,
          child: body,
        ),
      ),
    );
  }

  Widget _listHeader(NotesColors colors, String title) => SizedBox(
    height: NotesMetrics.listHeader,
    child: Padding(
      padding: const EdgeInsets.only(
        left: NotesMetrics.rowTextX,
        top: NotesMetrics.listHeaderTop,
      ),
      child: Text(
        title,
        key: ValueKey('list header $title'),
        style: AmalfiType.label(color: colors.tertiary),
      ),
    ),
  );

  /// `text` with the search matches on the search highlight.
  Widget _marked(
    String text,
    TextStyle style,
    NotesColors colors, {
    int maxLines = 1,
    bool onAccent = false,
  }) {
    final q = _search;
    if (q == null || q.isEmpty || text.toLowerCase().length != text.length) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    var at = 0;
    while (true) {
      final hit = lower.indexOf(q, at);
      if (hit < 0) break;
      if (hit > at) spans.add(TextSpan(text: text.substring(at, hit)));
      spans.add(
        TextSpan(
          text: text.substring(hit, hit + q.length),
          style: onAccent
              ? const TextStyle(fontWeight: FontWeight.w700)
              : TextStyle(backgroundColor: colors.searchHighlight),
        ),
      );
      at = hit + q.length;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _row(NotesColors colors, Note note, {required bool separator}) {
    final chosen = note.id == _selected;
    final active =
        widget.active && _listFocus.hasFocus || chosen && widget.active;
    final fill = chosen
        ? (active ? colors.accent : colors.inactiveSelection)
        : null;
    final onFill = chosen && active;
    final primary = onFill ? colors.onAccent : colors.text;
    final secondary = onFill ? colors.onAccent : colors.secondary;
    final title = note.title.isEmpty ? l10n.newNote : note.title;
    final preview = note.preview.isEmpty ? l10n.noAdditionalText : note.preview;
    return _DragNote(
      id: note.id,
      label: title,
      child: GestureDetector(
        key: ValueKey('row ${note.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _listFocus.requestFocus();
          _open(note);
          setState(() {});
        },
        onDoubleTap: () {
          _open(note, focus: !note.trashed);
          setState(() {});
        },
        onSecondaryTapDown: (d) {
          _open(note);
          setState(() {});
          unawaited(_noteMenu(note, d.globalPosition));
        },
        child: SizedBox(
          height: NotesMetrics.listRow,
          child: Stack(
            children: [
              if (fill != null)
                Positioned(
                  left: NotesMetrics.selectionInsetX,
                  right: NotesMetrics.selectionInsetX,
                  top: NotesMetrics.selectionInsetY,
                  bottom: NotesMetrics.selectionInsetY,
                  child: DecoratedBox(
                    key: ValueKey('selection ${note.id}'),
                    decoration: ShapeDecoration(
                      color: fill,
                      shape: const AmalfiSmoothBorder(
                        radius: NotesMetrics.selectionRadius,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: NotesMetrics.rowTextX,
                right: NotesMetrics.rowTextX,
                top: NotesMetrics.rowTitleY,
                height: 18,
                child: Row(
                  children: [
                    if (note.pinned)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: AmalfiSymbol('pin', size: 12, color: secondary),
                      ),
                    Expanded(
                      child: _marked(
                        title,
                        AmalfiType.headline(color: primary),
                        colors,
                        onAccent: onFill,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: NotesMetrics.rowTextX,
                width: NotesMetrics.rowDateWidth,
                top: NotesMetrics.rowDetailY,
                height: 16,
                child: Text(
                  _rowDate(_dateOf(note)),
                  key: ValueKey('date ${note.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AmalfiType.callout(color: secondary),
                ),
              ),
              Positioned(
                left: NotesMetrics.rowPreviewX,
                right: NotesMetrics.rowTextX,
                top: NotesMetrics.rowDetailY,
                height: 32,
                child: _marked(
                  _search != null && note.folder.isNotEmpty
                      ? '${note.folder} · $preview'
                      : preview,
                  AmalfiType.callout(color: secondary),
                  colors,
                  maxLines: 2,
                  onAccent: onFill,
                ),
              ),
              if (separator && !chosen)
                Positioned(
                  left: NotesMetrics.rowTextX,
                  right: 0,
                  bottom: 0,
                  height: 1,
                  child: ColoredBox(color: colors.separator),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _noteMenu(Note note, Offset at) async {
    final targets = [
      if (!(note.folder == defaultFolder && !note.trashed)) defaultFolder,
      for (final f in _store.folders)
        if (f != note.folder || note.trashed) f,
    ];
    await showAmalfiMenu(
      context: context,
      position: at,
      minWidth: 220,
      entries: note.trashed
          ? [
              AmalfiMenuAction(l10n.recover, onSelected: () => _recover(note)),
              AmalfiMenuAction(
                l10n.moveTo,
                submenu: [
                  for (final f in [defaultFolder, ..._store.folders])
                    AmalfiMenuAction(
                      f.isEmpty ? l10n.defaultFolder : f,
                      onSelected: () => _moveNote(note, f),
                    ),
                ],
              ),
              const AmalfiMenuDivider(),
              AmalfiMenuAction(
                l10n.deleteForever,
                destructive: true,
                onSelected: deleteNote,
              ),
            ]
          : [
              AmalfiMenuAction(
                note.pinned ? l10n.unpinNote : l10n.pinNote,
                onSelected: togglePin,
              ),
              AmalfiMenuAction(l10n.duplicateNote, onSelected: duplicateNote),
              AmalfiMenuAction(
                l10n.moveTo,
                enabled: targets.isNotEmpty,
                submenu: [
                  for (final f in targets)
                    AmalfiMenuAction(
                      f.isEmpty ? l10n.defaultFolder : f,
                      onSelected: () => _moveNote(note, f),
                    ),
                ],
              ),
              const AmalfiMenuDivider(),
              AmalfiMenuAction(
                l10n.delete,
                destructive: true,
                onSelected: deleteNote,
              ),
            ],
    );
  }

  // MARK: gallery

  Widget _gallery(NotesColors colors) {
    final visible = [for (final s in _sections) ...s.notes];
    if (visible.isEmpty) {
      return _emptyState(
        colors,
        _search != null ? l10n.noResults : l10n.noNotes,
      );
    }
    return SingleChildScrollView(
      key: const ValueKey('gallery'),
      padding: const EdgeInsets.all(NotesMetrics.cardGap),
      child: Wrap(
        spacing: NotesMetrics.cardGap,
        runSpacing: NotesMetrics.cardGap,
        children: [
          for (final n in visible)
            SizedBox(
              width: NotesMetrics.cardWidth,
              height: NotesMetrics.cardHeight,
              child: _card(colors, n),
            ),
        ],
      ),
    );
  }

  Widget _card(NotesColors colors, Note note) {
    final chosen = note.id == _selected;
    return GestureDetector(
      key: ValueKey('card ${note.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _open(note);
        setState(() {});
      },
      onDoubleTap: () {
        _open(note, focus: !note.trashed);
        _settings.view = NotesView.list;
      },
      onSecondaryTapDown: (d) {
        _open(note);
        setState(() {});
        unawaited(_noteMenu(note, d.globalPosition));
      },
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: colors.card,
          shape: AmalfiSmoothBorder(
            radius: NotesMetrics.cardRadius,
            side: BorderSide(
              color: chosen ? colors.accent : colors.border,
              width: chosen ? 2 : 1,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(NotesMetrics.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (note.pinned)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: AmalfiSymbol(
                        'pin',
                        size: 12,
                        color: colors.secondary,
                      ),
                    ),
                  Expanded(
                    child: _marked(
                      note.title.isEmpty ? l10n.newNote : note.title,
                      AmalfiType.headline(color: colors.text),
                      colors,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: _marked(
                  note.preview,
                  AmalfiType.callout(color: colors.secondary),
                  colors,
                  maxLines: 7,
                ),
              ),
              Text(
                DateFormat.yMMMd(l10n.localeName).format(_dateOf(note)),
                style: AmalfiType.caption(color: colors.tertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // MARK: editor

  String _editorDate(Note note) {
    final locale = l10n.localeName;
    final d = note.modified;
    return l10n.dateAtTime(
      DateFormat.yMMMMd(locale).format(d),
      DateFormat.Hm(locale).format(d),
    );
  }

  Widget _editorPane(NotesColors colors) {
    final note = selectedNote;
    if (note == null) {
      return _emptyState(colors, l10n.noNoteSelected, big: true);
    }
    return _DropFiles(
      enabled: !note.trashed,
      onFiles: attachPaths,
      child: NoteEditor(
        key: const ValueKey('editor'),
        controller: _editor,
        focusNode: _editorFocus,
        scrollController: _editorScroll,
        date: _editorDate(note),
        readOnly: note.trashed,
        onReadOnlyEdit: _offerRecover,
        attachmentPath: (name) => _store.attachmentPath(note.id, name),
      ),
    );
  }
}

/// A note row that can be dragged onto a folder.
class _DragNote extends StatelessWidget {
  const _DragNote({required this.id, required this.label, required this.child});
  final String id;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = NotesColors.of(context);
    return Draggable<_NoteDrag>(
      data: _NoteDrag(id),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: ShapeDecoration(
          color: colors.card,
          shape: AmalfiSmoothBorder(
            radius: 8,
            side: BorderSide(color: colors.border),
          ),
        ),
        child: Text(label, style: AmalfiType.body(color: colors.text)),
      ),
      child: child,
    );
  }
}

class _NoteDrag {
  const _NoteDrag(this.id);
  final String id;
}

/// A folder row that takes a dragged note.
class _DropTarget extends StatelessWidget {
  const _DropTarget({
    required this.accepts,
    required this.onNote,
    required this.child,
  });
  final bool accepts;
  final void Function(String id) onNote;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!accepts) return child;
    final colors = NotesColors.of(context);
    return DragTarget<_NoteDrag>(
      onAcceptWithDetails: (d) => onNote(d.data.id),
      builder: (context, candidates, _) => DecoratedBox(
        decoration: candidates.isEmpty
            ? const BoxDecoration()
            : ShapeDecoration(
                shape: AmalfiSmoothBorder(
                  radius: 8,
                  side: BorderSide(color: colors.accent, width: 2),
                ),
              ),
        child: child,
      ),
    );
  }
}

/// Files dropped from the file manager onto the editor: attached at the caret. Drops between
/// apps arrive as [SilicaDrop]s from the embedder (silica_ui `drag.dart`).
class _DropFiles extends StatefulWidget {
  const _DropFiles({
    required this.enabled,
    required this.onFiles,
    required this.child,
  });
  final bool enabled;
  final void Function(List<String> paths) onFiles;
  final Widget child;

  @override
  State<_DropFiles> createState() => _DropFilesState();
}

class _DropFilesState extends State<_DropFiles> {
  StreamSubscription<SilicaDragEvent>? _drags;

  @override
  void initState() {
    super.initState();
    _drags = SilicaDrag.events.listen(_event);
  }

  @override
  void dispose() {
    unawaited(_drags?.cancel());
    super.dispose();
  }

  void _event(SilicaDragEvent event) {
    if (event is! SilicaDrop || !widget.enabled || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final local = box.globalToLocal(event.position);
    if (!(Offset.zero & box.size).contains(local)) return;
    final paths = event.paths;
    if (paths.isNotEmpty) widget.onFiles(paths);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
