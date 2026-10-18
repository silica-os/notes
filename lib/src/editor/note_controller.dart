// The editing controller of a note: a TextEditingController over a [NoteText]. Every change
// of the text, typed or programmatic, goes through [value]: the change is found by comparing
// the old and new text, the inline styles and paragraphs are carried over, and the list
// markers are kept where they belong (a new line of a list gets one, a deleted marker ends the
// list, Return on an empty item ends it). Format commands, the undo history and the rich
// clipboard live here too; [buildTextSpan] draws the paragraphs, markers and attachments.

import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../model/rich.dart';

/// How the text is drawn: one style per paragraph style and the colours.
class NoteLook {
  const NoteLook({
    required this.title,
    required this.heading,
    required this.subheading,
    required this.body,
    required this.mono,
    required this.list,
    required this.checklist,
    required this.text,
    required this.secondary,
    required this.highlight,
  });

  final TextStyle title;
  final TextStyle heading;
  final TextStyle subheading;
  final TextStyle body;
  final TextStyle mono;

  /// List items: the body with room between the items.
  final TextStyle list;

  /// Checklist items: room for the checkbox.
  final TextStyle checklist;
  final Color text;
  final Color secondary;

  /// The background of search matches.
  final Color highlight;

  TextStyle of(ParaStyle s) => switch (s) {
    ParaStyle.title => title,
    ParaStyle.heading => heading,
    ParaStyle.subheading => subheading,
    ParaStyle.mono => mono,
    ParaStyle.body => body,
    ParaStyle.checklist => checklist,
    _ => list,
  };
}

/// Builds the widget of a list marker of paragraph [line].
typedef MarkerBuilder =
    Widget Function(int line, Para para, int number, TextStyle style);

/// Builds the widget of attachment [name].
typedef AttachmentBuilder = Widget Function(String name);

class _Snapshot {
  const _Snapshot(this.doc, this.selection);
  final NoteText doc;
  final TextSelection selection;
}

enum _EditKind { typing, deleting, other }

/// A copied fragment: its plain text (what went to the clipboard) and the rich text.
class _Clip {
  const _Clip(this.plain, this.text, this.styles, this.paras);
  final String plain;
  final String text;
  final List<Inline> styles;
  final List<Para> paras;
}

class NoteEditorController extends TextEditingController {
  NoteEditorController({NoteText? text}) : this._(text ?? NoteText.empty());

  NoteEditorController._(NoteText doc)
    : _doc = doc,
      super.fromValue(
        TextEditingValue(
          text: doc.text,
          selection: TextSelection.collapsed(offset: doc.text.length),
        ),
      );

  NoteText _doc;
  bool _internal = false;

  /// The text.
  NoteText get doc => _doc;

