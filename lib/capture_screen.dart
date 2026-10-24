import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'backup.dart';
import 'clipboard_image_io.dart'
    if (dart.library.js_interop) 'clipboard_image_web.dart';
import 'context_menu.dart';
import 'day_label.dart';
import 'focus_ring.dart';
import 'formatting.dart';
import 'image_paste.dart';
import 'l10n/app_localizations.dart';
import 'list_settings.dart';
import 'report_error.dart';
import 'settings_page.dart';
import 'sidebar.dart';
import 'sliver_animated_reorderable_list.dart';
import 'theme.dart';
import 'theme_name_dialog.dart';
import 'theme_names.dart';
import 'thought.dart';
import 'thought_field.dart';
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

const _messageWidth = 480.0;

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

extension on ScaffoldMessengerState {
  /// Replaces the message shown with [text], centered over the window past
  /// [start], where the sidebar ends.
  void showMessage(
    String text, {
    SnackBarAction? action,
    bool persist = false,
    double start = 0,
  }) {
    final side = math.max(
      _gutter,
      (MediaQuery.sizeOf(context).width - start - _messageWidth) / 2,
    );
    this
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          action: action,
          // Flutter otherwise keeps a message with an action until tapped.
          persist: persist,
          // SnackBar resolves a directional margin as left-to-right.
          margin: EdgeInsetsDirectional.only(
            start: start + side,
            end: side,
            bottom: _gutter,
          ).resolve(Directionality.of(context)),
        ),
      );
  }
}

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
  final _input = thoughtController();
  final _inputFocus = FocusNode();
  var _listKey = GlobalKey<SliverAnimatedReorderableListState>();
  final _scaffold = GlobalKey<ScaffoldState>();
  final _scroll = ScrollController();
  late final AppLifecycleListener _lifecycle;
  late final Timer _clock;

  /// The images pasted into the field, waiting to be sent.
  var _attachments = <PastedImage>[];

  /// Thoughts noted in the open theme, kept in it until the AI gives them
  /// theirs.
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
    if (theme == null) return _rowsOf(_store.thoughts, withHeadings: true);
    final thoughts = [
      for (final t in _store.thoughts)
        if (_isIn(t, theme) || (t.themes.isEmpty && _notedHere.contains(t.id)))
          t,
    ];
    // Stable, so that thoughts of equal rank stay newest first.
    mergeSort(
      thoughts,
      compare: (a, b) => b.rankIn(theme).compareTo(a.rankIn(theme)),
    );
    return _rowsOf(thoughts, withHeadings: false);
  }

  /// Whether [thought] is listed under [theme], '' for no theme.
  bool _isIn(Thought thought, String theme) =>
      theme.isEmpty ? thought.themes.isEmpty : thought.themes.contains(theme);

  /// The themes the sidebar opens, in the person's order, then '' for the
  /// thoughts that will get none. Empty when there is no sidebar.
  List<String> _sidebarThemes() {
    final theme = _theme;
    final themes = {..._store.themes, ?theme};
    if (themes.isEmpty) return const [];
    final noThemeOpen = themes.remove('');
    return [
      ...orderedThemes(themes, _listSettings.themeOrder),
      // Not for the thoughts the AI is about to sort, which would flicker.
      if (noThemeOpen ||
          _store.thoughts.any((t) => t.themes.isEmpty && !_tidier.willSort(t)))
        '',
    ];
  }

  bool get _wide => MediaQuery.sizeOf(context).width >= _wideWidth;

  /// Where the list's side of the window starts, past a sidebar beside it.
  double get _listStart =>
      _wide && _sidebarThemes().isNotEmpty ? _sidebarWidth : 0;

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
    final gone = switch (_theme) {
      null => false,
      '' => !_store.thoughts.any((t) => t.themes.isEmpty),
      final theme => !_store.themes.contains(theme),
    };
    if (gone) _listSettings.theme = null;
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
    final content = contentOf(_input.document);
    final images = [for (final pasted in _attachments) pasted.name];
    final thought = _store.add(
      content.text,
      delta: content.delta,
      images: images,
    );
    if (thought == null) return;
    // Its id is only known now, after the store has told the list.
    _notedHere.add(thought.id);
    _syncRows();
    _tidier.noted(thought);
    // Rather than clear(), which keeps the last line's list and bold.
    _input
      ..document = Document()
      ..toggledStyle = const Style();
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

  void _showError(String message) =>
      ScaffoldMessenger.of(context).showMessage(message, start: _listStart);

  Future<void> _copyImage(String name) async {
    try {
      // No await before this call: on the web it must run inside the click.
      await copyImage(_store.readImage(name));
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) _showError(AppLocalizations.of(context).imageNotCopied);
    }
  }

  Future<void> _copyText(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) _showError(AppLocalizations.of(context).textNotCopied);
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

  /// Moves the thought at [from] in the open theme to [to].
  void _move(int from, int to) {
    // Before the store tells the list, which then has nothing to animate.
    _rows.insert(to, _rows.removeAt(from));
    _store.reorder(_theme!, [for (final row in _rows) row.thought!.id]);
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
    ScaffoldMessenger.of(context).showMessage(
      message,
      start: _listStart,
      // A screen reader takes longer than the timeout to reach Undo. The web
      // keeps semantics on for typing, so it cannot tell one is running.
      persist: !kIsWeb && MediaQuery.accessibleNavigationOf(context),
      action: SnackBarAction(
        label: AppLocalizations.of(context).undo,
        onPressed: () {
          if (mounted) undo();
        },
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

  void _openSettings() {
    _scaffold.currentState?.closeDrawer();
    Navigator.push(
      context,
      SettingsPage.route(tidier: _tidier, backup: widget.backup),
    );
  }

  Future<void> _edit(Thought thought) async {
    final edit = await showDialog<_Edit>(
      context: context,
      builder: (_) => _EditDialog(
        store: _store,
        thought: thought,
        themes: _themes(),
        onDelete: () => _remove(thought),
      ),
    );
    if (edit == null) return;
    _store.update(
      thought.id,
      text: edit.text,
      delta: edit.delta,
      images: edit.images,
    );
    if (!listEquals(edit.themes, thought.themes)) {
      _store.chooseThemes(thought.id, edit.themes);
    }
  }

  List<String> _themes() =>
      orderedThemes(_store.themes, _listSettings.themeOrder);

  /// Says what the AI found when the open theme does not show it.
  Future<void> _cleanUp() async {
    _scaffold.currentState?.closeDrawer();
    final found = await _tidier.cleanUp();
    if (!mounted || found == null) return;
    final shown = {for (final row in _rows) ?row.thought?.id};
    if (_tidier.suggestions.any((s) => s.ids.any(shown.contains))) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showMessage(
      found == 0 ? l10n.nothingToCleanUp : l10n.suggestionsElsewhere(found),
      start: _listStart,
      action: found == 0
          ? null
          : SnackBarAction(label: l10n.show, onPressed: () => _open(null)),
    );
  }

  /// Opens a new theme, or the one its name spells.
  Future<void> _createTheme() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => ThemeNameDialog(themes: _themes()),
    );
    if (name == null) return;
    _store.addThemes([name]);
    _open(name);
  }

  /// Renames [theme], which joins another when it takes its name.
  Future<void> _renameTheme(String theme) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => ThemeNameDialog(themes: _themes(), renaming: theme),
    );
    if (name == null || name == theme) return;
    // Before the store tells the list, which then keeps the same thoughts.
    if (_theme == theme) _listSettings.theme = name;
    _listSettings.renameTheme(theme, name);
    _store.renameTheme(theme, name);
  }

  /// Takes [theme] off its thoughts, which stay. It keeps its place in the
  /// sidebar's order, for undo.
  void _deleteTheme(String theme) {
    final open = _theme == theme;
    if (open) _open(null);
    final originals = _store.removeTheme(theme);
    _offerUndo(AppLocalizations.of(context).themeDeleted, () {
      _store.restoreTheme(theme, originals);
      if (open) _open(theme);
    });
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
    final inputStyle = theme.textTheme.displaySmall!.copyWith(
      color: scheme.onPrimaryContainer,
    );
    final attachments = _attachments;

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
                          builder: (contextMenuBuilder) => ThoughtField(
                            controller: _input,
                            focusNode: _inputFocus,
                            label: l10n.thoughtField,
                            style: inputStyle,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            maxLines: 5,
                            action: TextInputAction.send,
                            onSubmit: _capture,
                            contextMenuBuilder: contextMenuBuilder,
                            placeholder: l10n.captureHint,
                            placeholderStyle: inputStyle.copyWith(
                              color: scheme.onPrimaryContainer.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ListenableBuilder(
                        listenable: _input,
                        builder: (context, _) => IconButton.filled(
                          style: IconButton.styleFrom(
                            disabledBackgroundColor: scheme.onPrimaryContainer
                                .withValues(alpha: 0.08),
                            disabledForegroundColor: scheme.onPrimaryContainer
                                .withValues(alpha: 0.4),
                          ),
                          tooltip: l10n.captureButton,
                          onPressed:
                              _input.document.toPlainText().trim().isEmpty &&
                                  attachments.isEmpty
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
    final sidebar = themes.isEmpty
        ? null
        : Sidebar(
            themes: themes,
            selected: _theme,
            onSelect: _open,
            onCreate: _createTheme,
            onRename: _renameTheme,
            onDelete: _deleteTheme,
            onReorder: (order) => _listSettings.themeOrder = order,
            cleaning: _tidier.cleaning,
            onCleanUp: _tidier.settings == null ? null : _cleanUp,
            onSettings: _openSettings,
          );
    return Scaffold(
      key: _scaffold,
      drawer: sidebar == null || _wide
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
            if (sidebar != null && _wide)
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
                            if (sidebar == null || !_wide)
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

  /// Opens the drawer, or the AI's clean-up and the settings while there is
  /// no sidebar.
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
                if (tidier.settings != null && _store.thoughts.isNotEmpty)
                  IconButton(
                    tooltip: tidier.cleaning
                        ? l10n.cleaningUp
                        : l10n.cleanUpAction,
                    onPressed: tidier.cleaning ? null : _cleanUp,
                    icon: tidier.cleaning
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_fix_high_outlined),
                  ),
                IconButton(
                  tooltip: l10n.settings,
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings_outlined),
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
                      onPressed: _tidier.cleanUpFailed
                          ? _cleanUp
                          : _tidier.retry,
                      child: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_rows.isEmpty)
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
                        sliver: SliverAnimatedReorderableList(
                          key: _listKey,
                          initialItemCount: _rows.length,
                          itemBuilder: (context, index, animation, moves) =>
                              _buildRow(_rows[index], animation, moves),
                          onReorderItem: _theme == null ? null : _move,
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

  Widget _buildRow(
    _Row row,
    Animation<double> animation, [
    ItemMoves moves = ItemMoves.none,
  ]) {
    final eased = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    final thought = row.thought;
    return SizeTransition(
      sizeFactor: eased,
      child: FadeTransition(
        opacity: eased,
        child: thought == null
            ? _Heading(day: row.day)
            : _buildThought(thought, moves),
      ),
    );
  }

  Widget _buildThought(Thought thought, ItemMoves moves) {
    final l10n = AppLocalizations.of(context);
    final themes = _themes();
    final otherThemes = orderedThemes(
      thought.themes.where((theme) => theme != _theme),
      _listSettings.themeOrder,
    );
    void chooseThemes(List<String> chosen) =>
        _store.chooseThemes(thought.id, chosen);
    return ContextMenu<int>(
      menuChildren: (image, focusFirst) => [
        if (image != null) ...[
          _ClipboardMenuItem(
            icon: Icons.image_outlined,
            label: l10n.copyImage,
            onPressed: () => _copyImage(thought.images[image]),
          ),
          const Divider(),
        ],
        MenuItemButton(
          autofocus: focusFirst,
          leadingIcon: const Icon(Icons.edit_outlined),
          onPressed: () => _edit(thought),
          child: Text(l10n.edit),
        ),
        if (thought.text.isNotEmpty)
          _ClipboardMenuItem(
            icon: Icons.content_copy_rounded,
            label: l10n.copyText,
            onPressed: () => _copyText(thought.text),
          ),
        SubmenuButton(
          leadingIcon: const Icon(Icons.label_outline_rounded),
          menuChildren: _themeItems(
            context,
            selected: thought.themes,
            themes: themes,
            onChoose: chooseThemes,
          ),
          child: Text(l10n.themes),
        ),
        if (moves.up != null || moves.down != null) ...[
          const Divider(),
          ...moveMenuItems(context, up: moves.up, down: moves.down),
        ],
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.delete_outline_rounded),
          onPressed: () => _remove(thought),
          child: Text(l10n.delete),
        ),
      ],
      builder: (openImageMenu) => Semantics(
        customSemanticsActions: {
          CustomSemanticsAction(label: l10n.delete): () => _remove(thought),
          ...moves.actions,
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
            child: moves.draggable(
              _ThoughtTile(
                text: thought.text,
                delta: thought.delta,
                title: thought.title,
                subtasks: thought.subtasks,
                images: _imagesOf(thought),
                createdAt: thought.createdAt,
                withDay: _theme != null,
                sorting: _tidier.willSort(thought),
                themeButton: otherThemes.isEmpty
                    ? null
                    : _ThemeMenu(
                        selected: thought.themes,
                        themes: themes,
                        onChoose: chooseThemes,
                        // Else the tooltip ends up on the thought rather than here.
                        builder: (context, toggle) => MergeSemantics(
                          child: Tooltip(
                            message: l10n.changeThemes,
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                textStyle: Theme.of(context)
                                    .textTheme
                                    .bodySmall,
                                // Lines the label up with the text above.
                                padding: const EdgeInsetsDirectional.only(
                                  end: 8,
                                ),
                                minimumSize: const Size(0, 28),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: toggle,
                              icon: const Icon(
                                Icons.label_outline_rounded,
                                size: 14,
                              ),
                              label: Text(otherThemes.join(', ')),
                            ),
                          ),
                        ),
                      ),
                onTap: () => _edit(thought),
                onToggleSubtask: (index) =>
                    _store.toggleSubtask(thought.id, index),
                onImageTap: (index) => _view(thought.images, index),
                onImageCopy: (index) => _copyImage(thought.images[index]),
                onImageMenu: openImageMenu,
                onDelete: () => _remove(thought),
              ),
            ),
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
    required this.delta,
    required this.title,
    required this.subtasks,
    required this.images,
    required this.createdAt,
    required this.withDay,
    required this.sorting,
    required this.themeButton,
    required this.onTap,
    required this.onToggleSubtask,
    required this.onImageTap,
    required this.onImageCopy,
    required this.onImageMenu,
    required this.onDelete,
  });

  final String text;

  /// The formatting of [text], see [Thought.delta].
  final List<Map<String, dynamic>> delta;

  /// Shown in place of [text], which the thought opens on.
  final String? title;
  final List<Subtask> subtasks;
  final List<ImageProvider> images;
  final DateTime createdAt;

  /// Shows the day it was noted rather than the time, unless that is today.
  final bool withDay;

  /// Whether the AI is about to give it themes, which [themeButton] then
  /// shows.
  final bool sorting;

  /// Under the text and images.
  final Widget? themeButton;
  final VoidCallback onTap;
  final ValueChanged<int> onToggleSubtask;
  final ValueChanged<int> onImageTap;
  final ValueChanged<int> onImageCopy;

  /// Opens the thought's menu at a global position, from one of its images.
  final void Function(Offset position, int index) onImageMenu;
  final VoidCallback onDelete;

  @override
  State<_ThoughtTile> createState() => _ThoughtTileState();
}

class _ThoughtTileState extends State<_ThoughtTile> {
  var _hovered = false;
  var _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_highlightModeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_highlightModeChanged);
    super.dispose();
  }

  void _highlightModeChanged(FocusHighlightMode _) => setState(() {});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.title;
    final text = title ?? widget.text;
    final subtasks = widget.subtasks;
    final images = widget.images;
    final footer = widget.sorting ? const _Sorting() : widget.themeButton;
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
    // Not on the focus a click gives on the web, through semantics, which
    // Flutter counts as touch.
    final revealed =
        _hovered ||
        _focused &&
            FocusManager.instance.highlightMode ==
                FocusHighlightMode.traditional;
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
          // Rather than InkWell's onHover, which goes quiet once the tile has
          // moved in the tree, as it does while dragged.
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: InkWell(
              borderRadius: paperRadius,
              onTap: widget.onTap,
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
                          if (title == null && widget.delta.isNotEmpty)
                            FormattedText(
                              text: text,
                              delta: widget.delta,
                              style: theme.textTheme.bodyLarge!,
                            )
                          else if (text.isNotEmpty)
                            Text(text, style: theme.textTheme.bodyLarge),
                          if (subtasks.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final (index, subtask)
                                      in subtasks.indexed)
                                    _SubtaskRow(
                                      subtask: subtask,
                                      onToggle: () =>
                                          widget.onToggleSubtask(index),
                                    ),
                                ],
                              ),
                            ),
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
                                      onMenu: (position) =>
                                          widget.onImageMenu(position, index),
                                    ),
                                ],
                              ),
                            ),
                          if (footer != null)
                            Padding(
                              padding: EdgeInsets.only(
                                top: images.isEmpty ? 2 : 8,
                              ),
                              child: footer,
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
      ),
    );
  }
}

