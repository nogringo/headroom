import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'l10n/app_localizations.dart';
import 'relative_time.dart';
import 'thought.dart';
import 'thought_store.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, required this.store});

  final ThoughtStore store;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _listKey = GlobalKey<AnimatedListState>();
  final _scroll = ScrollController();
  late final AppLifecycleListener _lifecycle;
  late final Timer _clock;

  ThoughtStore get _store => widget.store;

  Duration get _motion => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 280);

  @override
  void initState() {
    super.initState();
    // Reopening the app from the background should land in the field, like a cold start.
    _lifecycle = AppLifecycleListener(onResume: _refocus);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
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

  void _capture() {
    if (_store.add(_input.text) == null) return;
    _input.clear();
    _inputFocus.requestFocus();
    _listKey.currentState?.insertItem(0, duration: _motion);
    if (_scroll.hasClients && _scroll.offset > 0) {
      if (_motion == Duration.zero) {
        _scroll.jumpTo(0);
      } else {
        _scroll.animateTo(0, duration: _motion, curve: Curves.easeOutCubic);
      }
    }
    HapticFeedback.lightImpact();
  }

  void _remove(Thought thought) {
    final index = _store.remove(thought.id);
    if (index == -1) return;
    _listKey.currentState?.removeItem(
      index,
      (_, _) => const SizedBox.shrink(),
      duration: Duration.zero,
    );
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.thoughtDeleted),
          action: SnackBarAction(
            label: l10n.undo,
            onPressed: () {
              if (!mounted) return;
              final at = _store.restore(thought, index);
              _listKey.currentState?.insertItem(at, duration: _motion);
            },
          ),
        ),
      );
  }

  Future<void> _edit(Thought thought) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _EditDialog(initialText: thought.text),
    );
    if (text != null) _store.update(thought.id, text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final inputStyle = theme.textTheme.displaySmall;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 16, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          focusNode: _inputFocus,
                          autofocus: true,
                          minLines: 1,
                          maxLines: 5,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.send,
                          textCapitalization: TextCapitalization.sentences,
                          onEditingComplete: _capture,
                          style: inputStyle,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 8,
                            ),
                            hintText: l10n.captureHint,
                            hintStyle: inputStyle?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ValueListenableBuilder(
                        valueListenable: _input,
                        builder: (context, value, _) => IconButton.filled(
                          tooltip: l10n.captureButton,
                          onPressed: value.text.trim().isEmpty
                              ? null
                              : _capture,
                          icon: const Icon(Icons.arrow_upward_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
                Expanded(
                  child: ListenableBuilder(
                    listenable: _store,
                    builder: (context, _) => _buildList(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_store.saveFailed)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Text(
              l10n.saveFailed,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_store.thoughts.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                  child: Text(
                    l10n.emptyList,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              AnimatedList(
                key: _listKey,
                controller: _scroll,
                padding: EdgeInsets.only(
                  top: 8,
                  bottom: 8 + MediaQuery.paddingOf(context).bottom,
                ),
                initialItemCount: _store.thoughts.length,
                itemBuilder: (context, index, animation) => _buildItem(
                  _store.thoughts[index],
                  animation,
                  relativeTime(_store.thoughts[index].createdAt, now, l10n),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildItem(Thought thought, Animation<double> animation, String age) {
    final eased = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    final l10n = AppLocalizations.of(context);

    return SizeTransition(
      sizeFactor: eased,
      child: FadeTransition(
        opacity: eased,
        child: Semantics(
          customSemanticsActions: {
            CustomSemanticsAction(label: l10n.delete): () => _remove(thought),
          },
          child: Dismissible(
            key: ValueKey(thought.id),
            background: const _SwipeBackground(
              alignment: AlignmentDirectional.centerStart,
            ),
            secondaryBackground: const _SwipeBackground(
              alignment: AlignmentDirectional.centerEnd,
            ),
            onDismissed: (_) => _remove(thought),
            child: _ThoughtTile(
              thought: thought,
              age: age,
              onTap: () => _edit(thought),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThoughtTile extends StatelessWidget {
  const _ThoughtTile({
    required this.thought,
    required this.age,
    required this.onTap,
  });

  final Thought thought;
  final String age;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Opaque so the swipe background only shows where the tile has slid away.
    return Material(
      color: theme.colorScheme.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(thought.text, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 4),
              Text(age, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({required this.alignment});

  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return ColoredBox(
      color: theme.colorScheme.outlineVariant,
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
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

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.initialText});

  final String initialText;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (_controller.text.trim().isEmpty) return;
    Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.editTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 1,
        maxLines: 8,
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.done,
        textCapitalization: TextCapitalization.sentences,
        onEditingComplete: _save,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ValueListenableBuilder(
          valueListenable: _controller,
          builder: (context, value, _) => FilledButton(
            onPressed: value.text.trim().isEmpty ? null : _save,
            child: Text(l10n.save),
          ),
        ),
      ],
    );
  }
}
