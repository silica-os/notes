// The file format of a note: a line-oriented subset of Markdown (docs/format.md), readable in
// any text editor and by Markdown tools. One line of the file is one paragraph of the note:
//
//   # Title          ## Heading       ### Subheading
//   - item           + dashed item     1. numbered item
//   - [ ] to do      - [x] done        (two spaces before the marker per indentation level)
//   ```              monostyled lines between fences, kept as they are
//   **bold**  *italic*  <u>underline</u>  ~~strikethrough~~  ![name](attachments/name)
//
// Characters that would start a style are escaped with a backslash, and a body line that
// would read as another paragraph style starts with one. A header in an HTML comment holds
// the dates, the pin and, in Recently Deleted, where the note was.

import 'rich.dart';

/// What the header of a note file holds.
class NoteHeader {
  NoteHeader({
    required this.created,
    required this.modified,
    this.pinned = false,
    this.folder,
    this.deleted,
  });

  DateTime created;
  DateTime modified;
  bool pinned;

  /// In Recently Deleted: the folder the note was in ('' for the default folder).
  String? folder;

  /// In Recently Deleted: when the note was deleted.
  DateTime? deleted;
}

const String _headerStart = '<!-- silica-notes';
const String _headerEnd = '-->';

/// The file of a note: the header, then the text.
String writeNoteFile(NoteHeader header, NoteText text) {
  final b = StringBuffer()
    ..writeln(_headerStart)
    ..writeln('created: ${header.created.toUtc().toIso8601String()}')
    ..writeln('modified: ${header.modified.toUtc().toIso8601String()}');
  if (header.pinned) b.writeln('pinned: yes');
  if (header.folder case final f?) b.writeln('folder: $f');
  if (header.deleted case final d?) {
    b.writeln('deleted: ${d.toUtc().toIso8601String()}');
  }
  b
    ..writeln(_headerEnd)
    ..write(writeMarkdown(text));
  return b.toString();
}

/// A note file read back; [fallbackDate] is used for dates the header does not give (a file
/// written by another program: its modification time).
(NoteHeader, NoteText) readNoteFile(String source, DateTime fallbackDate) {
  var lines = source
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  final header = NoteHeader(created: fallbackDate, modified: fallbackDate);
  if (lines.isNotEmpty && lines.first.trim() == _headerStart) {
    var end = 1;
    while (end < lines.length && lines[end].trim() != _headerEnd) {
      final line = lines[end];
      final colon = line.indexOf(':');
      if (colon > 0) {
        final key = line.substring(0, colon).trim();
        final value = line.substring(colon + 1).trim();
        switch (key) {
          case 'created':
            header.created =
                DateTime.tryParse(value)?.toLocal() ?? fallbackDate;
          case 'modified':
            header.modified =
                DateTime.tryParse(value)?.toLocal() ?? fallbackDate;
          case 'pinned':
            header.pinned = value == 'yes' || value == 'true';
          case 'folder':
            header.folder = value;
          case 'deleted':
            header.deleted = DateTime.tryParse(value)?.toLocal();
        }
      }
      end++;
    }
    lines = end < lines.length ? lines.sublist(end + 1) : const [];
  }
  return (header, readMarkdown(lines.join('\n')));
}

// MARK: writing