/// Takes the place of the theme button, at its height.
class _Sorting extends StatelessWidget {
  const _Sorting();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 28 + theme.visualDensity.baseSizeAdjustment.dy,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 14,
            child: Padding(
              padding: const EdgeInsets.all(1),
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            AppLocalizations.of(context).tidying,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Ticked off with a tap anywhere on it, without opening the thought.
class _SubtaskRow extends StatelessWidget {
  const _SubtaskRow({required this.subtask, required this.onToggle});

  final Subtask subtask;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = subtask.done;
    return MergeSemantics(
      child: InkWell(
        borderRadius: paperRadius,
        onTap: onToggle,
        child: Row(
          children: [
            Checkbox(
              value: done,
              onChanged: (_) => onToggle(),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                subtask.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: done ? theme.colorScheme.onSurfaceVariant : null,
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
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
    this.onMenu,
  });

  final ImageProvider image;
  final String label;
  final double maxHeight;
  final VoidCallback? onTap;

  /// Offered in a context menu when set.
  final VoidCallback? onCopy;

  /// See [_CopyImageMenu.onMenu].
  final ValueChanged<Offset>? onMenu;

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
            onMenu: onMenu,
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
  const _CopyImageMenu({
    required this.onCopy,
    this.onMenu,
    required this.child,
  });

  /// No menu when null.
  final VoidCallback? onCopy;

  /// Opens another menu at a global position on right-click, rather than
  /// this one, when set.
  final ValueChanged<Offset>? onMenu;
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
      onSecondaryTapUp: (details) =>
          (widget.onMenu ?? _show)(details.globalPosition),
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
      _messenger.currentState?.showMessage(
        AppLocalizations.of(context).imageNotCopied,
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

typedef _Edit = ({
  String text,
  List<Map<String, dynamic>> delta,
  List<String> images,
  List<String> themes,
});

class _EditDialog extends StatefulWidget {
  const _EditDialog({
    required this.store,
    required this.thought,
    required this.themes,
    required this.onDelete,
  });

  final ThoughtStore store;
  final Thought thought;

  /// Every theme a thought has, in the sidebar's order, to pick from.
  final List<String> themes;
  final VoidCallback onDelete;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _controller = thoughtController(
    text: widget.thought.text,
    delta: widget.thought.delta,
  );
  final _focus = FocusNode();
  late var _images = <PastedImage>[
    for (final name in widget.thought.images)
      (name: name, image: widget.store.imageNamed(name)),
  ];
  late var _themes = widget.thought.themes;
  String? _error;

  bool get _canSave =>
      _controller.document.toPlainText().trim().isNotEmpty ||
      _images.isNotEmpty;

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (!_canSave) return;
    final content = contentOf(_controller.document);
    Navigator.pop<_Edit>(context, (
      text: content.text,
      delta: content.delta,
      images: [for (final pasted in _images) pasted.name],
      themes: _themes,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final images = _images;
    final error = _error;
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
            builder: (contextMenuBuilder) => ThoughtField(
              controller: _controller,
              focusNode: _focus,
              label: l10n.thoughtField,
              style: theme.textTheme.displaySmall!.copyWith(
                fontSize: 22,
                color: scheme.onPrimaryContainer,
              ),
              padding: const EdgeInsets.symmetric(vertical: 4),
              maxLines: 8,
              action: TextInputAction.done,
              onSubmit: _save,
              contextMenuBuilder: contextMenuBuilder,
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
            selected: _themes,
            themes: widget.themes,
            onChoose: (themes) => setState(() => _themes = themes),
            builder: (context, toggle) => Tooltip(
              message: l10n.themes,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onPrimaryContainer,
                  // Lines the label up with the text above.
                  padding: const EdgeInsetsDirectional.fromSTEB(0, 8, 8, 8),
                ),
                onPressed: toggle,
                icon: const Icon(Icons.label_outline_rounded, size: 18),
                label: Text(
                  _themes.isEmpty ? l10n.chooseThemes : _themes.join(', '),
                ),
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
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => FilledButton(
                style: FilledButton.styleFrom(
                  disabledBackgroundColor: scheme.onPrimaryContainer.withValues(
                    alpha: 0.08,
                  ),
                  disabledForegroundColor: scheme.onPrimaryContainer.withValues(
                    alpha: 0.4,
                  ),
                ),
                onPressed: _canSave ? _save : null,
                child: Text(l10n.save),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Opens a menu that ticks a thought's themes, and creates new ones. It stays
/// open, to tick several.
class _ThemeMenu extends StatelessWidget {
  const _ThemeMenu({
    required this.selected,
    required this.themes,
    required this.onChoose,
    required this.builder,
  });

  final List<String> selected;
  final List<String> themes;

  /// Called with every theme the thought then has, none when empty.
  final ValueChanged<List<String>> onChoose;

  /// The button that opens and closes the menu with `toggle`.
  final Widget Function(BuildContext context, VoidCallback toggle) builder;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    // Inside a thought's context menu, Flutter would open it as a submenu, at
    // the end of the button, which moves as ticking themes changes its label.
    style: const MenuStyle(alignment: AlignmentDirectional.bottomStart),
    menuChildren: _themeItems(
      context,
      selected: selected,
      themes: themes,
      onChoose: onChoose,
    ),
    builder: (context, controller, _) => builder(
      context,
      () => controller.isOpen ? controller.close() : controller.open(),
    ),
  );
}

/// Ticks [selected] among [themes], and creates new ones. [onChoose] gets
/// every theme the thought then has, none when empty.
List<Widget> _themeItems(
  BuildContext context, {
  required List<String> selected,
  required List<String> themes,
  required ValueChanged<List<String>> onChoose,
}) {
  Future<void> create() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => ThemeNameDialog(themes: themes),
    );
    if (name != null && !selected.contains(name)) onChoose([...selected, name]);
  }

  final named = [
    ...themes,
    for (final theme in selected)
      if (!themes.contains(theme)) theme,
  ];
  return [
    for (final name in named)
      CheckboxMenuButton(
        value: selected.contains(name),
        closeOnActivate: false,
        onChanged: (_) => onChoose(
          selected.contains(name)
              ? [
                  for (final theme in selected)
                    if (theme != name) theme,
                ]
              : [...selected, name],
        ),
        child: Text(name),
      ),
    if (named.isNotEmpty) const Divider(),
    MenuItemButton(
      leadingIcon: const Icon(Icons.add_rounded),
      onPressed: create,
      child: Text(AppLocalizations.of(context).newThemeItem),
    ),
  ];
}

/// A menu item that acts as soon as a click on it ends. [MenuItemButton]
/// waits a frame, past the click inside which browsers let a page write to
/// the clipboard.
class _ClipboardMenuItem extends StatefulWidget {
  const _ClipboardMenuItem({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  State<_ClipboardMenuItem> createState() => _ClipboardMenuItemState();
}

class _ClipboardMenuItemState extends State<_ClipboardMenuItem> {
  var _pressed = false;

  void _press() {
    if (_pressed) return;
    _pressed = true;
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerUp: (event) {
      if (!context.size!.contains(event.localPosition)) return;
      _press();
      MenuController.maybeOf(context)?.close();
    },
    child: MenuItemButton(
      leadingIcon: Icon(widget.icon),
      // For the keyboard.
      onPressed: _press,
      child: Text(widget.label),
    ),
  );
}
