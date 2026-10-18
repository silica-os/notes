// The app: the language (English, Italian), the active window state, and the lifecycle.
// Closing the window keeps Notes running without windows, as on the reference; a reopen (the
// Dock, the Launcher) builds the window again on the notes as they are.

import 'dart:async';
import 'dart:ui' show AppExitResponse, Locale, PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:silica_ui/silica_ui.dart';

import '../l10n/app_localizations.dart';
import 'model/store.dart';
import 'portal.dart';
import 'settings.dart';
import 'style.dart';
import 'window.dart';

/// The system languages resolved against ours, English when none matches.
Locale resolveLocale(List<Locale> preferred) =>
    basicLocaleListResolution(preferred, AppLocalizations.supportedLocales);

class NotesApp extends StatefulWidget {
  const NotesApp({
    super.key,
    required this.store,
    required this.settings,
    required this.dialogs,
    this.locale,
    this.windowKey,
  });

  final NotesStore store;
  final NotesSettings settings;
  final FileDialogs dialogs;

  /// A fixed language (tests); null follows the system.
  final Locale? locale;

  /// The window's key (tests).
  final GlobalKey<NotesWindowState>? windowKey;

  @override
  State<NotesApp> createState() => _NotesAppState();
}

class _NotesAppState extends State<NotesApp> with WidgetsBindingObserver {
  late Locale _locale =
      widget.locale ?? resolveLocale(PlatformDispatcher.instance.locales);
  bool _active = _isActive(WidgetsBinding.instance.lifecycleState);
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onStateChange: (state) => setState(() => _active = _isActive(state)),
    onInactive: _flush,
    onHide: _flush,
    onExitRequested: () async {
      _flush();
      return AppExitResponse.exit;
    },
  );
  late final GlobalKey<NotesWindowState> _window =
      widget.windowKey ?? GlobalKey<NotesWindowState>();

  static bool _isActive(AppLifecycleState? s) =>
      s == null || s == AppLifecycleState.resumed;

  void _flush() => _window.currentState?.flush();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycle;
    // Dates in the list and the editor, in every language.
    unawaited(initializeDateFormatting());
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (widget.locale != null || locales == null) return;
    setState(() => _locale = resolveLocale(locales));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Localizations(
    locale: _locale,
    delegates: const [
      AppLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    child: DefaultTextEditingShortcuts(
      child: ScrollConfiguration(
        behavior: const SilicaScrollBehavior(),
        child: AmalfiTheme(
          child: Builder(
            builder: (context) => ColoredBox(
              color: NotesColors.of(context).window,
              child: Overlay(
                initialEntries: [
                  OverlayEntry(
                    builder: (context) => SilicaAppWindow(
                      onReopen: () async => widget.store.load(),
                      builder: (context) => NotesWindow(
                        key: _window,
                        store: widget.store,
                        settings: widget.settings,
                        dialogs: widget.dialogs,
                        active: _active,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