  /// The style the next typed text takes at [_pendingAt] (Bold with nothing selected).
  Inline? _pending;
  int? _pendingAt;

  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];
  _EditKind _lastKind = _EditKind.other;
  int _lastEnd = -1;
  DateTime _lastTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// How many steps Undo keeps.
  static const int undoLimit = 200;

  /// A rich fragment being pasted: its text and styles go in as they are.
  _Clip? _pasting;

  /// The last fragment copied from a note.
  static _Clip? _clip;

  // Presentation, set by the editor before it builds.
  NoteLook? look;
  MarkerBuilder? markerBuilder;
  AttachmentBuilder? attachmentBuilder;

  /// The search text whose matches are marked (lower case); empty: none.
  String highlight = '';

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Replaces the whole text (another note opened): no undo across notes.
  void load(NoteText doc, {TextSelection? selection}) {
    _doc = doc;
    _undo.clear();
    _redo.clear();
    _pending = null;
    _lastKind = _EditKind.other;
    _set(selection ?? TextSelection.collapsed(offset: doc.text.length));
  }

  void _set(TextSelection selection, {TextRange composing = TextRange.empty}) {
    _internal = true;
    try {
      super.value = TextEditingValue(
        text: _doc.text,
        selection: _fit(selection, _doc.text.length),
        composing: composing,
      );
    } finally {
      _internal = false;
    }
  }

  static TextSelection _fit(TextSelection s, int length) {
    if (!s.isValid) return TextSelection.collapsed(offset: length);
    return s.copyWith(
      baseOffset: s.baseOffset.clamp(0, length),
      extentOffset: s.extentOffset.clamp(0, length),
    );
  }

  @override
  set value(TextEditingValue v) {
    if (_internal) {
      super.value = v;
      return;
    }
    final old = _doc;
    if (v.text == old.text) {
      final sel = _clampCaret(v.selection, old, value.selection);
      if (sel != value.selection) _pending = null;
      _internal = true;
      try {
        super.value = v.copyWith(selection: sel);
      } finally {
        _internal = false;
      }
      return;
    }
    // The change: the common start and end of the old and new text. The caret after a typed
    // character tells where it went when the text around it repeats.
    final oldText = old.text;
    final newText = v.text;
    final minLen = min(oldText.length, newText.length);
    final grow = newText.length - oldText.length;
    var limit = minLen;
    if (v.selection.isValid && v.selection.isCollapsed) {
      final hint = v.selection.baseOffset - max<int>(0, grow);
      if (hint >= 0) limit = min(limit, hint);
    }
    var p = 0;
    while (p < limit && oldText.codeUnitAt(p) == newText.codeUnitAt(p)) {
      p++;
    }
    var s = 0;
    while (s < minLen - p &&
        oldText.codeUnitAt(oldText.length - 1 - s) ==
            newText.codeUnitAt(newText.length - 1 - s)) {
      s++;
    }
    final oldEnd = oldText.length - s;
    final inserted = newText.substring(p, newText.length - s);
    final clip = _pasting;
    _pasting = null;
    final styles = clip != null && clip.text == inserted
        ? clip.styles
        : _typed(old, p, oldEnd, inserted);
    final fresh = clip != null && clip.text == inserted ? clip.paras : null;
    _replace(
      p,
      oldEnd,
      inserted,
      styles,
      freshParas: fresh,
      selection: v.selection,
      composing: v.composing,
    );
  }

  /// The styles of [inserted] typed over [p, end): the pending style, else the style of the
  /// text before (or after, at the start of a line).
  List<Inline> _typed(NoteText old, int p, int end, String inserted) {
    Inline style;
    if (_pending != null && _pendingAt == p) {
      style = _pending!;
    } else if (end > p) {
      style = Runs.at(old.runs, p).typing;
    } else if (p > 0 && old.text.codeUnitAt(p - 1) != 0x0A) {
      style = Runs.at(old.runs, p - 1).typing;
    } else if (p < old.text.length && old.text.codeUnitAt(p) != 0x0A) {
      style = Runs.at(old.runs, p).typing;
    } else {
      style = Inline.plain;
    }
    return [
      for (var i = 0; i < inserted.length; i++)
        inserted.codeUnitAt(i) == 0x0A ? Inline.plain : style,
    ];
  }

  /// Characters [p, oldEnd) of the text replaced by [inserted] (with [styles]); [selection] is
  /// in the coordinates of the text before the markers are fixed. [freshParas] gives the
  /// paragraphs of the new lines (a pasted fragment).
  void _replace(
    int p,
    int oldEnd,
    String inserted,
    List<Inline> styles, {
    List<Para>? freshParas,
    TextSelection? selection,
    TextRange composing = TextRange.empty,
    _EditKind? kind,
  }) {
    final old = _doc;
    final before = value.selection;
    final newText = old.text.replaceRange(p, oldEnd, inserted);
    final sel =
        selection ?? TextSelection.collapsed(offset: p + inserted.length);
    final lp = old.lineAt(p);
    final le = old.lineAt(oldEnd);

    // Return on an empty list item ends the list (an indented one moves out one level).
    if (inserted == '\n' &&
        oldEnd == p &&
        old.paras[lp].style.isList &&
        old.line(lp) == objectChar &&
        p == old.lineEnd(lp)) {
      _record(old, before, _EditKind.other);
      final para = old.paras[lp];
      if (para.indent > 0) {
        _doc = NoteText(
          old.text,
          old.runs,
          [...old.paras]..[lp] = para.copyWith(indent: para.indent - 1),
        );
        _set(TextSelection.collapsed(offset: p));
      } else {
        final start = old.lineStart(lp);
        _doc = NoteText(
          old.text.replaceRange(start, start + 1, ''),
          Runs.replace(old.runs, start, start + 1, const []),
          [...old.paras]..[lp] = Para.body,
        );
        _set(TextSelection.collapsed(offset: start));
      }
      return;
    }

    final regionStart = old.lineStart(lp);
    final oldRegionEnd = old.lineEnd(le);
    final grow = newText.length - old.text.length;
    final regionEnd = oldRegionEnd + grow;
    final regionText = newText.substring(regionStart, regionEnd);
    final regionStyles = <Inline>[
      ...Runs.styles(old.runs, regionStart, p),
      ...styles,
      ...Runs.styles(old.runs, oldEnd, oldRegionEnd),
    ];
    assert(regionStyles.length == regionText.length);

    // The paragraphs of the new lines.
    final newlines = '\n'.allMatches(inserted).length;
    final whole = p == regionStart && le > lp;
    final base = whole ? old.paras[le] : old.paras[lp];
    final onlyNewlines =
        inserted.isNotEmpty && inserted.replaceAll('\n', '').isEmpty;
    final atContentStart =
        oldEnd == p &&
        onlyNewlines &&
        p == old.contentStart(lp) &&
        p < old.lineEnd(lp);
    final paras = <Para>[
      if (atContentStart) ...[
        for (var i = 0; i < newlines; i++)
          base.style.isList ? base.copyWith(checked: false) : base,
        base,
      ] else ...[
        base,
        for (var i = 1; i <= newlines; i++)
          freshParas != null && i < freshParas.length
              ? freshParas[i]
              : base.next,
      ],
    ];

    // Each line of the region: markers where they belong, stray objects out.
    final outText = StringBuffer();
    final outStyles = <Inline>[];
    final outParas = <Para>[];
    final map = List<int>.filled(regionText.length + 1, 0);
    var changed = false;
    var lineStart = 0;
    for (var i = 0; i < paras.length; i++) {
      var lineEnd = regionText.indexOf('\n', lineStart);
      if (lineEnd < 0) lineEnd = regionText.length;
      var para = paras[i];
      final fresh = atContentStart ? i < paras.length - 1 : i > 0;
      final hasMarker =
          lineEnd > lineStart &&
          regionText.codeUnitAt(lineStart) == objectUnit &&
          regionStyles[lineStart].marker;
      var addMarker = false;
      if (para.style.isList && !hasMarker) {
        if (fresh || atContentStart) {
          addMarker = true;
        } else {
          para = Para.body;
        }
      }
      if (i == 0 && atContentStart && para.style.isList && hasMarker) {
        addMarker = false;
      }
      outParas.add(para);
      if (addMarker) {
        outText.write(objectChar);
        outStyles.add(Inline.listMarker);
        changed = true;
      }
      for (var j = lineStart; j < lineEnd; j++) {
        map[j] = outText.length;
        final c = regionText.codeUnitAt(j);
        final st = regionStyles[j];
        if (c == objectUnit) {
          final keepMarker =
              st.marker && j == lineStart && para.style.isList && !addMarker;
          if (!(keepMarker || st.attachment != null)) {
            changed = true;
            continue;
          }
        }
        outText.writeCharCode(c);
        outStyles.add(c == objectUnit ? st : (st.isObject ? Inline.plain : st));
      }
      map[lineEnd] = outText.length;
      if (lineEnd < regionText.length) {
        outText.write('\n');
        outStyles.add(Inline.plain);
      }
      lineStart = lineEnd + 1;
    }
    final out = outText.toString();
    final text = newText.replaceRange(regionStart, regionEnd, out);
    final runs = Runs.replace(
      Runs.replace(old.runs, p, oldEnd, Runs.fromStyles(styles)),
      regionStart,
      regionEnd,
      Runs.fromStyles(outStyles),
    );
    final allParas = [
      ...old.paras.sublist(0, lp),
      ...outParas,
      ...old.paras.sublist(le + 1),
    ];
    final delta = out.length - regionText.length;
    int mapOffset(int o) {
      if (o < regionStart) return o;
      if (o > regionEnd) return o + delta;
      return regionStart + map[o - regionStart];
    }

    final editKind =
        kind ??
        (oldEnd == p && inserted.length == 1 && inserted != '\n'
            ? _EditKind.typing
            : inserted.isEmpty && oldEnd - p == 1
            ? _EditKind.deleting
            : _EditKind.other);
    _recordEdit(old, before, editKind, p, p + inserted.length);
    _doc = NoteText(text, runs, allParas);
    _pending = null;
    final mapped = sel.isValid
        ? sel.copyWith(
            baseOffset: mapOffset(sel.baseOffset),
            extentOffset: mapOffset(sel.extentOffset),
          )
        : TextSelection.collapsed(offset: mapOffset(p + inserted.length));
    _set(
      _clampCaret(mapped, _doc, before),
      composing: changed || !composing.isValid
          ? TextRange.empty
          : TextRange(
              start: mapOffset(composing.start),
              end: mapOffset(composing.end),
            ),
    );
  }

  /// A caret in front of a list marker goes after it (or, moving left, to the line above).
  static TextSelection _clampCaret(
    TextSelection sel,
    NoteText doc,
    TextSelection previous,
  ) {
    if (!sel.isValid || !sel.isCollapsed) return sel;
    final o = sel.baseOffset;
    if (!doc.hasMarkerAt(o)) return sel;
    final left =
        previous.isValid &&
        previous.isCollapsed &&
        previous.baseOffset == o + 1;
    if (left && o > 0) return TextSelection.collapsed(offset: o - 1);
    return TextSelection.collapsed(offset: o + 1);
  }

  // MARK: undo

  void _recordEdit(
    NoteText old,
    TextSelection selection,
    _EditKind kind,
    int start,
    int end,
  ) {
    final now = DateTime.now();
    final merge =
        kind != _EditKind.other &&
        kind == _lastKind &&
        now.difference(_lastTime) < const Duration(seconds: 2) &&
        (kind == _EditKind.typing
            ? start == _lastEnd
            : end == _lastEnd || start == _lastEnd - 1);
    if (!merge) _push(old, selection);
    _lastKind = kind;
    _lastEnd = kind == _EditKind.deleting ? start : end;
    _lastTime = now;
    _redo.clear();
  }

  void _record(NoteText old, TextSelection selection, _EditKind kind) =>
      _recordEdit(old, selection, kind, -1, -1);

  void _push(NoteText doc, TextSelection selection) {
    _undo.add(_Snapshot(doc, selection));
    if (_undo.length > undoLimit) _undo.removeAt(0);
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_Snapshot(_doc, value.selection));
    final s = _undo.removeLast();
    _doc = s.doc;
    _lastKind = _EditKind.other;
    _pending = null;
    _set(s.selection);
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_Snapshot(_doc, value.selection));
    final s = _redo.removeLast();
    _doc = s.doc;
    _lastKind = _EditKind.other;
    _pending = null;
    _set(s.selection);
  }

  /// A programmatic change of the whole text, undoable.
  void _commit(NoteText doc, TextSelection selection) {
    if (doc == _doc) {
      _set(selection);
      return;
    }
    _record(_doc, value.selection, _EditKind.other);
    _doc = doc;
    _set(selection);
  }

  // MARK: clipboard

  /// The selection as plain text (markers written as text) for the clipboard.
  String selectedPlainText() {
    final sel = value.selection;
    if (!sel.isValid || sel.isCollapsed) return '';
    return _doc.plainText(start: sel.start, end: sel.end);
  }

  /// Copies the selection: plain text to the clipboard, the rich fragment kept for pasting
  /// into a note.
  Future<void> copy({bool cut = false}) async {
    final sel = value.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final plain = selectedPlainText();
    final first = _doc.lineAt(sel.start);
    final last = _doc.lineAt(sel.end);
    _clip = _Clip(
      plain,
      _doc.text.substring(sel.start, sel.end),
      Runs.styles(_doc.runs, sel.start, sel.end),
      _doc.paras.sublist(first, last + 1),
    );
    await Clipboard.setData(ClipboardData(text: plain));
    if (cut) {
      _replace(sel.start, sel.end, '', const [], kind: _EditKind.other);
    }
  }

  /// Pastes the clipboard: a fragment copied from a note keeps its styles; other text goes in
  /// plain.
  Future<void> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    final sel = value.selection;
    if (text == null || !sel.isValid) return;
    final clip = _clip;
    if (clip != null && clip.plain == text) {
      _replace(
        sel.start,
        sel.end,
        clip.text,
        clip.styles,
        freshParas: clip.paras,
        kind: _EditKind.other,
      );
      return;
    }
    final clean = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(objectChar, '');
    _replace(
      sel.start,
      sel.end,
      clean,
      _typed(_doc, sel.start, sel.end, clean),
      kind: _EditKind.other,
    );
  }

  // MARK: formatting

  /// The lines the selection touches.
  (int, int) get selectedLines {
    final sel = value.selection;
    if (!sel.isValid) return (0, 0);
    return (_doc.lineAt(sel.start), _doc.lineAt(sel.end));
  }

  /// The paragraph style at the caret.
  Para get currentPara => _doc.paras[selectedLines.$1];

  /// The inline style the next typed text takes, or of the selection's first character.
  Inline get currentInline {
    final sel = value.selection;
    if (!sel.isValid) return Inline.plain;
    if (sel.isCollapsed) {
      if (_pending != null && _pendingAt == sel.baseOffset) return _pending!;
      return _typed(_doc, sel.baseOffset, sel.baseOffset, 'x').first;
    }
    for (var i = sel.start; i < sel.end; i++) {
      final s = Runs.at(_doc.runs, i);
      if (!s.isObject && _doc.text.codeUnitAt(i) != 0x0A) return s;
    }
    return Inline.plain;
  }

  /// Whether the selection (or the typing style) has [trait].
  bool hasTrait(InlineTrait trait) {
    final sel = value.selection;
    if (!sel.isValid) return false;
    if (sel.isCollapsed) return currentInline.has(trait);
    var any = false;
    for (final r in Runs.slice(_doc.runs, sel.start, sel.end)) {
      if (r.style.isObject) continue;
      any = true;
      if (!r.style.has(trait)) return false;
    }
    return any;
  }

  /// Bold, italic, underline or strikethrough on the selection, or for the next typed text.
  void toggleTrait(InlineTrait trait) {
    final sel = value.selection;
    if (!sel.isValid) return;
    final on = !hasTrait(trait);
    if (sel.isCollapsed) {
      _pending = currentInline.withTrait(trait, on);
      _pendingAt = sel.baseOffset;
      notifyListeners();
      return;
    }
    _commit(
      NoteText(
        _doc.text,
        Runs.map(
          _doc.runs,
          sel.start,
          sel.end,
          (s) => s.isObject ? s : s.withTrait(trait, on),
        ),
        _doc.paras,
      ),
      sel,
    );
  }

  /// [style] on the selected paragraphs; a list style they all have already turns them back
  /// into body text.
  void setParaStyle(ParaStyle style, {bool toggle = false}) {
    final (first, last) = selectedLines;
    final all = [
      for (var i = first; i <= last; i++) _doc.paras[i].style,
    ].every((s) => s == style);
    final target = toggle && all && style.isList ? ParaStyle.body : style;
    var text = _doc.text;
    var runs = _doc.runs;
    final paras = [..._doc.paras];
    final sel = value.selection;
    var base = sel.baseOffset;
    var extent = sel.extentOffset;
    for (var line = first; line <= last; line++) {
      final start = _lineStartIn(text, line);
      final had = paras[line].style.isList;
      final wants = target.isList;
      void moved(int at, int by) {
        if (base > at || (base == at && by > 0)) base += by;
        if (extent > at || (extent == at && by > 0)) extent += by;
      }

      if (wants && !had) {
        text = text.replaceRange(start, start, objectChar);
        runs = Runs.replace(runs, start, start, const [
          Run(1, Inline.listMarker),
        ]);
        moved(start, 1);
      } else if (!wants && had && _hasMarker(text, runs, start)) {
        text = text.replaceRange(start, start + 1, '');
        runs = Runs.replace(runs, start, start + 1, const []);
        moved(start, -1);
      }
      paras[line] = paras[line].copyWith(style: target);
    }
    final doc = NoteText(text, runs, paras);
    _commit(
      doc,
      _clampCaret(
        TextSelection(
          baseOffset: base.clamp(0, text.length),
          extentOffset: extent.clamp(0, text.length),
        ),
        doc,
        const TextSelection.collapsed(offset: -1),
      ),
    );
  }

  static bool _hasMarker(String text, List<Run> runs, int at) =>
      at < text.length &&
      text.codeUnitAt(at) == objectUnit &&
      Runs.at(runs, at).marker;

  static int _lineStartIn(String text, int line) {
    var at = 0;
    for (var i = 0; i < line; i++) {
      final nl = text.indexOf('\n', at);
      if (nl < 0) return text.length;
      at = nl + 1;
    }
    return at;
  }

  /// Ticks or unticks checklist item [line].
  void toggleChecked(int line) {
    if (line < 0 || line >= _doc.paras.length) return;
    final p = _doc.paras[line];
    if (p.style != ParaStyle.checklist) return;
    _commit(
      NoteText(
        _doc.text,
        _doc.runs,
        [..._doc.paras]..[line] = p.copyWith(checked: !p.checked),
      ),
      value.selection,
    );
  }

  /// Ticks the selected checklist items, or unticks them if all are ticked.
  void markChecked() {
    final (first, last) = selectedLines;
    final items = [
      for (var i = first; i <= last; i++)
        if (_doc.paras[i].style == ParaStyle.checklist) i,
    ];
    if (items.isEmpty) return;
    final on = !items.every((i) => _doc.paras[i].checked);
    final paras = [..._doc.paras];
    for (final i in items) {
      paras[i] = paras[i].copyWith(checked: on);
    }
    _commit(NoteText(_doc.text, _doc.runs, paras), value.selection);
  }

  /// Whether the selection has checklist items.
  bool get hasChecklistItems {
    final (first, last) = selectedLines;
    for (var i = first; i <= last; i++) {
      if (_doc.paras[i].style == ParaStyle.checklist) return true;
    }
    return false;
  }

  /// Moves the selected list items in ([delta] 1) or out (-1); false if none is a list item.
  bool indent(int delta) {
    final (first, last) = selectedLines;
    final paras = [..._doc.paras];
    var any = false;
    for (var i = first; i <= last; i++) {
      if (!paras[i].style.isList) continue;
      any = true;
      paras[i] = paras[i].copyWith(indent: paras[i].indent + delta);
    }
    if (!any) return false;
    _commit(NoteText(_doc.text, _doc.runs, paras), value.selection);
    return true;
  }

  /// Puts attachment [name] at the caret, on a line of its own.
  void insertAttachment(String name) {
    final sel = value.selection;
    final start = sel.isValid ? sel.start : _doc.text.length;
    final end = sel.isValid ? sel.end : _doc.text.length;
    final line = _doc.lineAt(start);
    final before = start > _doc.contentStart(line);
    final after = end < _doc.lineEnd(_doc.lineAt(end));
    final text = '${before ? '\n' : ''}$objectChar${after ? '\n' : ''}';
    final styles = [
      if (before) Inline.plain,
      Inline(attachment: name),
      if (after) Inline.plain,
    ];
    _replace(
      start,
      end,
      text,
      styles,
      freshParas: [Para.body, Para.body, Para.body],
      kind: _EditKind.other,
    );
    // The attachment's line is a body line, whatever the line it came from.
    final at = _doc.text.indexOf(objectChar, start);
    if (at < 0) return;
    final l = _doc.lineAt(at);
    if (_doc.paras[l] != Para.body && !_doc.paras[l].style.isList) {
      _doc = NoteText(_doc.text, _doc.runs, [..._doc.paras]..[l] = Para.body);
      _set(value.selection);
    }
  }

  /// Inserts plain [text] at the caret (over the selection).
  void insertText(String text) {
    final sel = value.selection;
    final start = sel.isValid ? sel.start : _doc.text.length;
    final end = sel.isValid ? sel.end : _doc.text.length;
    _replace(start, end, text, _typed(_doc, start, end, text));
  }

  /// Draws the text again (the search marks changed).
  void refresh() => notifyListeners();

  /// Selects [start, end).
  void select(int start, int end) =>
      _set(TextSelection(baseOffset: start, extentOffset: end));

  // MARK: drawing

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final look = this.look;
    if (look == null) return TextSpan(style: style, text: text);
    final doc = _doc;
    if (doc.text != text) return TextSpan(style: style, text: text);
    final marks = _matches(doc.text, highlight);
    final composing = withComposing && value.isComposingRangeValid
        ? value.composing
        : TextRange.empty;
    final children = <InlineSpan>[];
    var at = 0;
    for (var line = 0; line < doc.paras.length; line++) {
      final para = doc.paras[line];
      final base = look.of(para.style).copyWith(color: look.text);
      final end = doc.text.indexOf('\n', at);
      final lineEnd = end < 0 ? doc.text.length : end;
      var pos = at;
      for (final run in Runs.slice(doc.runs, at, lineEnd)) {
        final runEnd = pos + run.length;
        final s = run.style;
        if (s.marker) {
          for (var i = 0; i < run.length; i++) {
            children.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                style: base,
                child:
                    markerBuilder?.call(
                      line,
                      para,
                      para.style == ParaStyle.numbered
                          ? doc.listNumber(line)
                          : 0,
                      base,
                    ) ??
                    const SizedBox(width: 24, height: 1),
              ),
            );
          }
        } else if (s.attachment case final name?) {
          for (var i = 0; i < run.length; i++) {
            children.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.bottom,
                style: base,
                child:
                    attachmentBuilder?.call(name) ??
                    const SizedBox(width: 1, height: 1),
              ),
            );
          }
        } else {
          final runStyle = _inlineStyle(base, s, para.style == ParaStyle.mono);
          // Split at the search matches and the composing range.
          var a = pos;
          while (a < runEnd) {
            var b = runEnd;
            var marked = false;
            for (final (ms, me) in marks) {
              if (me <= a) continue;
              if (ms > a) {
                b = min(b, ms);
              } else {
                marked = true;
                b = min(b, me);
              }
              break;
            }
            if (composing.isValid) {
              if (composing.start > a && composing.start < b) {
                b = composing.start;
              } else if (composing.end > a && composing.end < b) {
                b = composing.end;
              }
            }
            final inComposing =
                composing.isValid && a >= composing.start && b <= composing.end;
            var st = runStyle;
            if (marked) st = st.copyWith(backgroundColor: look.highlight);
            if (inComposing) {
              st = st.copyWith(
                decoration: TextDecoration.combine([
                  ?st.decoration,
                  TextDecoration.underline,
                ]),
              );
            }
            children.add(TextSpan(text: doc.text.substring(a, b), style: st));
            a = b;
          }
        }
        pos = runEnd;
      }
      if (lineEnd == at) {
        // An empty line still takes its paragraph's height.
        children.add(TextSpan(text: '', style: base));
      }
      if (end >= 0) children.add(TextSpan(text: '\n', style: base));
      at = lineEnd + 1;
    }
    return TextSpan(style: style, children: children);
  }

  static TextStyle _inlineStyle(TextStyle base, Inline s, bool mono) {
    if (mono) return base;
    if (!s.bold && !s.italic && !s.underline && !s.strike) return base;
    final w = base.fontWeight ?? FontWeight.w400;
    return base.copyWith(
      fontWeight: s.bold
          ? (w.value >= 600 ? FontWeight.w800 : FontWeight.w700)
          : null,
      fontStyle: s.italic ? FontStyle.italic : null,
      decoration: s.underline || s.strike
          ? TextDecoration.combine([
              if (s.underline) TextDecoration.underline,
              if (s.strike) TextDecoration.lineThrough,
            ])
          : null,
    );
  }

  /// The ranges of [query] in [text], ignoring case.
  static List<(int, int)> _matches(String text, String query) {
    if (query.isEmpty) return const [];
    final lower = text.toLowerCase();
    if (lower.length != text.length) return const [];
    final out = <(int, int)>[];
    var at = 0;
    while (true) {
      final hit = lower.indexOf(query, at);
      if (hit < 0) break;
      out.add((hit, hit + query.length));
      at = hit + query.length;
    }
    return out;
  }
}
