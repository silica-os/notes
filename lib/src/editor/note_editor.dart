// The editor of a note (kit `Apps/Notes/Editor`): the date centred on top, then the text with
// its paragraph styles, list markers, checkboxes and attachments, and under a checklist how
// many items are done. The text is one EditableText over [NoteEditorController]; the clipboard
// and undo intents are taken over so that styles and markers survive them.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:silica_ui/silica_ui.dart';

import '../../l10n/app_localizations.dart';
import '../external.dart';
import '../model/rich.dart';
import '../style.dart';
import 'note_controller.dart';

/// Moves the caret's list items in or out (Tab, Shift-Tab).
class IndentIntent extends Intent {
  const IndentIntent(this.delta);
  final int delta;
}

class NoteEditor extends StatefulWidget {
  const NoteEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.date,
    required this.attachmentPath,
    this.readOnly = false,
    this.onReadOnlyEdit,
    this.scrollController,
  });

  final NoteEditorController controller;
  final FocusNode focusNode;

  /// The date shown on top ("16 October 2026 at 10:22").
  final String date;

  /// The file of attachment `name`.
  final String Function(String name) attachmentPath;

  /// A note in Recently Deleted: it can be read and copied, not changed.
  final bool readOnly;

  /// A key pressed in a read-only note (the window offers to recover it).
  final VoidCallback? onReadOnlyEdit;

  final ScrollController? scrollController;

  @override
  State<NoteEditor> createState() => NoteEditorState();
}

