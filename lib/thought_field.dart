// Quill's Markdown shortcuts are experimental.
// ignore_for_file: experimental_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'clipboard_image_io.dart'
    if (dart.library.js_interop) 'clipboard_image_web.dart';
import 'formatting.dart';

/// Touch keyboards have a single key, kept for sending. On the web, the
/// platform is the browser's OS.
bool _shiftEnterBreaksLine(TargetPlatform platform) => switch (platform) {
  TargetPlatform.macOS ||
  TargetPlatform.windows ||
  TargetPlatform.linux => true,
  _ => false,
};

/// Where a thought is written, with its formatting. Enter, or the action key
/// of a touch keyboard, calls [onSubmit]. Shift+Enter starts a new line.
///
/// Markdown typed in it formats the text: `- ` starts a list, `**` bold.
class ThoughtField extends StatefulWidget {
  const ThoughtField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.style,
    required this.padding,
    required this.maxLines,
    required this.action,
    required this.onSubmit,
    required this.contextMenuBuilder,
    this.placeholder,
    this.placeholderStyle,
  });

  final QuillController controller;
  final FocusNode focusNode;

  /// What a screen reader calls it.
  final String label;
  final TextStyle style;
  final EdgeInsets padding;

  /// Past which it scrolls.
  final int maxLines;

  /// What the action key of a touch keyboard shows.
  final TextInputAction action;
  final VoidCallback onSubmit;
  final QuillEditorContextMenuBuilder contextMenuBuilder;

  /// Shown while it is empty.
  final String? placeholder;
  final TextStyle? placeholderStyle;

  @override
  State<ThoughtField> createState() => _ThoughtFieldState();
}

class _ThoughtFieldState extends State<ThoughtField> {
  final _editor = GlobalKey<EditorState>();
  final _scroll = ScrollController();
  late final VoidCallback _stopListening;

  @override
  void initState() {
    super.initState();
    _stopListening = listenToPastedHtml(
      accept: () => widget.focusNode.hasFocus,
      onHtml: (html) => pasteHtml(widget.controller, html),
    );
  }

  @override
  void dispose() {
    _stopListening();
    _scroll.dispose();
    super.dispose();
  }

  void _requestKeyboard() {
    if (_editor.currentState case final QuillRawEditorState editor) {
      editor.requestKeyboard();
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final editor = _editor.currentState;
    if (event is KeyUpEvent ||
        (key != LogicalKeyboardKey.enter &&
            key != LogicalKeyboardKey.numpadEnter) ||
        HardwareKeyboard.instance.isShiftPressed ||
        // An input method confirms its composition with Enter.
        (editor is QuillRawEditorState &&
            editor.composingRange.value.isValid)) {
      return KeyEventResult.ignored;
    }
    // Repeats are swallowed, or a held Enter would fill the emptied field
    // with line breaks.
    if (event is KeyDownEvent) widget.onSubmit();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final lineHeight = (style.fontSize ?? 16) * (style.height ?? 1.2);
    final shiftEnter = _shiftEnterBreaksLine(Theme.of(context).platform);
    final controller = widget.controller;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onKeyEvent: _handleKey,
      child: ListenableBuilder(
        listenable: Listenable.merge([controller, widget.focusNode]),
        // A text field, as the web, where semantics are always on, types in
        // the one the semantics tree holds.
        builder: (context, editor) => Semantics(
          container: true,
          excludeSemantics: true,
          textField: true,
          multiline: true,
          enabled: true,
          focused: widget.focusNode.hasFocus,
          label: widget.label,
          value: controller.document.toPlainText().trim(),
          onTap: _requestKeyboard,
          onFocus: _requestKeyboard,
          child: editor,
        ),
        child: QuillEditor(
          controller: controller,
          focusNode: widget.focusNode,
          scrollController: _scroll,
          config: QuillEditorConfig(
            editorKey: _editor,
            autoFocus: true,
            padding: widget.padding,
            maxHeight: widget.maxLines * lineHeight + widget.padding.vertical,
            placeholder: widget.placeholder,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: shiftEnter
                ? TextInputAction.newline
                : widget.action,
            onPerformAction: (action) {
              if (action == widget.action) widget.onSubmit();
            },
            contextMenuBuilder: widget.contextMenuBuilder,
            customStyles: thoughtStyles(
              style,
              placeholder: widget.placeholderStyle,
            ),
            characterShortcutEvents: standardCharactersShortcutEvents,
            spaceShortcutEvents: standardSpaceShorcutEvents,
          ),
        ),
      ),
    );
  }
}
