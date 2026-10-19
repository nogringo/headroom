import 'package:flutter/material.dart';

import 'capture_screen.dart';
import 'file_thought_storage.dart'
    if (dart.library.js_interop) 'web_thought_storage.dart';
import 'l10n/app_localizations.dart';
import 'theme.dart';
import 'thought_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = ThoughtStore(await openThoughtStorage());
  await store.load();
  runApp(HeadroomApp(store: store));
}

class HeadroomApp extends StatelessWidget {
  const HeadroomApp({super.key, required this.store});

  final ThoughtStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Headroom',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CaptureScreen(store: store),
    );
  }
}
