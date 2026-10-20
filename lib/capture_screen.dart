import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'ai_settings_dialog.dart';
import 'backup.dart';
import 'backup_dialog.dart';
import 'clipboard_image_io.dart'
    if (dart.library.js_interop) 'clipboard_image_web.dart';
import 'day_label.dart';
import 'focus_ring.dart';
import 'image_paste.dart';
import 'l10n/app_localizations.dart';
import 'list_settings.dart';
import 'report_error.dart';
import 'sidebar.dart';
import 'theme.dart';
import 'theme_name_dialog.dart';
import 'theme_names.dart';
import 'thought.dart';
import 'thought_store.dart';
import 'tidier.dart';
import 'tidy_client.dart';

const _contentWidth = 640.0;

/// From the window's edge to the note and to the thoughts.
const _gutter = 12.0;

/// From the note's edge to its text, which the thoughts line up with.
const _inset = 20.0;

/// From this window width, Material's expanded class, the sidebar stays open
/// beside the list rather than in a drawer.
const _wideWidth = 840.0;

const _sidebarWidth = 240.0;

/// A heading for [day] when [thought] is null, else a thought noted that day.
typedef _Row = ({DateTime day, Thought? thought});

String _imageLabel(AppLocalizations l10n, int index, int count) =>
    count == 1 ? l10n.imageLabel : l10n.imagePosition(index + 1, count);

List<_Row> _rowsOf(Iterable<Thought> thoughts, {required bool withHeadings}) {
  final rows = <_Row>[];
  DateTime? previous;
  for (final thought in thoughts) {
    final day = DateUtils.dateOnly(thought.createdAt);
    if (withHeadings && day != previous) rows.add((day: day, thought: null));
    rows.add((day: day, thought: thought));
    previous = day;
  }
  return rows;
}

Object _keyOf(_Row row) => row.thought?.id ?? row.day;

