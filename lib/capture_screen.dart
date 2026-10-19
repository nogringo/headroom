import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'image_paste.dart';
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

  /// The image pasted into the field, waiting to be sent.
  PastedImage? _attachment;

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
    if (_store.add(_input.text, image: _attachment?.name) == null) return;
    _input.clear();
    setState(() => _attachment = null);
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

  void _showError(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

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
    final edit = await showDialog<_Edit>(
      context: context,
      builder: (_) => _EditDialog(store: _store, thought: thought),
    );
    if (edit != null) {
      _store.update(thought.id, text: edit.text, image: edit.image);
    }
  }

  void _view(ImageProvider image) => showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    useSafeArea: false,
    builder: (_) => _ImageViewer(image: image),
  );

  ImageProvider? _imageOf(Thought thought) => switch (thought.image) {
    null => null,
    final name => _store.imageNamed(name),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final inputStyle = theme.textTheme.displaySmall;
    final attachment = _attachment;

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
                              onImage: (image) =>
                                  setState(() => _attachment = image),
                              onError: _showError,
                              builder: (contextMenuBuilder) => TextField(
                                controller: _input,
                                focusNode: _inputFocus,
                                autofocus: true,
                                minLines: 1,
                                maxLines: 5,
                                keyboardType: TextInputType.text,
                                textInputAction: TextInputAction.send,
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
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ValueListenableBuilder(
                            valueListenable: _input,
                            builder: (context, value, _) => IconButton.filled(
                              tooltip: l10n.captureButton,
                              onPressed:
                                  value.text.trim().isEmpty &&
                                      attachment == null
                                  ? null
                                  : _capture,
                              icon: const Icon(Icons.arrow_upward_rounded),
                            ),
                          ),
                        ],
                      ),
                      if (attachment != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _AttachmentPreview(
                            image: attachment.image,
                            onRemove: () => setState(() => _attachment = null),
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
    final image = _imageOf(thought);

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
              text: thought.text,
              image: image,
              age: age,
              onTap: () => _edit(thought),
              onImageTap: image == null ? null : () => _view(image),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThoughtTile extends StatelessWidget {
  const _ThoughtTile({
    required this.text,
    required this.image,
    required this.age,
    required this.onTap,
    required this.onImageTap,
  });

  final String text;
  final ImageProvider? image;
  final String age;
  final VoidCallback onTap;
  final VoidCallback? onImageTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = this.image;
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
              if (text.isNotEmpty) Text(text, style: theme.textTheme.bodyLarge),
              if (image != null)
                Padding(
                  padding: EdgeInsets.only(top: text.isEmpty ? 2 : 10),
                  child: _ImageThumbnail(
                    image: image,
                    maxHeight: 160,
                    onTap: onImageTap,
                  ),
                ),
              SizedBox(height: image == null ? 4 : 8),
              Text(age, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageThumbnail extends StatelessWidget {
  const _ImageThumbnail({
    required this.image,
    required this.maxHeight,
    this.onTap,
  });

  final ImageProvider image;
  final double maxHeight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final decodedHeight = (maxHeight * MediaQuery.devicePixelRatioOf(context))
        .round();
    return Semantics(
      label: AppLocalizations.of(context).imageLabel,
      image: true,
      // A max height rather than a fixed one keeps the box to the image's
      // proportions when the width runs short, so the corners stay on it.
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            child: Image(
              image: ResizeImage(image, height: decodedHeight),
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({
    required this.image,
    required this.onRemove,
    this.maxHeight = 96,
  });

  final ImageProvider image;
  final VoidCallback onRemove;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    // Beside the image rather than over it: its width is 0 until decoded.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: _ImageThumbnail(image: image, maxHeight: maxHeight),
        ),
        const SizedBox(width: 4),
        IconButton.filledTonal(
          visualDensity: VisualDensity.compact,
          iconSize: 16,
          tooltip: AppLocalizations.of(context).removeImage,
          onPressed: onRemove,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.image});

  final ImageProvider image;

  @override
  Widget build(BuildContext context) {
    void close() => Navigator.pop(context);
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: close,
            child: InteractiveViewer(
              maxScale: 6,
              child: Image(
                image: image,
                semanticLabel: AppLocalizations.of(context).imageLabel,
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: AlignmentDirectional.topEnd,
              child: IconButton(
                color: Colors.white,
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: close,
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ),
        ],
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

typedef _Edit = ({String text, String? image});

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.store, required this.thought});

  final ThoughtStore store;
  final Thought thought;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _controller = TextEditingController(text: widget.thought.text);
  final _focus = FocusNode();
  late PastedImage? _image = switch (widget.thought.image) {
    null => null,
    final name => (name: name, image: widget.store.imageNamed(name)),
  };
  String? _error;

  bool _canSave(String text) => text.trim().isNotEmpty || _image != null;

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
      image: _image?.name,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final image = _image;
    final error = _error;
    return AlertDialog(
      title: Text(l10n.editTitle),
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (image != null) ...[
            _AttachmentPreview(
              image: image.image,
              maxHeight: 160,
              onRemove: () => setState(() => _image = null),
            ),
            const SizedBox(height: 16),
          ],
          ImagePaste(
            store: widget.store,
            focusNode: _focus,
            onImage: (pasted) => setState(() {
              _image = pasted;
              _error = null;
            }),
            onError: (message) => setState(() => _error = message),
            builder: (contextMenuBuilder) => TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: true,
              minLines: 1,
              maxLines: 8,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              onEditingComplete: _save,
              contextMenuBuilder: contextMenuBuilder,
            ),
          ),
          // Inline rather than a snackbar, which would sit under the dialog's barrier.
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ValueListenableBuilder(
          valueListenable: _controller,
          builder: (context, value, _) => FilledButton(
            onPressed: _canSave(value.text) ? _save : null,
            child: Text(l10n.save),
          ),
        ),
      ],
    );
  }
}
