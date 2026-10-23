import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'backup.dart';
import 'day_label.dart';
import 'l10n/app_localizations.dart';
import 'report_error.dart';

class BackupSection extends StatefulWidget {
  const BackupSection({super.key, required this.backup});

  final Backup backup;

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
  var _busy = false;

  /// What the last restore came to, or why a save or restore failed.
  ({String message, bool failed})? _outcome;

  Future<void> _save() => _run((l10n) async {
    final bytes = await widget.backup.create();
    final saved = await FilePicker.saveFile(
      fileName: Backup.fileName(DateTime.now()),
      bytes: bytes,
      mimeType: 'application/zip',
    );
    // The date of the last copy shows it went through.
    if (saved != null) await widget.backup.saved();
    return null;
  }, failure: (l10n) => l10n.backupNotSaved);

  Future<void> _restore() => _run((l10n) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (file == null) return null;
    try {
      final restored = await widget.backup.restore(await file.readAsBytes());
      return (
        message: [
          l10n.restored(restored.thoughts),
          if (restored.ai) l10n.aiRestored,
        ].join(' '),
        failed: false,
      );
    } on FormatException {
      return (message: l10n.notABackup, failed: true);
    }
  }, failure: (l10n) => l10n.restoreFailed);

  Future<void> _run(
    Future<({String message, bool failed})?> Function(AppLocalizations) task, {
    required String Function(AppLocalizations) failure,
  }) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _outcome = null;
    });
    ({String message, bool failed})? outcome;
    try {
      outcome = await task(l10n);
    } catch (error, stack) {
      reportError(error, stack);
      outcome = (message: failure(l10n), failed: true);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _outcome = outcome;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final savedAt = widget.backup.savedAt;
    final outcome = _outcome;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.backupIntro, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Text(
          savedAt == null
              ? l10n.noBackupYet
              : l10n.lastBackup(daysBetween(savedAt, DateTime.now())),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(l10n.saveBackup),
            ),
            OutlinedButton(
              onPressed: _busy ? null : _restore,
              child: Text(l10n.restoreBackup),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(l10n.restoreHelp, style: theme.textTheme.bodySmall),
        if (_busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ] else if (outcome != null) ...[
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(
              outcome.message,
              style: outcome.failed
                  ? theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    )
                  : theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ],
    );
  }
}