/// The text as Markdown lines.
String writeMarkdown(NoteText note) {
  final out = <String>[];
  var inFence = false;
  for (var line = 0; line < note.paras.length; line++) {
    final para = note.paras[line];
    final start = note.lineStart(line);
    final end = note.lineEnd(line);
    final raw = note.text.substring(start, end);
    final mono = para.style == ParaStyle.mono && !raw.contains(objectChar);
    if (mono != inFence) {
      out.add('```');
      inFence = mono;
    }
    if (mono) {
      out.add(raw.startsWith('```') || raw.startsWith(r'\') ? '\\$raw' : raw);
      continue;
    }
    final content = _inline(note, note.contentStart(line), end);
    final indent = '  ' * para.indent;
    out.add(switch (para.style) {
      ParaStyle.title => '# $content',
      ParaStyle.heading => '## $content',
      ParaStyle.subheading => '### $content',
      ParaStyle.bulleted => '$indent- $content',
      ParaStyle.dashed => '$indent+ $content',
      ParaStyle.numbered => '$indent${note.listNumber(line)}. $content',
      ParaStyle.checklist => '$indent- [${para.checked ? 'x' : ' '}] $content',
      ParaStyle.body ||
      ParaStyle.mono => _blockLike.hasMatch(content) ? '\\$content' : content,
    });
  }
  if (inFence) out.add('```');
  return out.join('\n');
}

/// A line that would read as something other than a body paragraph.
final RegExp _blockLike = RegExp(r'^\s*(#|[-+*](?: |$)|\d+\.(?: |$)|```|>)');

const String _escaped = r'\*~<[]_`';

String _inline(NoteText note, int start, int end) {
  final b = StringBuffer();
  var bold = false, italic = false, underline = false, strike = false;
  void toggle(Inline s) {
    if (s.bold != bold) {
      b.write('**');
      bold = s.bold;
    }
    if (s.italic != italic) {
      b.write('*');
      italic = s.italic;
    }
    if (s.strike != strike) {
      b.write('~~');
      strike = s.strike;
    }
    if (s.underline != underline) {
      b.write(s.underline ? '<u>' : '</u>');
      underline = s.underline;
    }
  }

  var at = start;
  for (final run in Runs.slice(note.runs, start, end)) {
    final s = run.style;
    if (s.attachment case final name?) {
      for (var i = 0; i < run.length; i++) {
        b.write('![${_escape(name)}](attachments/${_encodePath(name)})');
      }
    } else if (!s.marker) {
      toggle(s);
      final chunk = note.text.substring(at, at + run.length);
      b.write(_escape(chunk.replaceAll(objectChar, '')));
    }
    at += run.length;
  }
  toggle(Inline.plain);
  return b.toString();
}

/// [name] as a path in a link: parentheses encoded too, so the link ends at its own `)`.
String _encodePath(String name) =>
    Uri.encodeComponent(name).replaceAll('(', '%28').replaceAll(')', '%29');

String _escape(String s) {
  final b = StringBuffer();
  for (final c in s.split('')) {
    if (_escaped.contains(c)) b.write(r'\');
    b.write(c);
  }
  return b.toString();
}

// MARK: reading

final RegExp _heading = RegExp(r'^(#{1,3})(?: (.*))?$');
final RegExp _list = RegExp(r'^( *)(?:([-+*])|(\d+)\.)(?: (.*))?$');
final RegExp _check = RegExp(r'^\[([ xX])\](?: (.*))?$');

/// Markdown lines as the text of a note. Anything it does not know stays as text.
NoteText readMarkdown(String source) {
  final lines = source.split('\n');
  final text = StringBuffer();
  final styles = <Inline>[];
  final paras = <Para>[];
  var inFence = false;
  var first = true;
  void add(Para para, String content, {bool raw = false}) {
    if (!first) {
      text.write('\n');
      styles.add(Inline.plain);
    }
    first = false;
    paras.add(para);
    if (para.style.isList) {
      text.write(objectChar);
      styles.add(Inline.listMarker);
    }
    if (raw) {
      final clean = content.replaceAll(objectChar, '');
      text.write(clean);
      styles.addAll(List.filled(clean.length, Inline.plain));
      return;
    }
    for (final (chunk, style) in _parseInline(content)) {
      text.write(chunk);
      styles.addAll(List.filled(chunk.length, style));
    }
  }

  for (final line in lines) {
    if (line.trimRight() == '```') {
      inFence = !inFence;
      continue;
    }
    if (inFence) {
      add(
        const Para(ParaStyle.mono),
        line.startsWith(r'\') ? line.substring(1) : line,
        raw: true,
      );
      continue;
    }
    if (_heading.firstMatch(line) case final m?) {
      final style = switch (m.group(1)!.length) {
        1 => ParaStyle.title,
        2 => ParaStyle.heading,
        _ => ParaStyle.subheading,
      };
      add(Para(style), m.group(2) ?? '');
      continue;
    }
    if (_list.firstMatch(line) case final m?) {
      final indent = (m.group(1)!.length ~/ 2).clamp(0, Para.maxIndent);
      final rest = m.group(4) ?? '';
      final bullet = m.group(2);
      if (bullet == '-' || bullet == '*') {
        if (_check.firstMatch(rest) case final c?) {
          add(
            Para(
              ParaStyle.checklist,
              checked: c.group(1) != ' ',
              indent: indent,
            ),
            c.group(2) ?? '',
          );
        } else {
          add(Para(ParaStyle.bulleted, indent: indent), rest);
        }
      } else if (bullet == '+') {
        add(Para(ParaStyle.dashed, indent: indent), rest);
      } else {
        add(Para(ParaStyle.numbered, indent: indent), rest);
      }
      continue;
    }
    var body = line;
    if (body.length > 1 &&
        body.startsWith(r'\') &&
        !_escaped.contains(body[1])) {
      body = body.substring(1);
    }
    add(Para.body, body);
  }
  if (paras.isEmpty) return NoteText.empty();
  return NoteText(text.toString(), Runs.fromStyles(styles), paras);
}

List<(String, Inline)> _parseInline(String s) {
  final out = <(String, Inline)>[];
  var style = Inline.plain;
  final b = StringBuffer();
  void flush() {
    if (b.isEmpty) return;
    out.add((b.toString(), style));
    b.clear();
  }

  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == r'\' && i + 1 < s.length && _escaped.contains(s[i + 1])) {
      b.write(s[i + 1]);
      i += 2;
      continue;
    }
    if (s.startsWith('**', i)) {
      flush();
      style = style.copyWith(bold: !style.bold);
      i += 2;
      continue;
    }
    if (c == '*') {
      flush();
      style = style.copyWith(italic: !style.italic);
      i += 1;
      continue;
    }
    if (s.startsWith('~~', i)) {
      flush();
      style = style.copyWith(strike: !style.strike);
      i += 2;
      continue;
    }
    if (s.startsWith('<u>', i)) {
      flush();
      style = style.copyWith(underline: true);
      i += 3;
      continue;
    }
    if (s.startsWith('</u>', i)) {
      flush();
      style = style.copyWith(underline: false);
      i += 4;
      continue;
    }
    if (s.startsWith('![', i)) {
      var close = s.indexOf('](', i + 2);
      while (close > 0 && s[close - 1] == r'\') {
        close = s.indexOf('](', close + 1);
      }
      final end = close < 0 ? -1 : s.indexOf(')', close + 2);
      if (close >= 0 && end >= 0) {
        final path = s.substring(close + 2, end);
        if (path.startsWith('attachments/')) {
          String name;
          try {
            name = Uri.decodeComponent(path.substring('attachments/'.length));
          } on ArgumentError {
            name = path.substring('attachments/'.length);
          }
          if (name.isNotEmpty && !name.contains('/')) {
            flush();
            out.add((objectChar, Inline(attachment: name)));
            i = end + 1;
            continue;
          }
        }
      }
    }
    if (c != objectChar) b.write(c);
    i++;
  }
  flush();
  return out;
}
