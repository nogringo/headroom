import 'package:flutter/material.dart';

import 'ai_settings_section.dart';
import 'backup.dart';
import 'backup_section.dart';
import 'l10n/app_localizations.dart';
import 'tidier.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.tidier, required this.backup});

  final Tidier tidier;
  final Backup backup;

  /// Closed with Escape too.
  static Route<void> route({required Tidier tidier, required Backup backup}) =>
      MaterialPageRoute(
        barrierDismissible: true,
        builder: (_) => SettingsPage(tidier: tidier, backup: backup),
      );

  @override
  Widget build(BuildContext context) {
    final appTheme = Theme.of(context);
    // Settings are the app's own words, not handwritten like thoughts.
    final theme = appTheme.copyWith(
      textTheme: appTheme.textTheme.copyWith(
        bodyLarge: appTheme.textTheme.bodyMedium?.copyWith(fontSize: 16),
      ),
    );
    final l10n = AppLocalizations.of(context);

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        header: true,
        child: Text(text, style: theme.textTheme.titleSmall),
      ),
    );

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.settings)),
        body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            32 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  heading(l10n.tidySettings),
                  AiSettingsSection(tidier: tidier),
                  const SizedBox(height: 40),
                  heading(l10n.backup),
                  BackupSection(backup: backup),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
