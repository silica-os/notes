// Notes, the notes app of Silica.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:silica_ui/silica_ui.dart';

import 'src/app.dart';
import 'src/model/store.dart';
import 'src/portal.dart';
import 'src/settings.dart';
import 'src/style.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  // The toolbar is unified with the window: Ossido draws only the window buttons.
  SilicaWindow.setFullSizeContent(NotesMetrics.toolbar).ignore();
  SilicaWindow.setSizeLimits(min: NotesMetrics.minimumWindow).ignore();
  // Notes keeps running when its window closes; a reopen builds the window again (APP-LC).
  SilicaApp.quitWhenLastWindowCloses = false;
  final env = Platform.environment;
  final store = NotesStore.forUser(env)..load();
  runApp(
    NotesApp(
      store: store,
      settings: NotesSettings.forUser(env),
      dialogs: PortalFileDialogs(),
    ),
  );
}
