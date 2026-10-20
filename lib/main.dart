import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'backup.dart';
import 'capture_screen.dart';
import 'file_thought_storage.dart'
    if (dart.library.js_interop) 'web_thought_storage.dart';
import 'l10n/app_localizations.dart';
import 'list_settings.dart';
import 'theme.dart';
import 'thought_store.dart';
import 'tidier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Headroom's own menus replace the browser's, fields included.
  if (kIsWeb) await BrowserContextMenu.disableContextMenu();
  final storage = await openThoughtStorage();
  final store = ThoughtStore(storage);
  await store.load();
  final tidier = Tidier(store, storage);
  await tidier.load();
  final listSettings = ListSettings(storage);
  await listSettings.load();
  final backup = Backup(store, tidier, listSettings, storage);
  await backup.load();
  runApp(
    HeadroomApp(
      store: store,
      tidier: tidier,
      listSettings: listSettings,
      backup: backup,
    ),
  );
  // Otherwise screen readers see nothing until they find Flutter's hidden
  // "Enable accessibility" button.
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics();
}

class HeadroomApp extends StatelessWidget {
  const HeadroomApp({
    super.key,
    required this.store,
    required this.tidier,
    required this.listSettings,
    required this.backup,
  });

  final ThoughtStore store;
  final Tidier tidier;
  final ListSettings listSettings;
  final Backup backup;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Headroom',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CaptureScreen(
        store: store,
        tidier: tidier,
        listSettings: listSettings,
        backup: backup,
      ),
    );
  }
}
