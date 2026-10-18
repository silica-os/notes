// The editing controller: typing keeps styles and list markers where they belong, the format
// commands, undo and the rich clipboard.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/src/editor/note_controller.dart';
import 'package:notes/src/model/rich.dart';

const o = objectChar;

/// Types [s] at the caret, as the text input does.
void type(NoteEditorController c, String s) {
  final v = c.value;
  final sel = v.selection;
  c.value = TextEditingValue(
    text: v.text.replaceRange(sel.start, sel.end, s),
    selection: TextSelection.collapsed(offset: sel.start + s.length),
  );
}

/// Backspace at the caret.
void backspace(NoteEditorController c) {
  final v = c.value;
  final sel = v.selection;
  if (!sel.isCollapsed) {
    c.value = TextEditingValue(
      text: v.text.replaceRange(sel.start, sel.end, ''),
      selection: TextSelection.collapsed(offset: sel.start),
    );
    return;
  }
  if (sel.start == 0) return;
  c.value = TextEditingValue(
    text: v.text.replaceRange(sel.start - 1, sel.start, ''),
    selection: TextSelection.collapsed(offset: sel.start - 1),
  );
}

void caret(NoteEditorController c, int offset) =>
    c.selection = TextSelection.collapsed(offset: offset);

List<ParaStyle> styles(NoteEditorController c) =>
    c.doc.paras.map((p) => p.style).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a new note starts with a title; Return gives a body line', () {
    final c = NoteEditorController();
    type(c, 'Shopping');
    type(c, '\n');
    type(c, 'milk');
    expect(c.text, 'Shopping\nmilk');
    expect(styles(c), [ParaStyle.title, ParaStyle.body]);
  });

  test('a list goes on with Return and ends with Return on an empty item', () {
    final c = NoteEditorController();
    type(c, 'List\n');
    c.setParaStyle(ParaStyle.bulleted, toggle: true);
    expect(c.text, 'List\n$o');
    expect(c.selection.baseOffset, 6);
    type(c, 'eggs');
    type(c, '\n');
    expect(c.text, 'List\n${o}eggs\n$o');
    expect(c.selection.baseOffset, c.text.length);
    type(c, 'milk\n');
    type(c, '\n');
    expect(c.text, 'List\n${o}eggs\n${o}milk\n');
    expect(styles(c), [
      ParaStyle.title,
      ParaStyle.bulleted,
      ParaStyle.bulleted,
      ParaStyle.body,
    ]);
  });

  test('Backspace after a marker ends the list item, keeping its text', () {
    final c = NoteEditorController(
      text: NoteText(
        '${o}eggs',
        const [Run(1, Inline.listMarker), Run(4, Inline.plain)],
        const [Para(ParaStyle.checklist, checked: true)],
      ),
    );
    caret(c, 1);
    backspace(c);
    expect(c.text, 'eggs');
    expect(styles(c), [ParaStyle.body]);
  });

  test('Return at the start of a list item makes an empty item above', () {
    final c = NoteEditorController(
      text: NoteText(
        '${o}eggs',
        const [Run(1, Inline.listMarker), Run(4, Inline.plain)],
        const [Para(ParaStyle.checklist, checked: true)],
      ),
    );
    caret(c, 1);
    type(c, '\n');
    expect(c.text, '$o\n${o}eggs');
    expect(c.doc.paras, const [
      Para(ParaStyle.checklist),
      Para(ParaStyle.checklist, checked: true),
    ]);
  });

  test('the caret never stops before a marker', () {
    final c = NoteEditorController(
      text: NoteText(
        'a\n${o}b',
        const [
          Run(2, Inline.plain),
          Run(1, Inline.listMarker),
          Run(1, Inline.plain),
        ],
        const [Para.body, Para(ParaStyle.bulleted)],
      ),
    );
    caret(c, 2);
    expect(c.selection.baseOffset, 3);
    // Moving left from after the marker goes to the line above.
    caret(c, 2);
    expect(c.selection.baseOffset, 1);
  });

  test('bold on a selection, and for the next typed text', () {
    final c = NoteEditorController(text: NoteText.plain('hello world'));
    c.select(0, 5);
    c.toggleTrait(InlineTrait.bold);
    expect(Runs.at(c.doc.runs, 0).bold, isTrue);
    expect(Runs.at(c.doc.runs, 6).bold, isFalse);
    expect(c.hasTrait(InlineTrait.bold), isTrue);
    caret(c, 11);
    c.toggleTrait(InlineTrait.italic);
    type(c, '!');
    expect(Runs.at(c.doc.runs, 11).italic, isTrue);
    // Text typed after bold text is bold.
    caret(c, 5);
    type(c, 'X');
    expect(Runs.at(c.doc.runs, 5).bold, isTrue);
  });

  test('paragraph styles, checklist ticks, indentation and undo', () {
    final c = NoteEditorController(text: NoteText.plain('a\nb\nc'));
    c.select(0, 3);
    c.setParaStyle(ParaStyle.checklist, toggle: true);
    expect(c.text, '${o}a\n${o}b\nc');
    c.toggleChecked(1);
    expect(c.doc.paras[1].checked, isTrue);
    expect(c.doc.checklist, (1, 2));
    caret(c, 1);
    expect(c.indent(1), isTrue);
    expect(c.doc.paras[0].indent, 1);
    c.undo();
    expect(c.doc.paras[0].indent, 0);
    c.undo();
    expect(c.doc.paras[1].checked, isFalse);
    c.undo();
    expect(c.text, 'a\nb\nc');
    c.redo();
    expect(c.text, '${o}a\n${o}b\nc');
    // The same list style again turns the lines back into body text.
    c.select(0, 5);
    c.setParaStyle(ParaStyle.checklist, toggle: true);
    expect(c.text, 'a\nb\nc');
    c.select(0, 0);
    c.setParaStyle(ParaStyle.heading);
    expect(styles(c).first, ParaStyle.heading);
  });

  test('typing a word is one undo step', () {
    final c = NoteEditorController();
    for (final ch in 'hello'.split('')) {
      type(c, ch);
    }
    c.undo();
    expect(c.text, '');
  });

  test('copy writes plain text; pasting it back keeps the styles', () async {
    String? clipboard;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
          }
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          return null;
        });
    final c = NoteEditorController(
      text: NoteText(
        'x\n${o}bold',
        const [
          Run(2, Inline.plain),
          Run(1, Inline.listMarker),
          Run(4, Inline(bold: true)),
        ],
        const [Para.title, Para(ParaStyle.checklist, checked: true)],
      ),
    );
    c.select(0, c.text.length);
    await c.copy();
    expect(clipboard, 'x\n☑ bold');
    caret(c, c.text.length);
    type(c, '\n');
    await c.paste();
    expect(c.doc.paras.last, const Para(ParaStyle.checklist, checked: true));
    expect(Runs.at(c.doc.runs, c.text.length - 1).bold, isTrue);
    // Text from elsewhere goes in plain, objects out.
    clipboard = 'plain${o}text';
    await c.paste();
    expect(c.text.endsWith('plaintext'), isTrue);
  });

  test('an attachment goes on a line of its own', () {
    final c = NoteEditorController(text: NoteText.plain('before after'));
    caret(c, 6);
    c.insertAttachment('cake.png');
    expect(c.text, 'before\n$o\n after');
    expect(c.doc.attachments, ['cake.png']);
    expect(styles(c), [ParaStyle.body, ParaStyle.body, ParaStyle.body]);
  });
}
