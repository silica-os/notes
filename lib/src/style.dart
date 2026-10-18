// Geometry and colours of the Notes window, in one place. Layout and colours come from the
// Amalfi kit (`App · Notes`, masters `Apps/Notes/*`) and the design system's
// `components.md`; values the kit does not give are marked provisional.

import 'package:flutter/widgets.dart';
import 'package:silica_ui/silica_ui.dart';

/// Geometry (pt).
abstract final class NotesMetrics {
  /// The kit draws the window at 1120 × 720: sidebar 240, list 300, editor 580.
  static const Size defaultWindow = Size(1120, 720);

  /// PROVISIONAL: the smallest window: the list and an editor wide enough for its toolbar.
  static const Size minimumWindow = Size(760, 360);

  static const double toolbar = AmalfiToolbarMetrics.toolbarHeight;
  static const double sidebarWidth = AmalfiWindowMetrics.sidebarWidth;
  static const double listWidth = 300;

  /// Below this editor width the toolbar's search field becomes a button.
  static const double searchFieldMinEditor = 560;

  // List (kit `Apps/Notes/List Row/*`, 300 × 72; `List Header`, 300 × 28).
  static const double listRow = 72;
  static const double listHeader = 28;
  static const double listHeaderTop = 8;
  static const double selectionInsetX = 8;
  static const double selectionInsetY = 4;
  static const double selectionRadius = 8;
  static const double rowTextX = 20;
  static const double rowTitleY = 12;
  static const double rowDetailY = 36;
  static const double rowDateWidth = 76;
  static const double rowPreviewX = 100;

  // Gallery (kit `Apps/Notes/Gallery`, cards 256 × 200, 24 apart).
  static const double cardWidth = 256;
  static const double cardHeight = 200;
  static const double cardGap = 24;
  static const double cardRadius = 14;
  static const double cardPadding = 16;

  // Editor (kit `Apps/Notes/Editor`, 580 × 668).
  static const double editorPaddingX = 40;
  static const double editorDateTop = 20;
  static const double editorTitleGap = 16;
  static const double editorPaddingBottom = 40;

  /// Line heights: the kit's text boxes plus the space it leaves around them (title 32 + 12,
  /// heading 22 + 18, list items 28 apart, checklist items 36 apart).
  static const double titleLine = 44;
  static const double headingLine = 40;
  static const double subheadingLine = 32;
  static const double listLine = 28;
  static const double checklistLine = 36;
  static const double listMarker = 24;
  static const double checklistMarker = 28;
  static const double listIndent = 24;
  static const double bullet = 4;
  static const double bulletX = 8;
  static const double pictureRadius = 12;
  static const double chipRadius = 8;

  /// PROVISIONAL: the tallest a picture in a note is drawn.
  static const double imageMaxHeight = 480;

  /// Empty states: the glyph 32, the text 12 under it.
  static const double emptyGlyph = 32;

  /// How long typing waits before the note is written.
  static const Duration saveDelay = Duration(milliseconds: 800);
}

/// The colours of the window, from the Amalfi tokens of the current appearance.
@immutable
class NotesColors {
  const NotesColors._(this._c);

  final AmalfiColors _c;

  factory NotesColors.of(BuildContext context) =>
      NotesColors._(AmalfiTheme.of(context).colors);

  Color get sidebar => _c.surfaceSidebar;
  Color get window => _c.surfaceWindow;
  Color get card => _c.surfaceRaised;
  Color get text => _c.textPrimary;
  Color get secondary => _c.textSecondary;
  Color get tertiary => _c.textTertiary;
  Color get separator => _c.lineSeparator;
  Color get border => _c.lineBorder;
  Color get accent => _c.accentAmalfi;
  Color get accentSoft => _c.accentAmalfiSoft;
  Color get onAccent => _c.textOnAccent;

  /// The selected row of an inactive window.
  // Assumption: not measured (the kit draws only the active window): a neutral capsule.
  Color get inactiveSelection => _c.lineBorder;

  /// Folder glyphs (`components.md`: Notes folders are `Palette/Limone Scuro`).
  Color get folderGlyph => _c.paletteLimoneScuro;

  /// Smart folder glyphs: `Accent/Amalfi`.
  Color get smartGlyph => _c.accentAmalfi;

  /// Search matches in the text (kit `Apps/Notes/Search` › Match highlight).
  Color get searchHighlight => _c.accentAmalfiSoft;

  Color get destructive => _c.paletteTerracotta;

  /// The dot of a tag: one of the palette colours, the same for the same tag.
  Color tag(String name) {
    final palette = [
      _c.paletteLimone,
      _c.paletteMare,
      _c.paletteTerracotta,
      _c.paletteUlivo,
      _c.paletteLavanda,
      _c.paletteArancia,
      _c.paletteBouganville,
    ];
    var h = 0;
    for (final c in name.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return palette[h % palette.length];
  }
}
