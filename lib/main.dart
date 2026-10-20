import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  runApp(HeadroomApp(store: store, tidier: tidier, listSettings: listSettings));
}

class HeadroomApp extends StatelessWidget {
  const HeadroomApp({
    super.key,
    required this.store,
    required this.tidier,
    required this.listSettings,
  });

  final ThoughtStore store;
  final Tidier tidier;
  final ListSettings listSettings;

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
      ),
    );
  }
}
