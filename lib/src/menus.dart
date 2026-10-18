// Notes' menus in Silica's menu bar (silica-menu-v1): the app menu, File, Edit, Format, View,
// Window and Help. Items that do not apply now are disabled; what Notes cannot do is not
// listed. The shortcuts are bound by SilicaMenuBar while the app has the keyboard.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:silica_ui/silica_ui.dart';

import '../l10n/app_localizations.dart';
import 'editor/note_controller.dart';
import 'model/rich.dart';
import 'settings.dart';

/// What the menus act on: the window.
abstract interface class NotesCommands {
  NoteEditorController get editor;
  NotesSettings get settings;

  /// A note is open.
  bool get hasNote;

  /// The open note can be changed (it is not in Recently Deleted).
  bool get canEdit;
  bool get noteInTrash;
  bool get notePinned;
  bool get trashHasNotes;
  bool get editorFocused;

  void newNote();
  void newFolder();
  void deleteNote();
  void togglePin();
  void duplicateNote();
  void emptyTrash();
  Future<void> attachFile({bool photo = false});
  void setParaStyle(ParaStyle style, {bool toggle = false});
  void toggleTrait(InlineTrait trait);
  void markChecked();
  void indent(int delta);
  void undo();
  void redo();
  void focusSearch();
  void toggleSidebar();
  void setView(NotesView view);
}

SingleActivator _cmd(
  LogicalKeyboardKey key, {
  bool shift = false,
  bool alt = false,
  bool control = false,
}) =>
    SingleActivator(key, meta: true, shift: shift, alt: alt, control: control);