class NoteEditorState extends State<NoteEditor>
    implements TextSelectionGestureDetectorBuilderDelegate {
  @override
  final GlobalKey<EditableTextState> editableTextKey = GlobalKey();

  late final TextSelectionGestureDetectorBuilder _gestures =
      TextSelectionGestureDetectorBuilder(delegate: this);

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => true;

  NoteEditorController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
  }

  @override
  void didUpdateWidget(NoteEditor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    super.dispose();
  }

  (int, int) _checklist = (0, 0);

  void _changed() {
    final c = _c.doc.checklist;
    if (c != _checklist && mounted) setState(() => _checklist = c);
  }

  /// The secondary-click menu: the clipboard items.
  Future<void> _contextMenu(Offset position) async {
    final l = AppLocalizations.of(context);
    final sel = _c.value.selection;
    final hasSelection = sel.isValid && !sel.isCollapsed;
    await showAmalfiMenu(
      context: context,
      position: position,
      entries: [
        AmalfiMenuAction(
          l.cut,
          enabled: hasSelection && !widget.readOnly,
          onSelected: () => unawaited(_c.copy(cut: true)),
        ),
        AmalfiMenuAction(
          l.copy,
          enabled: hasSelection,
          onSelected: () => unawaited(_c.copy()),
        ),
        AmalfiMenuAction(
          l.paste,
          enabled: !widget.readOnly,
          onSelected: () => unawaited(_c.paste()),
        ),
        const AmalfiMenuDivider(),
        AmalfiMenuAction(
          l.selectAll,
          onSelected: () => _c.select(0, _c.text.length),
        ),
      ],
    );
  }

  Widget _marker(int line, Para para, int number, TextStyle style) {
    final colors = NotesColors.of(context);
    final indent = NotesMetrics.listIndent * para.indent;
    final height = (style.fontSize ?? 13) * (style.height ?? 1.4);
    Widget mark;
    double width;
    switch (para.style) {
      case ParaStyle.checklist:
        width = NotesMetrics.checklistMarker;
        mark = Listener(
          key: ValueKey('check $line'),
          behavior: HitTestBehavior.opaque,
          onPointerDown: widget.readOnly
              ? null
              : (e) {
                  if (e.buttons == kPrimaryButton) _c.toggleChecked(line);
                },
          child: MouseRegion(
            cursor: SystemMouseCursors.basic,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: AmalfiCheckboxFace(value: para.checked),
              ),
            ),
          ),
        );
      case ParaStyle.numbered:
        width = NotesMetrics.listMarker;
        mark = Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text('$number.', style: style, maxLines: 1, softWrap: false),
          ),
        );
      case ParaStyle.dashed:
        width = NotesMetrics.listMarker;
        mark = Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text('–', style: style, maxLines: 1, softWrap: false),
          ),
        );
      default:
        width = NotesMetrics.listMarker;
        mark = Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: NotesMetrics.bulletX),
            child: Container(
              width: NotesMetrics.bullet,
              height: NotesMetrics.bullet,
              decoration: BoxDecoration(
                color: colors.text,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
    }
    return SizedBox(
      width: indent + width,
      height: height,
      child: Padding(
        padding: EdgeInsets.only(left: indent),
        child: mark,
      ),
    );
  }

  double _contentWidth = 500;

  Widget _attachment(String name) => _Attachment(
    key: ValueKey('attachment $name'),
    name: name,
    path: widget.attachmentPath(name),
    maxWidth: max(40, _contentWidth - 2),
  );

  @override
  Widget build(BuildContext context) {
    final colors = NotesColors.of(context);
    final l = AppLocalizations.of(context);
    _c
      ..look = NoteLook(
        title: AmalfiType.title1().copyWith(
          height: NotesMetrics.titleLine / 26,
        ),
        heading: AmalfiType.title3().copyWith(
          height: NotesMetrics.headingLine / 16,
        ),
        subheading: AmalfiType.headline().copyWith(
          fontSize: 14,
          height: NotesMetrics.subheadingLine / 14,
        ),
        body: AmalfiType.body(),
        mono: AmalfiType.mono().copyWith(height: 18 / 12),
        list: AmalfiType.body().copyWith(height: NotesMetrics.listLine / 13),
        checklist: AmalfiType.body().copyWith(
          height: NotesMetrics.checklistLine / 13,
        ),
        text: colors.text,
        secondary: colors.secondary,
        highlight: colors.searchHighlight,
      )
      ..markerBuilder = _marker
      ..attachmentBuilder = _attachment;
    final active = WindowActiveScope.of(context);
    final editable = EditableText(
      key: editableTextKey,
      controller: _c,
      focusNode: widget.focusNode,
      readOnly: widget.readOnly,
      autocorrect: false,
      enableSuggestions: false,
      maxLines: null,
      style: AmalfiType.body(color: colors.text),
      // Each paragraph style has its own line height.
      strutStyle: StrutStyle.disabled,
      cursorColor: colors.accent,
      cursorWidth: 2,
      cursorOpacityAnimates: true,
      showCursor: active && !widget.readOnly,
      backgroundCursorColor: colors.tertiary,
      selectionColor: AmalfiTheme.of(context).selectionColor,
      rendererIgnoresPointer: true,
      enableInteractiveSelection: true,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      contextMenuBuilder: null,
    );
    final (done, total) = _c.doc.checklist;
    return LayoutBuilder(
      builder: (context, constraints) {
        _contentWidth = max(
          0.0,
          constraints.maxWidth - 2 * NotesMetrics.editorPaddingX,
        );
        return Actions(
          actions: {
            CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
              onInvoke: (i) {
                if (i.collapseSelection && widget.readOnly) return null;
                unawaited(_c.copy(cut: i.collapseSelection));
                return null;
              },
            ),
            PasteTextIntent: CallbackAction<PasteTextIntent>(
              onInvoke: (_) {
                if (widget.readOnly) {
                  widget.onReadOnlyEdit?.call();
                  return null;
                }
                unawaited(_c.paste());
                return null;
              },
            ),
            UndoTextIntent: CallbackAction<UndoTextIntent>(
              onInvoke: (_) {
                if (!widget.readOnly) _c.undo();
                return null;
              },
            ),
            RedoTextIntent: CallbackAction<RedoTextIntent>(
              onInvoke: (_) {
                if (!widget.readOnly) _c.redo();
                return null;
              },
            ),
            IndentIntent: CallbackAction<IndentIntent>(
              onInvoke: (i) {
                if (widget.readOnly) return null;
                if (!_c.indent(i.delta) && i.delta > 0) _c.insertText('\t');
                return null;
              },
            ),
          },
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (node, event) {
              if (widget.readOnly &&
                  event is KeyDownEvent &&
                  (event.character?.isNotEmpty ?? false) &&
                  !HardwareKeyboard.instance.isMetaPressed &&
                  !HardwareKeyboard.instance.isControlPressed) {
                widget.onReadOnlyEdit?.call();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.tab): IndentIntent(1),
                SingleActivator(LogicalKeyboardKey.tab, shift: true):
                    IndentIntent(-1),
              },
              child: SingleChildScrollView(
                controller: widget.scrollController,
                padding: const EdgeInsets.fromLTRB(
                  NotesMetrics.editorPaddingX,
                  NotesMetrics.editorDateTop,
                  NotesMetrics.editorPaddingX,
                  NotesMetrics.editorPaddingBottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.date,
                      key: const ValueKey('note date'),
                      textAlign: TextAlign.center,
                      style: AmalfiType.callout(color: colors.tertiary),
                    ),
                    const SizedBox(height: NotesMetrics.editorTitleGap),
                    MouseRegion(
                      cursor: SystemMouseCursors.text,
                      child: Listener(
                        onPointerDown: (e) {
                          if (e.buttons == kSecondaryButton) {
                            unawaited(_contextMenu(e.position));
                          }
                        },
                        child: _gestures.buildGestureDetector(
                          behavior: HitTestBehavior.translucent,
                          child: editable,
                        ),
                      ),
                    ),
                    if (total > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 28),
                        child: Text(
                          l.checklistDone(done, total),
                          key: const ValueKey('checklist progress'),
                          style: AmalfiType.callout(color: colors.tertiary),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// An attachment in the text: an image as a picture as wide as the text allows, any other
/// file as a chip with its name that opens it.
class _Attachment extends StatelessWidget {
  const _Attachment({
    super.key,
    required this.name,
    required this.path,
    required this.maxWidth,
  });

  final String name;
  final String path;
  final double maxWidth;

  static const _images = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};

  bool get _isImage {
    final dot = name.lastIndexOf('.');
    return dot > 0 && _images.contains(name.substring(dot + 1).toLowerCase());
  }

  void _open() {
    if (startsNothing) return;
    unawaited(
      Process.start(
        'xdg-open',
        [path],
        mode: ProcessStartMode.detached,
      ).then<void>((_) {}).catchError((Object _) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = NotesColors.of(context);
    if (_isImage && File(path).existsSync()) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: GestureDetector(
          onDoubleTap: _open,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: NotesMetrics.imageMaxHeight,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(NotesMetrics.pictureRadius),
              child: Image.file(
                File(path),
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => _chip(colors),
              ),
            ),
          ),
        ),
      );
    }
    return _chip(colors);
  }

  Widget _chip(NotesColors colors) {
    var size = '';
    try {
      final bytes = File(path).lengthSync();
      size = bytes < 1024
          ? '$bytes B'
          : bytes < 1024 * 1024
          ? '${(bytes / 1024).toStringAsFixed(0)} KB'
          : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } on FileSystemException {
      // Missing: the name only.
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        onTap: _open,
        child: Container(
          constraints: BoxConstraints(maxWidth: min(maxWidth, 360)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: ShapeDecoration(
            color: colors.accentSoft,
            shape: const AmalfiSmoothBorder(radius: NotesMetrics.chipRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AmalfiGlyph(AmalfiGlyphs.doc, size: 16, color: colors.accent),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AmalfiType.body(color: colors.text),
                ),
              ),
              if (size.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(size, style: AmalfiType.callout(color: colors.secondary)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
