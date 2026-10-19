import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'image_paste.dart';
import 'l10n/app_localizations.dart';
import 'relative_time.dart';
import 'thought.dart';
import 'thought_store.dart';

const _contentWidth = 640.0;

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

  /// The images pasted into the field, waiting to be sent.
  var _attachments = <PastedImage>[];

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
    final images = [for (final pasted in _attachments) pasted.name];
    if (_store.add(_input.text, images: images) == null) return;
    _input.clear();
    setState(() => _attachments = []);
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

  void _remove(Thought thought, {bool swiped = false}) {
    final index = _store.remove(thought.id);
    if (index == -1) return;
    final l10n = AppLocalizations.of(context);
    final age = relativeTime(thought.createdAt, DateTime.now(), l10n);
    // A swiped tile has already slid away. Any other one collapses.
    _listKey.currentState?.removeItem(
      index,
      (_, animation) => swiped
          ? const SizedBox.shrink()
          : IgnorePointer(child: _buildItem(thought, animation, age)),
      duration: swiped ? Duration.zero : _motion,
    );
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
      builder: (_) => _EditDialog(
        store: _store,
        thought: thought,
        onDelete: () => _remove(thought),
      ),
    );
    if (edit != null) {
      _store.update(thought.id, text: edit.text, images: edit.images);
    }
  }

  void _view(List<ImageProvider> images, int index) => showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    useSafeArea: false,
    builder: (_) => _ImageViewer(images: images, initialIndex: index),
  );

  List<ImageProvider> _imagesOf(Thought thought) => [
    for (final name in thought.images) _store.imageNamed(name),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final inputStyle = theme.textTheme.displaySmall;
    final attachments = _attachments;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _contentWidth),
                child: Padding(
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
                              onImage: (image) {
                                if (_attachments.any(
                                  (pasted) => pasted.name == image.name,
                                )) {
                                  _showError(l10n.imageAlreadyAdded);
                                } else {
                                  setState(
                                    () =>
                                        _attachments = [..._attachments, image],
                                  );
                                }
                              },
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
    );
  }

  Widget _buildList(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();

    // The list spans the window so its scrollbar sits at the edge and the
    // margins scroll too. Its content keeps to the field's centered column.
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.max(0.0, (constraints.maxWidth - _contentWidth) / 2);
        final inset = EdgeInsets.symmetric(horizontal: side + 24);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_store.saveFailed)
              Padding(
                padding: inset.copyWith(top: 12),
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
                      padding: inset.copyWith(top: 22),
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
                    padding: EdgeInsets.fromLTRB(
                      side,
                      8,
                      side,
                      8 + MediaQuery.paddingOf(context).bottom,
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
      },
    );
  }

  Widget _buildItem(Thought thought, Animation<double> animation, String age) {
    final eased = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    final l10n = AppLocalizations.of(context);
    final images = _imagesOf(thought);

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
            onDismissed: (_) => _remove(thought, swiped: true),
            child: _ThoughtTile(
              text: thought.text,
              images: images,
              age: age,
              onTap: () => _edit(thought),
              onImageTap: (index) => _view(images, index),
              onDelete: () => _remove(thought),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThoughtTile extends StatefulWidget {
  const _ThoughtTile({
    required this.text,
    required this.images,
    required this.age,
    required this.onTap,
    required this.onImageTap,
    required this.onDelete,
  });

  final String text;
  final List<ImageProvider> images;
  final String age;
  final VoidCallback onTap;
  final ValueChanged<int> onImageTap;
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
    // Touch screens have the swipe. Where a pointer hovers, a button shows up
    // on hover, or on keyboard focus.
    final deleteButton =
        kIsWeb ||
        switch (theme.platform) {
          TargetPlatform.macOS ||
          TargetPlatform.windows ||
          TargetPlatform.linux => true,
          _ => false,
        };
    // Opaque so the swipe background only shows where the tile has slid away.
    return Material(
      color: theme.colorScheme.surface,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: InkWell(
          onTap: widget.onTap,
          onHover: (hovered) => setState(() => _hovered = hovered),
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              24,
              14,
              deleteButton ? 12 : 24,
              14,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (text.isNotEmpty)
                        Text(text, style: theme.textTheme.bodyLarge),
                      if (images.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: text.isEmpty ? 2 : 10),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final (index, image) in images.indexed)
                                _ImageThumbnail(
                                  image: image,
                                  maxHeight: images.length == 1 ? 160 : 112,
                                  onTap: () => widget.onImageTap(index),
                                ),
                            ],
                          ),
                        ),
                      SizedBox(height: images.isEmpty ? 4 : 8),
                      Text(widget.age, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (deleteButton) ...[
                  const SizedBox(width: 8),
                  AnimatedOpacity(
                    opacity: _hovered || _focused ? 1 : 0,
                    duration: const Duration(milliseconds: 120),
                    alwaysIncludeSemantics: true,
                    child: IconButton(
                      tooltip: AppLocalizations.of(context).delete,
                      onPressed: widget.onDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ),
                ],
              ],
            ),
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
    final removeImage = AppLocalizations.of(context).removeImage;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final pasted in images)
          // Beside the image rather than over it: its width is 0 until decoded.
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: _ImageThumbnail(
                  image: pasted.image,
                  maxHeight: maxHeight,
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                tooltip: removeImage,
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
  const _ImageViewer({required this.images, required this.initialIndex});

  final List<ImageProvider> images;
  final int initialIndex;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  late var _index = widget.initialIndex;
  var _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _turn(int by) {
    final page = _index + by;
    if (page < 0 || page >= widget.images.length) return;
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final count = widget.images.length;
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
      },
      child: Focus(
        autofocus: true,
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _pages,
                // A zoomed image pans instead of turning the page.
                physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
                itemCount: count,
                onPageChanged: (index) => setState(() {
                  _index = index;
                  _zoomed = false;
                }),
                itemBuilder: (context, index) => GestureDetector(
                  onTap: close,
                  child: _ZoomableImage(
                    image: widget.images[index],
                    onZoomChanged: (zoomed) => setState(() => _zoomed = zoomed),
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
                    child: IconButton(
                      style: buttonStyle,
                      tooltip: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                      onPressed: close,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({required this.image, required this.onZoomChanged});

  final ImageProvider image;
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
    child: Image(
      image: widget.image,
      semanticLabel: AppLocalizations.of(context).imageLabel,
    ),
  );
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

typedef _Edit = ({String text, List<String> images});

class _EditDialog extends StatefulWidget {
  const _EditDialog({
    required this.store,
    required this.thought,
    required this.onDelete,
  });

  final ThoughtStore store;
  final Thought thought;
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
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final images = _images;
    final error = _error;
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(l10n.editTitle)),
          IconButton(
            tooltip: l10n.delete,
            onPressed: () {
              Navigator.pop(context);
              widget.onDelete();
            },
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
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