/// Touch keyboards have a single key, kept for sending. On the web, the
/// platform is the browser's OS.
bool _shiftEnterBreaksLine(TargetPlatform platform) => switch (platform) {
  TargetPlatform.macOS ||
  TargetPlatform.windows ||
  TargetPlatform.linux => true,
  _ => false,
};

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
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
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  var _listKey = GlobalKey<SliverAnimatedListState>();
  final _scaffold = GlobalKey<ScaffoldState>();
  final _scroll = ScrollController();
  late final AppLifecycleListener _lifecycle;
  late final Timer _clock;

  /// The images pasted into the field, waiting to be sent.
  var _attachments = <PastedImage>[];

  /// Thoughts noted or edited in the open theme, kept in it until the AI
  /// gives them theirs.
  final _notedHere = <String>{};

  /// What the list shows, kept in step with the store by [_syncRows].
  late var _rows = _currentRows();

  /// Set while the thought swiped away is being removed.
  String? _swipedId;

  ThoughtStore get _store => widget.store;
  Tidier get _tidier => widget.tidier;
  ListSettings get _listSettings => widget.listSettings;

  /// Null for every thought, '' for those without a theme.
  String? get _theme => _listSettings.theme;

  List<_Row> _currentRows() {
    final theme = _theme;
    return _rowsOf(
      theme == null
          ? _store.thoughts
          : _store.thoughts.where(
              (t) =>
                  (t.theme ?? '') == theme ||
                  (t.theme == null && _notedHere.contains(t.id)),
            ),
      withHeadings: theme == null,
    );
  }

  /// The themes the sidebar opens, in the person's order, then '' for the
  /// thoughts that will get none. Empty when there is no sidebar.
  List<String> _sidebarThemes() {
    final theme = _theme;
    final themes = {for (final t in _store.thoughts) ?t.theme, ?theme};
    if (themes.isEmpty) return const [];
    final noThemeOpen = themes.remove('');
    return [
      ...orderedThemes(themes, _listSettings.themeOrder),
      // Not for the thoughts the AI is about to sort, which would flicker.
      if (noThemeOpen ||
          _store.thoughts.any((t) => t.theme == null && !_tidier.willSort(t)))
        '',
    ];
  }

  Duration get _motion => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 280);

  @override
  void initState() {
    super.initState();
    // Reopening the app from the background should land in the field, like a cold start.
    _lifecycle = AppLifecycleListener(onResume: _refocus);
    // Turns "Today" into "Yesterday" at midnight.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
    _store.addListener(_syncRows);
    // Global rather than Shortcuts: a click elsewhere leaves the focus above
    // this screen, out of their reach.
    HardwareKeyboard.instance.addHandler(_onKey);
    final theme = _theme;
    if (theme != null &&
        !_store.thoughts.any((t) => (t.theme ?? '') == theme)) {
      _listSettings.theme = null;
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _store.removeListener(_syncRows);
    _clock.cancel();
    _lifecycle.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    _input.dispose();
    super.dispose();
  }

  void _refocus() {
    if (ModalRoute.of(context)?.isCurrent ?? true) _inputFocus.requestFocus();
  }

  /// Cmd+N (Ctrl+N off Apple devices), or "/" outside the field, goes back
  /// to it. Browsers keep Cmd+N and Ctrl+N for themselves.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    final command = switch (Theme.of(context).platform) {
      TargetPlatform.macOS || TargetPlatform.iOS => keyboard.isMetaPressed,
      _ => keyboard.isControlPressed,
    };
    final newThought = event.logicalKey == LogicalKeyboardKey.keyN && command;
    final slash =
        event.character == '/' &&
        !_inputFocus.hasFocus &&
        !keyboard.isMetaPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed;
    if (!newThought && !slash) return false;
    _scaffold.currentState?.closeDrawer();
    _inputFocus.requestFocus();
    return true;
  }

  void _capture() {
    final images = [for (final pasted in _attachments) pasted.name];
    final thought = _store.add(_input.text, images: images);
    if (thought == null) return;
    // Its id is only known now, after the store has told the list.
    _notedHere.add(thought.id);
    _syncRows();
    _input.clear();
    setState(() => _attachments = []);
    _inputFocus.requestFocus();
    if (_scroll.hasClients && _scroll.offset > 0) {
      if (_motion == Duration.zero) {
        _scroll.jumpTo(0);
      } else {
        _scroll.animateTo(0, duration: _motion, curve: Curves.easeOutCubic);
      }
    }
    HapticFeedback.lightImpact();
    if (MediaQuery.supportsAnnounceOf(context)) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        AppLocalizations.of(context).thoughtNoted,
        Directionality.of(context),
      );
    }
  }

  void _showError(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _copyImage(String name) async {
    try {
      // No await before this call: on the web it must run inside the click.
      await copyImage(_store.readImage(name));
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) _showError(AppLocalizations.of(context).imageNotCopied);
    }
  }

  /// Animates the list from the rows it shows to the store's: thoughts and
  /// headings that appear grow in, those that go away collapse.
  void _syncRows() {
    final from = _rows;
    final to = _rows = _currentRows();
    final list = _listKey.currentState;
    if (list == null) return;
    final kept = {for (final row in to) _keyOf(row)};
    var i = 0;
    var j = 0;
    var at = 0;
    while (i < from.length || j < to.length) {
      final before = i < from.length ? _keyOf(from[i]) : null;
      final after = j < to.length ? _keyOf(to[j]) : null;
      if (before != null && before == after) {
        i++;
        j++;
        at++;
      } else if (before != null && (after == null || !kept.contains(before))) {
        final removed = from[i++];
        // A swiped tile has already slid away. Any other row collapses.
        final swiped = removed.thought?.id == _swipedId;
        list.removeItem(
          at,
          (_, animation) => swiped
              ? const SizedBox.shrink()
              : IgnorePointer(child: _buildRow(removed, animation)),
          duration: swiped ? Duration.zero : _motion,
        );
      } else {
        list.insertItem(at++, duration: _motion);
        j++;
      }
    }
  }

  void _remove(Thought thought, {bool swiped = false}) {
    _swipedId = swiped ? thought.id : null;
    final index = _store.remove(thought.id);
    _swipedId = null;
    if (index == -1) return;
    _offerUndo(
      AppLocalizations.of(context).thoughtDeleted,
      () => _store.restore(thought, index),
    );
  }

  void _merge(Merge suggestion) {
    final merged = _store.merge(suggestion.ids, suggestion.text);
    if (merged == null) return;
    _offerUndo(
      AppLocalizations.of(context).thoughtsMerged,
      () => _store.unmerge(merged),
    );
  }

  void _offerUndo(String message, VoidCallback undo) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          // A screen reader takes longer than the timeout to reach Undo.
          persist: MediaQuery.accessibleNavigationOf(context),
          action: SnackBarAction(
            label: AppLocalizations.of(context).undo,
            onPressed: () {
              if (mounted) undo();
            },
          ),
        ),
      );
  }

  /// Lists every thought when [theme] is null, else that theme's.
  void _open(String? theme) {
    _scaffold.currentState?.closeDrawer();
    if (theme == _theme) return;
    setState(() {
      _listSettings.theme = theme;
      _notedHere.clear();
      _rows = _currentRows();
      // A fresh list, rather than every row sliding to its new place.
      _listKey = GlobalKey();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _openTidySettings() {
    _scaffold.currentState?.closeDrawer();
    showDialog<void>(
      context: context,
      builder: (_) => AiSettingsDialog(tidier: _tidier),
    );
  }

  void _openBackup() {
    _scaffold.currentState?.closeDrawer();
    showDialog<void>(
      context: context,
      builder: (_) => BackupDialog(backup: widget.backup),
    );
  }

  Future<void> _edit(Thought thought) async {
    final edit = await showDialog<_Edit>(
      context: context,
      builder: (_) => _EditDialog(
        store: _store,
        thought: thought,
        themes: _themes(),
        aiSorts: _tidier.settings != null,
        onDelete: () => _remove(thought),
      ),
    );
    if (edit == null) return;
    // New text drops the theme, which would take it out of this one.
    _notedHere.add(thought.id);
    _store.update(thought.id, text: edit.text, images: edit.images);
    if (edit.theme != thought.theme ||
        edit.themeChosen != thought.themeChosen) {
      _store.chooseTheme(thought.id, edit.themeChosen ? edit.theme : null);
    }
  }

  List<String> _themes() => orderedThemes({
    for (final t in _store.thoughts) ?t.theme,
  }, _listSettings.themeOrder);

  /// Renames the open [theme], which joins another when it takes its name.
  Future<void> _renameTheme(String theme) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => ThemeNameDialog(themes: _themes(), renaming: theme),
    );
    if (name == null || name == theme) return;
    // Before the store tells the list, which then keeps the same thoughts.
    _listSettings
      ..theme = name
      ..renameTheme(theme, name);
    _store.renameTheme(theme, name);
  }

  void _view(List<String> names, int index) => showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    useSafeArea: false,
    builder: (_) =>
        _ImageViewer(store: _store, names: names, initialIndex: index),
  );

  List<ImageProvider> _imagesOf(Thought thought) => [
    for (final name in thought.images) _store.imageNamed(name),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final inputStyle = theme.textTheme.displaySmall?.copyWith(
      color: scheme.onPrimaryContainer,
    );
    final attachments = _attachments;
    final shiftEnter = _shiftEnterBreaksLine(theme.platform);

    return ListenableBuilder(
      listenable: Listenable.merge([_store, _tidier, _listSettings]),
      builder: (context, note) => _buildLayout(context, note!),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _contentWidth),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(_gutter, _gutter, _gutter, 8),
            child: _Note(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: ImagePaste(
                          store: _store,
                          focusNode: _inputFocus,
                          onImage: (image) {
                            if (_attachments.any(
                              (pasted) => pasted.name == image.name,
                            )) {
                              _showError(l10n.imageAlreadyAdded);
                            } else {
                              setState(
                                () => _attachments = [..._attachments, image],
                              );
                            }
                          },
                          onError: _showError,
                          builder: (contextMenuBuilder) => _SubmitOnEnter(
                            controller: _input,
                            onSubmit: _capture,
                            // The hint goes away once there is text.
                            child: Semantics(
                              label: l10n.thoughtField,
                              child: TextField(
                                controller: _input,
                                focusNode: _inputFocus,
                                autofocus: true,
                                minLines: 1,
                                maxLines: 5,
                                keyboardType: shiftEnter
                                    ? TextInputType.multiline
                                    : TextInputType.text,
                                textInputAction: shiftEnter
                                    ? TextInputAction.newline
                                    : TextInputAction.send,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                onEditingComplete: _capture,
                                contextMenuBuilder: contextMenuBuilder,
                                style: inputStyle,
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  hintText: l10n.captureHint,
                                  // The French hint wraps; short text should not keep its two lines.
                                  maintainHintSize: false,
                                  hintStyle: inputStyle?.copyWith(
                                    color: scheme.onPrimaryContainer.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ValueListenableBuilder(
                        valueListenable: _input,
                        builder: (context, value, _) => IconButton.filled(
                          style: IconButton.styleFrom(
                            disabledBackgroundColor: scheme.onPrimaryContainer
                                .withValues(alpha: 0.08),
                            disabledForegroundColor: scheme.onPrimaryContainer
                                .withValues(alpha: 0.4),
                          ),
                          tooltip: l10n.captureButton,
                          onPressed:
                              value.text.trim().isEmpty && attachments.isEmpty
                              ? null
                              : _capture,
                          icon: const Icon(Icons.arrow_upward_rounded),
                        ),
                      ),
                    ],
                  ),
                  if (attachments.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _AttachmentsPreview(
                        images: attachments,
                        onRemove: (removed) => setState(
                          () => _attachments = [
                            for (final pasted in _attachments)
                              if (pasted != removed) pasted,
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Once a thought has a theme, the sidebar sits beside [note] and the list
  /// on a wide window, else in a drawer.
  Widget _buildLayout(BuildContext context, Widget note) {
    final themes = _sidebarThemes();
    final wide = MediaQuery.sizeOf(context).width >= _wideWidth;
    final sidebar = themes.isEmpty
        ? null
        : Sidebar(
            themes: themes,
            selected: _theme,
            onSelect: _open,
            onRename: _renameTheme,
            onReorder: (order) => _listSettings.themeOrder = order,
            onBackup: _openBackup,
            tidying: _tidier.working,
            onTidySettings: _openTidySettings,
          );
    return Scaffold(
      key: _scaffold,
      drawer: sidebar == null || wide
          ? null
          : Drawer(
              width: 280,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadiusDirectional.horizontal(
                  end: Radius.circular(6),
                ),
              ),
              child: SafeArea(bottom: false, child: sidebar),
            ),
      body: SafeArea(
        bottom: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sidebar != null && wide)
              Container(
                width: _sidebarWidth,
                decoration: BoxDecoration(
                  border: BorderDirectional(
                    end: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                child: sidebar,
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Up to three quarters of the height, past which large
                    // text with the keyboard up scrolls rather than hiding
                    // the list.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight * 0.75,
                      ),
                      child: SingleChildScrollView(
                        primary: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            note,
                            if (sidebar == null || !wide)
                              _buildToolbar(context, drawer: sidebar != null),
                          ],
                        ),
                      ),
                    ),
                    Expanded(child: _buildList(context)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the drawer, or the backup and the AI's settings while there is no
  /// sidebar.
  Widget _buildToolbar(BuildContext context, {required bool drawer}) {
    final l10n = AppLocalizations.of(context);
    final tidier = _tidier;
    final theme = _theme;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _contentWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _gutter),
          child: Row(
            children: [
              if (drawer)
                Flexible(
                  child: Tooltip(
                    message: MaterialLocalizations.of(context)
                        .openAppDrawerTooltip,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context)
                            .colorScheme
                            .onSurface,
                      ),
                      onPressed: () => _scaffold.currentState?.openDrawer(),
                      icon: const Icon(Icons.menu_rounded),
                      label: Text(
                        switch (theme) {
                          null => l10n.allThoughts,
                          '' => l10n.noTheme,
                          _ => theme,
                        },
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                )
              else ...[
                const Spacer(),
                IconButton(
                  tooltip: l10n.backup,
                  onPressed: _openBackup,
                  icon: const Icon(Icons.backup_outlined),
                ),
                IconButton(
                  tooltip: tidier.working ? l10n.tidying : l10n.tidySettings,
                  onPressed: _openTidySettings,
                  icon: tidier.working
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cleaning_services_outlined),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final shown = {
      for (final row in _rows)
        if (row.thought case final thought?) thought.id,
    };
    final suggestions = [
      for (final s in _tidier.suggestions)
        if (s.ids.any(shown.contains)) s,
    ];
    final suggestion = suggestions.firstOrNull;
    final tidyFailure = switch (_tidier.failure) {
      null => null,
      TidyFailure.unreachable => l10n.tidyUnreachable,
      TidyFailure.rejectedKey => l10n.tidyRejectedKey,
      TidyFailure.notFound => l10n.tidyNotFound,
      TidyFailure.limited => l10n.tidyLimited,
      TidyFailure.failed => l10n.tidyFailed,
    };
    final errorStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.error,
    );

    // The list spans the window so its scrollbar sits at the edge and the
    // margins scroll too. Its content keeps to the note's centered column.
    return LayoutBuilder(
      builder: (context, constraints) {
        final side =
            math.max(0.0, (constraints.maxWidth - _contentWidth) / 2) + _gutter;
        final inset = EdgeInsets.symmetric(horizontal: side + _inset);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_store.saveFailed)
              Padding(
                padding: inset.copyWith(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(l10n.saveFailed, style: errorStyle),
                ),
              ),
            if (tidyFailure != null)
              Padding(
                padding: inset.copyWith(top: 4, right: side),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tidyFailure, style: errorStyle),
                            if (_tidier.failureMessage case final message?)
                              Text(
                                message,
                                style: theme.textTheme.bodySmall,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _tidier.retry,
                      child: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_store.thoughts.isEmpty)
                    Padding(
                      padding: inset.copyWith(top: 24),
                      child: Text(
                        l10n.emptyList,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  CustomScrollView(
                    controller: _scroll,
                    slivers: [
                      if (suggestion != null)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(side, 12, side, 0),
                          sliver: SliverToBoxAdapter(
                            child: _CleanUpCard(
                              suggestion: suggestion,
                              count: suggestions.length,
                              thoughts: {
                                for (final t in _store.thoughts) t.id: t,
                              },
                              onAccept: () => switch (suggestion) {
                                final Merge merge => _merge(merge),
                                Outdated(:final id) => _remove(
                                  _store.thoughts.firstWhere((t) => t.id == id),
                                ),
                              },
                              onDecline: () => _tidier.decline(suggestion),
                            ),
                          ),
                        ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          side,
                          0,
                          side,
                          24 + MediaQuery.paddingOf(context).bottom,
                        ),
                        sliver: SliverAnimatedList(
                          key: _listKey,
                          initialItemCount: _rows.length,
                          itemBuilder: (context, index, animation) =>
                              _buildRow(_rows[index], animation),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRow(_Row row, Animation<double> animation) {
    final eased = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    final thought = row.thought;
    return SizeTransition(
      sizeFactor: eased,
      child: FadeTransition(
        opacity: eased,
        child: thought == null
            ? _Heading(day: row.day)
            : _buildThought(thought),
      ),
    );
  }

  Widget _buildThought(Thought thought) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: l10n.delete): () => _remove(thought),
      },
      child: ClipRRect(
        borderRadius: paperRadius,
        child: Dismissible(
          key: ValueKey(thought.id),
          background: const _SwipeBackground(
            alignment: AlignmentDirectional.centerStart,
          ),
          secondaryBackground: const _SwipeBackground(
            alignment: AlignmentDirectional.centerEnd,
          ),
          onDismissed: (_) => _remove(thought, swiped: true),
          child: _ThoughtTile(
            text: thought.text,
            images: _imagesOf(thought),
            createdAt: thought.createdAt,
            withDay: _theme != null,
            themeButton: switch (thought.theme) {
              final theme? when _theme == null => _ThemeMenu(
                theme: theme,
                chosen: thought.themeChosen,
                themes: _themes(),
                aiSorts: _tidier.settings != null,
                onChoose: (theme) => _store.chooseTheme(thought.id, theme),
                // Else the tooltip ends up on the thought rather than here.
                builder: (context, toggle) => MergeSemantics(
                  child: Tooltip(
                    message: l10n.changeTheme,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                        textStyle: Theme.of(context).textTheme.bodySmall,
                        // Lines the label up with the text above.
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: toggle,
                      icon: const Icon(Icons.label_outline_rounded, size: 14),
                      label: Text(theme),
                    ),
                  ),
                ),
              ),
              _ => null,
            },
            onTap: () => _edit(thought),
            onImageTap: (index) => _view(thought.images, index),
            onImageCopy: (index) => _copyImage(thought.images[index]),
            onDelete: () => _remove(thought),
          ),
        ),
      ),
    );
  }
}

/// The sticky note that thoughts are written on.
class _Note extends StatelessWidget {
  const _Note({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.primaryContainer,
    borderRadius: paperRadius,
    child: Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(_inset, 14, 12, 12),
      child: child,
    ),
  );
}

/// Names the day the thoughts below it were noted.
class _Heading extends StatelessWidget {
  const _Heading({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(_inset, 24, _inset, 0),
    child: Semantics(
      header: true,
      child: Text(
        dayLabel(day, DateTime.now(), AppLocalizations.of(context)),
        style: Theme.of(context).textTheme.titleSmall,
      ),
    ),
  );
}

/// Proposes the AI's first clean-up: merging thoughts, or deleting one that
/// looks out of date.
class _CleanUpCard extends StatelessWidget {
  const _CleanUpCard({
    required this.suggestion,
    required this.count,
    required this.thoughts,
    required this.onAccept,
    required this.onDecline,
  });

  final Suggestion suggestion;

  /// Of suggestions waiting, this one included.
  final int count;
  final Map<String, Thought> thoughts;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final quoted = theme.textTheme.bodyLarge?.copyWith(
      fontSize: 15,
      color: scheme.onSurfaceVariant,
    );
    final concerned = [for (final id in suggestion.ids) ?thoughts[id]];

    Widget quote(String text, TextStyle? style) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: style,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final (intro, keepLabel, acceptLabel) = switch (suggestion) {
      Merge() => (l10n.mergeIntro, l10n.keepApart, l10n.merge),
      Outdated() => (l10n.outdatedIntro, l10n.keep, l10n.delete),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: paperRadius,
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(_inset, 14, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.cleanUp,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: Text(
                    l10n.suggestionCount(count),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(intro, style: theme.textTheme.bodySmall),
            for (final thought in concerned)
              if (thought.text.isNotEmpty) quote(thought.text, quoted),
            if (suggestion case Merge(:final text)) ...[
              const SizedBox(height: 12),
              Text(l10n.mergeResult, style: theme.textTheme.bodySmall),
              quote(text, theme.textTheme.bodyLarge),
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onDecline, child: Text(keepLabel)),
                const SizedBox(width: 8),
                FilledButton(onPressed: onAccept, child: Text(acceptLabel)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ThoughtTile extends StatefulWidget {
  const _ThoughtTile({
    required this.text,
    required this.images,
    required this.createdAt,
    required this.withDay,
    required this.themeButton,
    required this.onTap,
    required this.onImageTap,
    required this.onImageCopy,
    required this.onDelete,
  });

  final String text;
  final List<ImageProvider> images;
  final DateTime createdAt;

  /// Shows the day it was noted rather than the time, unless that is today.
  final bool withDay;

  /// Under the text and images.
  final Widget? themeButton;
  final VoidCallback onTap;
  final ValueChanged<int> onImageTap;
  final ValueChanged<int> onImageCopy;
  final VoidCallback onDelete;

  @override
  State<_ThoughtTile> createState() => _ThoughtTileState();
}

class _ThoughtTileState extends State<_ThoughtTile> {
  var _hovered = false;
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = widget.text;
    final images = widget.images;
    final createdAt = widget.createdAt;
    final now = DateTime.now();
    final time = Text(
      widget.withDay && !DateUtils.isSameDay(createdAt, now)
          ? dayLabel(createdAt, now, AppLocalizations.of(context))
          : MaterialLocalizations.of(context).formatTimeOfDay(
              TimeOfDay.fromDateTime(createdAt),
              alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(
                context,
              ),
            ),
      style: theme.textTheme.bodySmall,
    );
    // Touch screens have the swipe. Where a pointer hovers, a button takes
    // the time's place on hover, or on keyboard focus.
    final deleteButton =
        kIsWeb ||
        switch (theme.platform) {
          TargetPlatform.macOS ||
          TargetPlatform.windows ||
          TargetPlatform.linux => true,
          _ => false,
        };
    final revealed = _hovered || _focused;
    const fade = Duration(milliseconds: 120);
    return FocusRing(
      // Opaque so the swipe background only shows where the tile has slid away.
      builder: (onFocusChange) => Material(
        color: theme.colorScheme.surface,
        borderRadius: paperRadius,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (focused) => setState(() => _focused = focused),
          child: InkWell(
            borderRadius: paperRadius,
            onTap: widget.onTap,
            onHover: (hovered) => setState(() => _hovered = hovered),
            onFocusChange: onFocusChange,
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                _inset,
                10,
                deleteButton ? 6 : _inset,
                10,
              ),
              child: Row(
                // The time sits on the first line of text, or at the top of an image.
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (text.isNotEmpty)
                          Text(text, style: theme.textTheme.bodyLarge),
                        if (images.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(
                              top: text.isEmpty ? 2 : 10,
                            ),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final (index, image) in images.indexed)
                                  _ImageThumbnail(
                                    image: image,
                                    label: _imageLabel(
                                      AppLocalizations.of(context),
                                      index,
                                      images.length,
                                    ),
                                    maxHeight: images.length == 1 ? 160 : 112,
                                    onTap: () => widget.onImageTap(index),
                                    onCopy: () => widget.onImageCopy(index),
                                  ),
                              ],
                            ),
                          ),
                        if (widget.themeButton case final themeButton?)
                          Padding(
                            padding: EdgeInsets.only(
                              top: images.isEmpty ? 2 : 8,
                            ),
                            child: themeButton,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (deleteButton)
                    Stack(
                      alignment: AlignmentDirectional.centerEnd,
                      children: [
                        AnimatedOpacity(
                          opacity: revealed ? 0 : 1,
                          duration: fade,
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(
                              end: _inset - 6,
                            ),
                            child: time,
                          ),
                        ),
                        // A touch screen has no hover: a touch on the hidden
                        // button opens the thought, as anywhere else on it.
                        _PointerGate(
                          open: revealed,
                          child: AnimatedOpacity(
                            opacity: revealed ? 1 : 0,
                            duration: fade,
                            alwaysIncludeSemantics: true,
                            child: IconButton(
                              constraints: const BoxConstraints.tightFor(
                                width: 32,
                                height: 28,
                              ),
                              padding: EdgeInsets.zero,
                              iconSize: 18,
                              tooltip: AppLocalizations.of(context).delete,
                              onPressed: widget.onDelete,
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    time,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets pointers through to what lies beneath while closed. Unlike
/// [IgnorePointer], it leaves a screen reader free to press its child.
class _PointerGate extends SingleChildRenderObjectWidget {
  const _PointerGate({required this.open, super.child});

  final bool open;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPointerGate(open);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPointerGate renderObject,
  ) => renderObject.open = open;
}

class _RenderPointerGate extends RenderProxyBox {
  _RenderPointerGate(this.open);

  bool open;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      open && super.hitTest(result, position: position);
}

class _ImageThumbnail extends StatelessWidget {
  const _ImageThumbnail({
    required this.image,
    required this.label,
    required this.maxHeight,
    this.onTap,
    this.onCopy,
  });

  final ImageProvider image;
  final String label;
  final double maxHeight;
  final VoidCallback? onTap;

  /// Offered in a context menu when set.
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final decodedHeight = (maxHeight * MediaQuery.devicePixelRatioOf(context))
        .round();
    return Semantics(
      label: label,
      image: true,
      // A max height rather than a fixed one keeps the box to the image's
      // proportions when the width runs short, so the corners stay on it.
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ClipRRect(
          borderRadius: paperRadius,
          child: _CopyImageMenu(
            onCopy: onCopy,
            child: InkWell(
              onTap: onTap,
              child: Image(
                image: ResizeImage(image, height: decodedHeight),
                excludeFromSemantics: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Offers "Copy image" on right-click, or on long press for touch screens.
class _CopyImageMenu extends StatefulWidget {
  const _CopyImageMenu({required this.onCopy, required this.child});

  /// No menu when null.
  final VoidCallback? onCopy;
  final Widget child;

  @override
  State<_CopyImageMenu> createState() => _CopyImageMenuState();
}

class _CopyImageMenuState extends State<_CopyImageMenu> {
  final _menu = ContextMenuController();

  @override
  void dispose() {
    _menu.remove();
    super.dispose();
  }

  void _show(Offset position) {
    final onCopy = widget.onCopy;
    if (onCopy == null) return;
    _menu.show(
      context: context,
      contextMenuBuilder: (context) => TapRegion(
        onTapOutside: (_) => _menu.remove(),
        child: AdaptiveTextSelectionToolbar.buttonItems(
          anchors: TextSelectionToolbarAnchors(primaryAnchor: position),
          buttonItems: [
            ContextMenuButtonItem(
              label: AppLocalizations.of(context).copyImage,
              onPressed: () {
                _menu.remove();
                onCopy();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onCopy == null || !canCopyImages) return widget.child;
    return GestureDetector(
      onSecondaryTapUp: (details) => _show(details.globalPosition),
      onLongPressStart: (details) => _show(details.globalPosition),
      child: widget.child,
    );
  }
}

class _AttachmentsPreview extends StatelessWidget {
  const _AttachmentsPreview({
    required this.images,
    required this.onRemove,
    this.maxHeight = 96,
  });

  final List<PastedImage> images;
  final ValueChanged<PastedImage> onRemove;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final onNote = Theme.of(context).colorScheme.onPrimaryContainer;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final (index, pasted) in images.indexed)
          // Beside the image rather than over it: its width is 0 until decoded.
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: _ImageThumbnail(
                  image: pasted.image,
                  label: _imageLabel(l10n, index, images.length),
                  maxHeight: maxHeight,
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                style: IconButton.styleFrom(
                  backgroundColor: onNote.withValues(alpha: 0.1),
                  foregroundColor: onNote,
                ),
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                tooltip: l10n.removeImage,
                onPressed: () => onRemove(pasted),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
      ],
    );
  }
}

class _ImageViewer extends StatefulWidget {
  const _ImageViewer({
    required this.store,
    required this.names,
    required this.initialIndex,
  });

  final ThoughtStore store;
  final List<String> names;
  final int initialIndex;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  // Its own messenger, since the app's snackbars sit under the viewer.
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  late var _index = widget.initialIndex;
  var _zoomed = false;
  var _copied = false;
  Timer? _copiedReset;

  @override
  void dispose() {
    _copiedReset?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _turn(int by) {
    final page = _index + by;
    if (page < 0 || page >= widget.names.length) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(
        page,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _copy() async {
    try {
      // No await before this call: on the web it must run inside the click.
      await copyImage(widget.store.readImage(widget.names[_index]));
    } catch (error, stack) {
      reportError(error, stack);
      if (!mounted) return;
      _messenger.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).imageNotCopied)),
        );
      return;
    }
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedReset?.cancel();
    _copiedReset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final count = widget.names.length;
    void close() => Navigator.pop(context);
    // Dark discs keep the buttons readable over light images.
    final buttonStyle = IconButton.styleFrom(
      backgroundColor: Colors.black54,
      foregroundColor: Colors.white,
    );

    Widget arrow(AlignmentGeometry alignment, int by) {
      final page = _index + by;
      if (page < 0 || page >= count) return const SizedBox.shrink();
      return Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: IconButton(
            style: buttonStyle,
            tooltip: by < 0 ? l10n.previousImage : l10n.nextImage,
            onPressed: () => _turn(by),
            icon: Icon(
              by < 0 ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
            ),
          ),
        ),
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _turn(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _turn(1),
        if (canCopyImages) ...{
          const SingleActivator(LogicalKeyboardKey.keyC, meta: true): _copy,
          const SingleActivator(LogicalKeyboardKey.keyC, control: true): _copy,
        },
      },
      child: Focus(
        autofocus: true,
        child: ScaffoldMessenger(
          key: _messenger,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  controller: _pages,
                  // A zoomed image pans instead of turning the page.
                  physics: _zoomed
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  itemCount: count,
                  onPageChanged: (index) => setState(() {
                    _index = index;
                    _zoomed = false;
                    _copied = false;
                  }),
                  itemBuilder: (context, index) => GestureDetector(
                    onTap: close,
                    child: _CopyImageMenu(
                      onCopy: _copy,
                      child: _ZoomableImage(
                        image: widget.store.imageNamed(widget.names[index]),
                        label: _imageLabel(l10n, index, count),
                        onZoomChanged: (zoomed) =>
                            setState(() => _zoomed = zoomed),
                      ),
                    ),
                  ),
                ),
                if (count > 1)
                  SafeArea(
                    child: Stack(
                      children: [
                        arrow(AlignmentDirectional.centerStart, -1),
                        arrow(AlignmentDirectional.centerEnd, 1),
                      ],
                    ),
                  ),
                SafeArea(
                  child: Align(
                    alignment: AlignmentDirectional.topEnd,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (canCopyImages) ...[
                            IconButton(
                              style: buttonStyle,
                              tooltip: _copied
                                  ? l10n.imageCopied
                                  : l10n.copyImage,
                              onPressed: _copy,
                              icon: Icon(
                                _copied
                                    ? Icons.check_rounded
                                    : Icons.content_copy_rounded,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          IconButton(
                            style: buttonStyle,
                            tooltip: MaterialLocalizations.of(context)
                                .closeButtonTooltip,
                            onPressed: close,
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({
    required this.image,
    required this.label,
    required this.onZoomChanged,
  });

  final ImageProvider image;
  final String label;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  final _transform = TransformationController();
  var _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(() {
      final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
      if (zoomed == _zoomed) return;
      _zoomed = zoomed;
      widget.onZoomChanged(zoomed);
    });
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InteractiveViewer(
    transformationController: _transform,
    maxScale: 6,
    child: Image(image: widget.image, semanticLabel: widget.label),
  );
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({required this.alignment});

  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurface;
    return ColoredBox(
      color: theme.colorScheme.outlineVariant,
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _inset),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline_rounded, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context).delete,
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Submits on Enter. Shift+Enter goes on to the platform, which starts a new
/// line in a multiline field.
class _SubmitOnEnter extends StatelessWidget {
  const _SubmitOnEnter({
    required this.controller,
    required this.onSubmit,
    required this.child,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final Widget child;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyUpEvent ||
        (key != LogicalKeyboardKey.enter &&
            key != LogicalKeyboardKey.numpadEnter) ||
        HardwareKeyboard.instance.isShiftPressed ||
        // An input method confirms its composition with Enter.
        controller.value.composing.isValid) {
      return KeyEventResult.ignored;
    }
    // Repeats are swallowed, or a held Enter would fill the emptied field
    // with line breaks.
    if (event is KeyDownEvent) onSubmit();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: _handleKey,
    child: child,
  );
}

typedef _Edit = ({
  String text,
  List<String> images,
  String? theme,
  bool themeChosen,
});

class _EditDialog extends StatefulWidget {
  const _EditDialog({
    required this.store,
    required this.thought,
    required this.themes,
    required this.aiSorts,
    required this.onDelete,
  });

  final ThoughtStore store;
  final Thought thought;

  /// Every theme a thought has, in the sidebar's order, to pick from.
  final List<String> themes;

  /// Whether an AI sorts the thoughts without a theme.
  final bool aiSorts;
  final VoidCallback onDelete;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _controller = TextEditingController(text: widget.thought.text);
  final _focus = FocusNode();
  late var _images = <PastedImage>[
    for (final name in widget.thought.images)
      (name: name, image: widget.store.imageNamed(name)),
  ];
  late String? _theme = widget.thought.theme;
  late var _themeChosen = widget.thought.themeChosen;
  String? _error;

  bool _canSave(String text) => text.trim().isNotEmpty || _images.isNotEmpty;

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (!_canSave(_controller.text)) return;
    Navigator.pop<_Edit>(context, (
      text: _controller.text,
      images: [for (final pasted in _images) pasted.name],
      theme: _theme,
      themeChosen: _themeChosen,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final images = _images;
    final error = _error;
    final shiftEnter = _shiftEnterBreaksLine(theme.platform);
    // The thought's own note, taken back off the list.
    return AlertDialog(
      semanticLabel: l10n.editTitle,
      backgroundColor: scheme.primaryContainer,
      shape: const RoundedRectangleBorder(borderRadius: paperRadius),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: _gutter,
        vertical: 24,
      ),
      contentPadding: const EdgeInsets.fromLTRB(_inset, 18, _inset, 0),
      actionsPadding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (images.isNotEmpty) ...[
            _AttachmentsPreview(
              images: images,
              maxHeight: 120,
              onRemove: (removed) => setState(
                () => _images = [
                  for (final pasted in _images)
                    if (pasted != removed) pasted,
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          ImagePaste(
            store: widget.store,
            focusNode: _focus,
            onImage: (pasted) => setState(() {
              final known = _images.any((image) => image.name == pasted.name);
              if (!known) _images = [..._images, pasted];
              _error = known ? l10n.imageAlreadyAdded : null;
            }),
            onError: (message) => setState(() => _error = message),
            builder: (contextMenuBuilder) => _SubmitOnEnter(
              controller: _controller,
              onSubmit: _save,
              child: Semantics(
                label: l10n.thoughtField,
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 8,
                  keyboardType: shiftEnter
                      ? TextInputType.multiline
                      : TextInputType.text,
                  textInputAction: shiftEnter
                      ? TextInputAction.newline
                      : TextInputAction.done,
                  textCapitalization: TextCapitalization.sentences,
                  onEditingComplete: _save,
                  contextMenuBuilder: contextMenuBuilder,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontSize: 22,
                    color: scheme.onPrimaryContainer,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
              ),
            ),
          ),
          // Inline rather than a snackbar, which would sit under the dialog's barrier.
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          _ThemeMenu(
            theme: _theme,
            chosen: _themeChosen,
            themes: widget.themes,
            aiSorts: widget.aiSorts,
            onChoose: (theme) => setState(() {
              _theme = theme;
              _themeChosen = theme != null;
            }),
            builder: (context, toggle) => Tooltip(
              message: l10n.theme,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onPrimaryContainer,
                  // Lines the label up with the text above.
                  padding: const EdgeInsetsDirectional.fromSTEB(0, 8, 8, 8),
                ),
                onPressed: toggle,
                icon: const Icon(Icons.label_outline_rounded, size: 18),
                label: Text(_theme ?? l10n.chooseTheme),
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: l10n.delete,
          color: scheme.onPrimaryContainer,
          onPressed: () {
            Navigator.pop(context);
            widget.onDelete();
          },
          icon: const Icon(Icons.delete_outline_rounded),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: scheme.onPrimaryContainer,
              ),
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, value, _) => FilledButton(
                style: FilledButton.styleFrom(
                  disabledBackgroundColor: scheme.onPrimaryContainer.withValues(
                    alpha: 0.08,
                  ),
                  disabledForegroundColor: scheme.onPrimaryContainer.withValues(
                    alpha: 0.4,
                  ),
                ),
                onPressed: _canSave(value.text) ? _save : null,
                child: Text(l10n.save),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Opens a menu to put a thought in another theme, a new one, or none.
class _ThemeMenu extends StatelessWidget {
  const _ThemeMenu({
    required this.theme,
    required this.chosen,
    required this.themes,
    required this.aiSorts,
    required this.onChoose,
    required this.builder,
  });

  final String? theme;

  /// Whether the person chose [theme] rather than the AI.
  final bool chosen;
  final List<String> themes;
  final bool aiSorts;

  /// Null takes the thought out of its theme, for the AI to sort if any.
  final ValueChanged<String?> onChoose;

  /// The button that opens and closes the menu with `toggle`.
  final Widget Function(BuildContext context, VoidCallback toggle) builder;

  Future<void> _create(BuildContext context) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => ThemeNameDialog(themes: themes),
    );
    if (name != null) onChoose(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = this.theme;
    final named = [
      ...themes,
      if (theme != null && !themes.contains(theme)) theme,
    ];
    return MenuAnchor(
      menuChildren: [
        for (final name in named)
          RadioMenuButton<String>(
            value: name,
            groupValue: theme,
            onChanged: (_) => onChoose(name),
            child: Text(name),
          ),
        if (named.isNotEmpty) const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.add_rounded),
          onPressed: () => _create(context),
          child: Text(l10n.newThemeItem),
        ),
        // The AI's own theme is already its choice.
        if (theme != null && (chosen || !aiSorts))
          MenuItemButton(
            leadingIcon: Icon(
              aiSorts ? Icons.auto_awesome_outlined : Icons.label_off_outlined,
            ),
            onPressed: () => onChoose(null),
            child: Text(aiSorts ? l10n.letAiChoose : l10n.noTheme),
          ),
      ],
      builder: (context, controller, _) => builder(
        context,
        () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
