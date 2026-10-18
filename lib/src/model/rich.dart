// The rich text of a note: the characters, the inline style of each one (as runs) and the
// style of each paragraph (one per line).
//
// Objects in the text are U+FFFC characters, the placeholder of an inline widget: the marker
// at the start of a list paragraph (bullet, dash, number or checkbox) and attachments. An
// object character carries what it is in its inline style ([Inline.marker],
// [Inline.attachment]), so it moves with the text.

import 'package:flutter/foundation.dart';

/// The object replacement character: one per inline widget.
const String objectChar = '\uFFFC';
const int objectUnit = 0xFFFC;

/// The inline style of one character.
@immutable
class Inline {
  const Inline({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.marker = false,
    this.attachment,
  });

  static const Inline plain = Inline();
  static const Inline listMarker = Inline(marker: true);

  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;

  /// The marker of a list paragraph (its first character).
  final bool marker;

  /// The file name of an attachment, in the note's attachment folder.
  final String? attachment;

  /// Whether the character is an object (a marker or an attachment).
  bool get isObject => marker || attachment != null;

  /// The style text typed after this character takes.
  Inline get typing => isObject ? plain : this;

  Inline copyWith({bool? bold, bool? italic, bool? underline, bool? strike}) =>
      Inline(
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        strike: strike ?? this.strike,
        marker: marker,
        attachment: attachment,
      );

  @override
  bool operator ==(Object other) =>
      other is Inline &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.strike == strike &&
      other.marker == marker &&
      other.attachment == attachment;

  @override
  int get hashCode =>
      Object.hash(bold, italic, underline, strike, marker, attachment);

  @override
  String toString() =>
      'Inline(${[if (bold) 'b', if (italic) 'i', if (underline) 'u', if (strike) 's', if (marker) 'marker', ?attachment].join(',')})';
}

/// The inline styles a format command toggles.
enum InlineTrait { bold, italic, underline, strike }

extension InlineTraits on Inline {
  bool has(InlineTrait t) => switch (t) {
    InlineTrait.bold => bold,
    InlineTrait.italic => italic,
    InlineTrait.underline => underline,
    InlineTrait.strike => strike,
  };

  Inline withTrait(InlineTrait t, bool on) => switch (t) {
    InlineTrait.bold => copyWith(bold: on),
    InlineTrait.italic => copyWith(italic: on),
    InlineTrait.underline => copyWith(underline: on),
    InlineTrait.strike => copyWith(strike: on),
  };
}

/// [length] characters in [style].
@immutable
class Run {
  const Run(this.length, this.style);
  final int length;
  final Inline style;

  @override
  bool operator ==(Object other) =>
      other is Run && other.length == length && other.style == style;

  @override
  int get hashCode => Object.hash(length, style);

  @override
  String toString() => 'Run($length, $style)';
}

/// The style of a paragraph.
enum ParaStyle {
  title,
  heading,
  subheading,
  body,
  mono,
  bulleted,
  dashed,
  numbered,
  checklist;

  /// A list paragraph: it starts with a marker.
  bool get isList =>
      this == bulleted ||
      this == dashed ||
      this == numbered ||
      this == checklist;
}

/// A paragraph's style, whether its checkbox is ticked and its list indentation.
@immutable
class Para {
  const Para(this.style, {this.checked = false, this.indent = 0});

  static const Para body = Para(ParaStyle.body);
  static const Para title = Para(ParaStyle.title);

  /// The deepest list indentation.
  static const int maxIndent = 8;

  final ParaStyle style;
  final bool checked;
  final int indent;

  /// The style of the line made by Return at the end of this one: lists go on (unticked),
  /// titles and headings give way to the body.
  Para get next => switch (style) {
    ParaStyle.title || ParaStyle.heading || ParaStyle.subheading => Para.body,
    ParaStyle.body || ParaStyle.mono => Para(style),
    _ => Para(style, indent: indent),
  };

