# Note storage

Notes keeps every note as a file under `$XDG_DATA_HOME/notes` (`~/.local/share/notes` by
default). Nothing else is needed to read them back: the files are plain UTF-8 text in a
line-oriented subset of Markdown, readable in any text editor.

## Layout

| Path | What |
| --- | --- |
| `<root>/<id>.md` | a note in the default folder ("Notes") |
| `<root>/<Folder>/<id>.md` | a note in a folder of the user (one level of folders) |
| `<root>/.trash/<id>.md` | a note in Recently Deleted; removed after 30 days |
| `<root>/.attachments/<id>/<name>` | the files attached to note `<id>` |

`<id>` is a unique name made from the creation time and a random part; it never changes, so
renaming or moving a note never breaks its attachments. Files are written to `<file>.new` and
renamed over the old one, so a note is never half written.

## File

A file starts with a header in an HTML comment, then the text:

```
<!-- silica-notes
created: 2026-10-16T08:22:00.000Z
modified: 2026-10-16T08:31:12.000Z
pinned: yes
-->
# Lemon cake
A soft cake for **Sunday**.
```

Header keys (all optional; a file without header takes its modification time):

| Key | Value |
| --- | --- |
| `created`, `modified` | ISO 8601 times, UTC |
| `pinned` | `yes` when the note is pinned |
| `folder` | in Recently Deleted: the folder the note came from (empty: the default folder) |
| `deleted` | in Recently Deleted: when it was deleted |

## Text

One line of the file is one paragraph of the note.

| Paragraph | Written as |
| --- | --- |
| Title, Heading, Subheading | `# text`, `## text`, `### text` |
| Body | `text` (a backslash first when it would read as another style: `\# not a title`) |
| Bulleted, dashed, numbered list | `- text`, `+ text`, `1. text` |
| Checklist | `- [ ] text`, `- [x] text` |
| List indentation | two spaces per level before the marker |
| Monostyled | lines between two ```` ``` ```` fences, kept as they are |

Inline styles: `**bold**`, `*italic*`, `<u>underline</u>`, `~~strikethrough~~`. The characters
`\ * ~ < [ ] _` and the backtick are escaped with a backslash. An attachment is
`![name](attachments/name)` (the name percent-encoded in the link), resolved against
`<root>/.attachments/<id>/`.

Tags are words written as `#tag` anywhere in the text.

Lines Notes does not know (other Markdown) are kept as body text.