List<PlatformMenuItem> notesMenus(AppLocalizations l, NotesCommands c) {
  final edit = c.canEdit;
  final editing = edit && c.editorFocused;
  final e = c.editor;
  final para = c.hasNote ? e.currentPara.style : ParaStyle.body;
  SilicaMenuItem style(
    ParaStyle s,
    String label,
    LogicalKeyboardKey key, {
    bool toggle = false,
  }) => SilicaMenuItem(
    label: label,
    shortcut: _cmd(key, shift: true),
    checked: c.hasNote && para == s,
    enabled: edit,
    onSelected: edit ? () => c.setParaStyle(s, toggle: toggle) : null,
  );
  SilicaMenuItem trait(InlineTrait t, String label, LogicalKeyboardKey? key) =>
      SilicaMenuItem(
        label: label,
        shortcut: key == null ? null : _cmd(key),
        checked: edit && e.hasTrait(t),
        enabled: edit,
        onSelected: edit ? () => c.toggleTrait(t) : null,
      );
  const cause = SelectionChangedCause.keyboard;
  SilicaMenuItem text(
    SilicaMenuItemRole role,
    Intent intent,
    SingleActivator? shortcut, {
    bool enabled = true,
  }) => SilicaMenuItem(
    role: role,
    shortcut: shortcut,
    onSelectedIntent: enabled ? intent : null,
    enabled: enabled,
  );
  final view = c.settings.view;
  final sort = c.settings.sort;
  return [
    SilicaMenus.app(l.appTitle),
    SilicaMenu(
      label: l.menuFile,
      menus: [
        PlatformMenuItemGroup(
          members: [
            SilicaMenuItem(
              label: l.newNote,
              shortcut: _cmd(LogicalKeyboardKey.keyN),
              onSelected: c.newNote,
            ),
            SilicaMenuItem(
              label: l.newFolder,
              shortcut: _cmd(LogicalKeyboardKey.keyN, shift: true),
              onSelected: c.newFolder,
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: [SilicaMenuItem.system(SilicaMenuItemRole.close)],
        ),
        PlatformMenuItemGroup(
          members: [
            SilicaMenuItem(
              label: c.notePinned ? l.unpinNote : l.pinNote,
              enabled: edit,
              onSelected: edit ? c.togglePin : null,
            ),
            SilicaMenuItem(
              label: l.duplicateNote,
              shortcut: _cmd(LogicalKeyboardKey.keyD),
              enabled: edit,
              onSelected: edit ? c.duplicateNote : null,
            ),
            SilicaMenuItem(
              label: c.noteInTrash ? l.deleteForever : l.delete,
              enabled: c.hasNote,
              onSelected: c.hasNote ? c.deleteNote : null,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            SilicaMenuItem(
              label: l.emptyRecentlyDeleted,
              enabled: c.trashHasNotes,
              onSelected: c.trashHasNotes ? c.emptyTrash : null,
            ),
          ],
        ),
      ],
    ),
    SilicaMenu(
      label: l.menuEdit,
      menus: [
        PlatformMenuItemGroup(
          members: [
            SilicaMenuItem(
              role: SilicaMenuItemRole.undo,
              shortcut: _cmd(LogicalKeyboardKey.keyZ),
              enabled: editing && e.canUndo,
              onSelected: editing && e.canUndo ? c.undo : null,
            ),
            SilicaMenuItem(
              role: SilicaMenuItemRole.redo,
              shortcut: _cmd(LogicalKeyboardKey.keyZ, shift: true),
              enabled: editing && e.canRedo,
              onSelected: editing && e.canRedo ? c.redo : null,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            text(
              SilicaMenuItemRole.cut,
              const CopySelectionTextIntent.cut(cause),
              _cmd(LogicalKeyboardKey.keyX),
            ),
            text(
              SilicaMenuItemRole.copy,
              CopySelectionTextIntent.copy,
              _cmd(LogicalKeyboardKey.keyC),
            ),
            text(
              SilicaMenuItemRole.paste,
              const PasteTextIntent(cause),
              _cmd(LogicalKeyboardKey.keyV),
            ),
            text(
              SilicaMenuItemRole.selectAll,
              const SelectAllTextIntent(cause),
              _cmd(LogicalKeyboardKey.keyA),
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            SilicaMenuItem(
              label: l.attachFileMenu,
              shortcut: _cmd(LogicalKeyboardKey.keyA, shift: true),
              enabled: edit,
              onSelected: edit ? () => c.attachFile() : null,
            ),
            SilicaMenuItem(
              label: l.addPhotoMenu,
              enabled: edit,
              onSelected: edit ? () => c.attachFile(photo: true) : null,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            SilicaMenuItem(
              label: l.searchNotes,
              shortcut: _cmd(LogicalKeyboardKey.keyF, alt: true),
              onSelected: c.focusSearch,
            ),
          ],
        ),
      ],
    ),
    SilicaMenu(
      label: l.menuFormat,
      menus: [
        PlatformMenuItemGroup(
          members: [
            style(ParaStyle.title, l.styleTitle, LogicalKeyboardKey.keyT),
            style(ParaStyle.heading, l.styleHeading, LogicalKeyboardKey.keyH),
            style(
              ParaStyle.subheading,
              l.styleSubheading,
              LogicalKeyboardKey.keyJ,
            ),
            style(ParaStyle.body, l.styleBody, LogicalKeyboardKey.keyB),
            style(ParaStyle.mono, l.styleMono, LogicalKeyboardKey.keyM),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            style(
              ParaStyle.bulleted,
              l.bulletedList,
              LogicalKeyboardKey.digit7,
              toggle: true,
            ),
            style(
              ParaStyle.dashed,
              l.dashedList,
              LogicalKeyboardKey.digit8,
              toggle: true,
            ),
            style(
              ParaStyle.numbered,
              l.numberedList,
              LogicalKeyboardKey.digit9,
              toggle: true,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            style(
              ParaStyle.checklist,
              l.checklist,
              LogicalKeyboardKey.keyL,
              toggle: true,
            ),
            SilicaMenuItem(
              label: l.markAsChecked,
              shortcut: _cmd(LogicalKeyboardKey.keyU, shift: true),
              enabled: edit && e.hasChecklistItems,
              onSelected: edit && e.hasChecklistItems ? c.markChecked : null,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            SilicaMenu(
              label: l.menuFont,
              enabled: edit,
              menus: [
                trait(InlineTrait.bold, l.bold, LogicalKeyboardKey.keyB),
                trait(InlineTrait.italic, l.italic, LogicalKeyboardKey.keyI),
                trait(
                  InlineTrait.underline,
                  l.underline,
                  LogicalKeyboardKey.keyU,
                ),
                trait(InlineTrait.strike, l.strikethrough, null),
              ],
            ),
            SilicaMenu(
              label: l.menuIndentation,
              enabled: edit && para.isList,
              menus: [
                SilicaMenuItem(
                  label: l.increaseIndent,
                  shortcut: _cmd(LogicalKeyboardKey.bracketRight),
                  enabled: edit && para.isList,
                  onSelected: edit && para.isList ? () => c.indent(1) : null,
                ),
                SilicaMenuItem(
                  label: l.decreaseIndent,
                  shortcut: _cmd(LogicalKeyboardKey.bracketLeft),
                  enabled: edit && para.isList,
                  onSelected: edit && para.isList ? () => c.indent(-1) : null,
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    SilicaMenu(
      label: l.menuView,
      menus: [
        PlatformMenuItemGroup(
          members: [
            SilicaMenuItem(
              label: l.viewAsList,
              shortcut: _cmd(LogicalKeyboardKey.digit1),
              checked: view == NotesView.list,
              onSelected: () => c.setView(NotesView.list),
            ),
            SilicaMenuItem(
              label: l.viewAsGallery,
              shortcut: _cmd(LogicalKeyboardKey.digit2),
              checked: view == NotesView.gallery,
              onSelected: () => c.setView(NotesView.gallery),
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            SilicaMenu(
              label: l.sortBy,
              menus: [
                for (final (s, label) in [
                  (NotesSort.edited, l.sortEdited),
                  (NotesSort.created, l.sortCreated),
                  (NotesSort.title, l.sortTitle),
                ])
                  SilicaMenuItem(
                    label: label,
                    checked: sort == s,
                    onSelected: () => c.settings.sort = s,
                  ),
              ],
            ),
            SilicaMenuItem(
              label: l.groupByDate,
              checked: c.settings.groupByDate,
              enabled: sort != NotesSort.title,
              onSelected: sort != NotesSort.title
                  ? () => c.settings.groupByDate = !c.settings.groupByDate
                  : null,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            SilicaMenuItem(
              label: c.settings.sidebar ? l.hideFolders : l.showFolders,
              shortcut: _cmd(LogicalKeyboardKey.keyS, control: true),
              onSelected: c.toggleSidebar,
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: [SilicaMenuItem.system(SilicaMenuItemRole.fullScreen)],
        ),
      ],
    ),
    SilicaMenus.window(l.menuWindow),
    SilicaMenus.help(l.menuHelp),
  ];
}