  Para copyWith({ParaStyle? style, bool? checked, int? indent}) {
    final s = style ?? this.style;
    return Para(
      s,
      checked: s == ParaStyle.checklist ? (checked ?? this.checked) : false,
      indent: s.isList ? (indent ?? this.indent).clamp(0, maxIndent) : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Para &&
      other.style == style &&
      other.checked == checked &&
      other.indent == indent;

  @override
  int get hashCode => Object.hash(style, checked, indent);

  @override
  String toString() =>
      'Para(${style.name}${checked ? ', checked' : ''}${indent > 0 ? ', $indent' : ''})';
}

/// Runs: operations on a run list that return a new one (runs are never changed in place).
abstract final class Runs {
  /// Adjacent runs of the same style merged, empty ones dropped.
  static List<Run> merged(Iterable<Run> runs) {
    final out = <Run>[];
    for (final r in runs) {
      if (r.length <= 0) continue;
      if (out.isNotEmpty && out.last.style == r.style) {
        out[out.length - 1] = Run(out.last.length + r.length, r.style);
      } else {
        out.add(r);
      }
    }
    return out;
  }

  /// Runs of one style per character.
  static List<Run> fromStyles(Iterable<Inline> styles) =>
      merged(styles.map((s) => Run(1, s)));

  static int length(List<Run> runs) {
    var n = 0;
    for (final r in runs) {
      n += r.length;
    }
    return n;
  }

  /// The runs covering characters [start, end).
  static List<Run> slice(List<Run> runs, int start, int end) {
    final out = <Run>[];
    var at = 0;
    for (final r in runs) {
      final a = at;
      final b = at + r.length;
      at = b;
      if (b <= start) continue;
      if (a >= end) break;
      final from = a < start ? start : a;
      final to = b > end ? end : b;
      if (to > from) out.add(Run(to - from, r.style));
    }
    return out;
  }

  /// Characters [start, end) replaced by [inserted].
  static List<Run> replace(
    List<Run> runs,
    int start,
    int end,
    List<Run> inserted,
  ) => merged([
    ...slice(runs, 0, start),
    ...inserted,
    ...slice(runs, end, length(runs)),
  ]);

  /// The style of character [index]; [Inline.plain] outside the text.
  static Inline at(List<Run> runs, int index) {
    if (index < 0) return Inline.plain;
    var at = 0;
    for (final r in runs) {
      if (index < at + r.length) return r.style;
      at += r.length;
    }
    return Inline.plain;
  }

  /// One style per character of [start, end).
  static List<Inline> styles(List<Run> runs, int start, int end) => [
    for (final r in slice(runs, start, end))
      for (var i = 0; i < r.length; i++) r.style,
  ];

  /// [f] applied to the style of characters [start, end).
  static List<Run> map(
    List<Run> runs,
    int start,
    int end,
    Inline Function(Inline) f,
  ) => merged([
    ...slice(runs, 0, start),
    for (final r in slice(runs, start, end)) Run(r.length, f(r.style)),
    ...slice(runs, end, length(runs)),
  ]);
}

/// The whole text of a note: characters, their runs and one paragraph per line.
@immutable
class NoteText {
  NoteText(this.text, List<Run> runs, List<Para> paras)
    : runs = List.unmodifiable(runs),
      paras = List.unmodifiable(paras) {
    assert(Runs.length(runs) == text.length, 'runs do not cover the text');
    assert(
      paras.length == '\n'.allMatches(text).length + 1,
      'one paragraph per line',
    );
  }

  /// An empty note: one empty title line.
  factory NoteText.empty({Para first = Para.title}) =>
      NoteText('', const [], [first]);

  /// Plain [text] in body paragraphs (a title first when [titled]).
  factory NoteText.plain(String text, {bool titled = false}) {
    final lines = text.split('\n');
    return NoteText(
      text,
      [if (text.isNotEmpty) Run(text.length, Inline.plain)],
      [
        for (var i = 0; i < lines.length; i++)
          i == 0 && titled ? Para.title : Para.body,
      ],
    );
  }

  final String text;
  final List<Run> runs;
  final List<Para> paras;

  /// The offset where line [line] starts.
  int lineStart(int line) {
    var at = 0;
    for (var i = 0; i < line; i++) {
      final nl = text.indexOf('\n', at);
      if (nl < 0) return text.length;
      at = nl + 1;
    }
    return at;
  }

  /// The offset where line [line] ends (its newline or the end of the text).
  int lineEnd(int line) {
    final start = lineStart(line);
    final nl = text.indexOf('\n', start);
    return nl < 0 ? text.length : nl;
  }

  /// The line holding offset [offset].
  int lineAt(int offset) {
    var line = 0;
    final end = offset.clamp(0, text.length);
    for (var i = 0; i < end; i++) {
      if (text.codeUnitAt(i) == 0x0A) line++;
    }
    return line;
  }

  /// The text of line [line].
  String line(int line) => text.substring(lineStart(line), lineEnd(line));

  /// Where the editable content of line [line] starts: after its marker.
  int contentStart(int line) {
    final start = lineStart(line);
    if (paras[line].style.isList && hasMarkerAt(start)) return start + 1;
    return start;
  }

  /// Whether a list marker is at [offset].
  bool hasMarkerAt(int offset) =>
      offset >= 0 &&
      offset < text.length &&
      text.codeUnitAt(offset) == objectUnit &&
      Runs.at(runs, offset).marker;

  /// The text of the line without objects, trimmed: what titles and previews show.
  String lineText(int line) {
    final start = lineStart(line);
    final end = lineEnd(line);
    final b = StringBuffer();
    for (var i = start; i < end; i++) {
      final c = text.codeUnitAt(i);
      if (c != objectUnit) b.writeCharCode(c);
    }
    return b.toString().trim();
  }

  /// The plain text: objects out, list markers written as text (copy, export).
  String plainText({int start = 0, int? end}) {
    final stop = end ?? text.length;
    final b = StringBuffer();
    var line = lineAt(start);
    var number = _numberOf(line);
    for (var i = start; i < stop; i++) {
      final c = text.codeUnitAt(i);
      if (c == 0x0A) {
        line++;
        number = _numberOf(line);
        b.write('\n');
        continue;
      }
      if (c == objectUnit) {
        final style = Runs.at(runs, i);
        if (style.marker && line < paras.length) {
          final p = paras[line];
          b.write('  ' * p.indent);
          b.write(switch (p.style) {
            ParaStyle.bulleted => '• ',
            ParaStyle.dashed => '– ',
            ParaStyle.numbered => '$number. ',
            ParaStyle.checklist => p.checked ? '☑ ' : '☐ ',
            _ => '',
          });
        } else if (style.attachment != null) {
          b.write(style.attachment);
        }
        continue;
      }
      b.writeCharCode(c);
    }
    return b.toString();
  }

  int _numberOf(int line) => line < paras.length ? listNumber(line) : 1;

  /// The number of numbered line [line]: 1 + the numbered lines just above it at its level.
  int listNumber(int line) {
    final p = paras[line];
    var n = 1;
    for (var i = line - 1; i >= 0; i--) {
      final q = paras[i];
      if (!q.style.isList) break;
      if (q.indent > p.indent) continue;
      if (q.indent < p.indent || q.style != ParaStyle.numbered) break;
      n++;
    }
    return n;
  }

  /// The attachments, in order.
  List<String> get attachments => [
    for (final r in runs)
      if (r.style.attachment case final a?) a,
  ];

  /// How many checklist items there are, and how many are ticked.
  (int done, int total) get checklist {
    var done = 0;
    var total = 0;
    for (final p in paras) {
      if (p.style != ParaStyle.checklist) continue;
      total++;
      if (p.checked) done++;
    }
    return (done, total);
  }

  @override
  bool operator ==(Object other) =>
      other is NoteText &&
      other.text == text &&
      listEquals(other.runs, runs) &&
      listEquals(other.paras, paras);

  @override
  int get hashCode =>
      Object.hash(text, Object.hashAll(runs), Object.hashAll(paras));

  @override
  String toString() => 'NoteText(${text.replaceAll(objectChar, '¤')}, $paras)';
}
