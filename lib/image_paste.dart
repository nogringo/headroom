import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'clipboard_image_io.dart'
    if (dart.library.js_interop) 'clipboard_image_web.dart';
import 'l10n/app_localizations.dart';
import 'report_error.dart';
import 'thought_store.dart';

/// An image already saved in the store, ready to go in a thought.
typedef PastedImage = ({String name, ImageProvider image});

/// Lets the text field built by [builder] take pasted images, through
/// Cmd/Ctrl+V, "Paste image" in its context menu, and paste events on the web.
class ImagePaste extends StatefulWidget {
  const ImagePaste({
    super.key,
    required this.store,
    required this.focusNode,
    required this.onImage,
    required this.onError,
    required this.builder,
  });

  final ThoughtStore store;

  /// The field's focus node: web paste events only count while it has focus.
  final FocusNode focusNode;
  final ValueChanged<PastedImage> onImage;
  final ValueChanged<String> onError;

  /// Builds the field, which must use the given context menu builder.
  final Widget Function(EditableTextContextMenuBuilder contextMenuBuilder)
  builder;

  @override
  State<ImagePaste> createState() => _ImagePasteState();
}

class _ImagePasteState extends State<ImagePaste> {
  late final _pasteImageOrText = _PasteImageOrTextAction(_pasteImage);
  late final VoidCallback _stopListening;

  @override
  void initState() {
    super.initState();
    _stopListening = listenToPastedImages(
      accept: () => widget.focusNode.hasFocus,
      onImage: _attach,
    );
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  /// Returns whether the clipboard held an image. A failed read counts as
  /// none, so that Cmd/Ctrl+V falls back to pasting text.
  Future<bool> _pasteImage() async {
    Uint8List? bytes;
    try {
      bytes = await readClipboardImage();
    } catch (error, stack) {
      reportError(error, stack);
    }
    if (bytes == null) return false;
    await _attach(bytes);
    return true;
  }

  Future<void> _pasteImageFromMenu() async {
    final l10n = AppLocalizations.of(context);
    Uint8List? bytes;
    try {
      // No await before this call: browsers only read the clipboard inside
      // the click.
      bytes = await readClipboardImage();
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) widget.onError(l10n.imageNotAdded);
      return;
    }
    if (bytes == null) {
      if (mounted) widget.onError(l10n.noImageInClipboard);
      return;
    }
    await _attach(bytes);
  }

  Future<void> _attach(Uint8List bytes) async {
    try {
      final name = await widget.store.saveImage(bytes);
      if (mounted) widget.onImage((name: name, image: MemoryImage(bytes)));
    } catch (error, stack) {
      reportError(error, stack);
      if (mounted) widget.onError(AppLocalizations.of(context).imageNotAdded);
    }
  }

  Widget _buildContextMenu(
    BuildContext context,
    EditableTextState editableText,
  ) => AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableText.contextMenuAnchors,
    buttonItems: [
      ...editableText.contextMenuButtonItems,
      ContextMenuButtonItem(
        label: AppLocalizations.of(context).pasteImage,
        onPressed: () {
          editableText.hideToolbar();
          _pasteImageFromMenu();
        },
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Actions(
    actions: {PasteTextIntent: _pasteImageOrText},
    child: widget.builder(_buildContextMenu),
  );
}

/// Pastes the clipboard's image when it holds no text, its text otherwise.
///
/// Text wins because apps such as Word also put a picture of copied text on
/// the clipboard. The context menu's "Paste image" reaches the image anyway.
class _PasteImageOrTextAction extends Action<PasteTextIntent> {
  _PasteImageOrTextAction(this.pasteImage);

  final Future<bool> Function() pasteImage;

  @override
  Future<void> invoke(PasteTextIntent intent) async {
    // Only set while this call runs synchronously.
    final pasteText = callingAction;
    if (await Clipboard.hasStrings() || !await pasteImage()) {
      pasteText?.invoke(intent);
    }
  }
}
