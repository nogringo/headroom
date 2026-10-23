// Quill's paste hooks, the only way into its pasting, are experimental.
// ignore_for_file: experimental_member_use

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import 'clipboard_image_io.dart'
    if (dart.library.js_interop) 'clipboard_image_web.dart';
import 'html_to_delta.dart';
import 'report_error.dart';

/// A thought's text as the editor holds it, from its [delta] when it has
/// formatting.
Document documentOf(String text, List<Map<String, dynamic>> delta) =>
    Document.fromJson(
      delta.isEmpty
          ? [
              {'insert': '$text\n'},
            ]
          : delta,
    );

/// What a thought keeps of [document], without the blanks around it: its
/// text, which marks list items as Markdown does for the AI and for copying,
/// and its formatting when it has some.
({String text, List<Map<String, dynamic>> delta}) contentOf(Document document) {
  final delta = document.toDelta();
  final all = delta.toList().map((op) => '${op.data}').join();
  final start = all.length - all.trimLeft().length;
  final end = all.trimRight().length;
  if (end <= start) return (text: '', delta: const []);
  // The line break that formats the last line, if it is a list item.
  final lineEnd = all.indexOf('\n', end);
  final trimmed = delta
      .slice(start, end)
      .concat(delta.slice(lineEnd, lineEnd + 1));
  final formatted = trimmed.toList().any((op) => op.attributes != null);
  return (
    text: _markdownText(trimmed),
    delta: formatted ? trimmed.toJson() : const [],
  );
}

String _markdownText(Delta delta) {
  final lines = <String>[];
  var line = StringBuffer();
  // How many items each level of the ordered list being read has so far.
  final counts = <int>[];
  for (final op in delta.toList()) {
    final parts = '${op.data}'.split('\n');
    for (final (index, part) in parts.indexed) {
      line.write(part);
      if (index == parts.length - 1) break;
      lines.add('${_marker(op.attributes, counts)}$line');
      line = StringBuffer();
    }
  }
  return lines.join('\n');
}

String _marker(Map<String, dynamic>? attributes, List<int> counts) {
  final list = attributes?['list'];
  if (list == null) {
    counts.clear();
    return '';
  }
  final depth = attributes?['indent'] as int? ?? 0;
  if (counts.length > depth + 1) counts.length = depth + 1;
  while (counts.length <= depth) {
    counts.add(0);
  }
  final pad = '  ' * depth;
  if (list == 'ordered') return '$pad${++counts[depth]}. ';
  counts[depth] = 0;
  return switch (list) {
    'checked' => '$pad- [x] ',
    'unchecked' => '$pad- [ ] ',
    _ => '$pad- ',
  };
}

/// For a field a thought is written in, from its [text] and [delta]. What
/// is pasted keeps the formatting [deltaFromHtml] reads.
QuillController thoughtController({
  String text = '',
  List<Map<String, dynamic>> delta = const [],
}) {
  final document = documentOf(text, delta);
  late final QuillController controller;
  controller = QuillController(
    document: document,
    selection: TextSelection.collapsed(offset: document.length - 1),
    config: QuillControllerConfig(
      clipboardConfig: QuillClipboardConfig(
        // Read here, as Quill's own conversion is deprecated and loses
        // paragraphs.
        enableExternalRichPaste: false,
        onClipboardPaste: () async {
          String? html;
          try {
            html = await clipboardHtml();
          } catch (error, stack) {
            // The text is pasted plain instead.
            reportError(error, stack);
          }
          return html != null && pasteHtml(controller, html);
        },
      ),
    ),
  );
  return controller;
}

/// Pastes [html] over the selection. Returns false, pasting nothing, when it
/// holds no text.
bool pasteHtml(QuillController controller, String html) {
  final pasted = deltaFromHtml(html);
  final selection = controller.selection;
  if (pasted.isEmpty || !selection.isValid) return false;
  controller
    ..replaceText(
      selection.start,
      selection.end - selection.start,
      pasted,
      null,
    )
    ..updateSelection(
      TextSelection.collapsed(offset: selection.start + lengthOf(pasted)),
      ChangeSource.local,
    );
  return true;
}

/// Quill's styles for a thought set in [style], headings a step larger.
DefaultStyles thoughtStyles(TextStyle style, {TextStyle? placeholder}) {
  final size = style.fontSize ?? 16;
  final ink = style.color ?? Colors.black;
  final code = style.copyWith(
    fontFamily: 'Menlo',
    fontFamilyFallback: const ['Consolas', 'monospace'],
    fontVariations: const [],
    fontSize: size * 0.85,
  );
  DefaultTextBlockStyle block(TextStyle style, [BoxDecoration? decoration]) =>
      DefaultTextBlockStyle(
        style,
        decoration == null
            ? HorizontalSpacing.zero
            : const HorizontalSpacing(12, 0),
        VerticalSpacing.zero,
        VerticalSpacing.zero,
        decoration,
      );
  DefaultTextBlockStyle heading(double scale) => block(
    style.copyWith(fontSize: size * scale, fontWeight: FontWeight.w700),
  );
  return DefaultStyles(
    paragraph: block(style),
    h1: heading(1.3),
    h2: heading(1.2),
    h3: heading(1.1),
    h4: heading(1),
    h5: heading(1),
    h6: heading(1),
    lists: DefaultListBlockStyle(
      style,
      HorizontalSpacing.zero,
      VerticalSpacing.zero,
      VerticalSpacing.zero,
      null,
      null,
      // Narrower than Quill's two ems, which suit its smaller text.
      numberPointWidthBuilder: _markerWidth,
      indentWidthBuilder: (block, context, count, markerWidth) {
        final attributes = block.style.attributes;
        final list = attributes[Attribute.list.key];
        if (list == null) {
          return TextBlockUtils.defaultIndentWidthBuilder(
            block,
            context,
            count,
            markerWidth,
          );
        }
        final indent = attributes[Attribute.indent.key]?.value as int? ?? 0;
        return HorizontalSpacing(
          markerWidth(size, list == Attribute.ol ? count : 1) + indent * size,
          0,
        );
      },
    ),
    leading: block(style),
    quote: block(
      style.copyWith(color: ink.withValues(alpha: 0.75)),
      BoxDecoration(
        border: BorderDirectional(
          start: BorderSide(width: 3, color: ink.withValues(alpha: 0.3)),
        ),
      ),
    ),
    code: block(
      code,
      BoxDecoration(
        color: ink.withValues(alpha: 0.06),
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
    ),
    inlineCode: InlineCodeStyle(
      style: code,
      backgroundColor: ink.withValues(alpha: 0.08),
      radius: const Radius.circular(3),
    ),
    link: const TextStyle(decoration: TextDecoration.underline),
    placeHolder: placeholder == null ? null : block(placeholder),
  );
}

/// Room for a list's bullet, or for its numbers up to [count].
double _markerWidth(double fontSize, int count) =>
    fontSize * 0.6 * ('$count'.length + 1);

/// A thought's formatted text, as its field shows it but read-only. Taps go
/// through to what holds it.
class FormattedText extends StatefulWidget {
  const FormattedText({
    super.key,
    required this.text,
    required this.delta,
    required this.style,
  });

  /// What a screen reader reads.
  final String text;
  final List<Map<String, dynamic>> delta;
  final TextStyle style;

  @override
  State<FormattedText> createState() => _FormattedTextState();
}

class _FormattedTextState extends State<FormattedText> {
  late final _controller = QuillController(
    document: Document.fromJson(widget.delta),
    selection: const TextSelection.collapsed(offset: 0),
    readOnly: true,
  );
  final _focus = FocusNode(canRequestFocus: false, skipTraversal: true);
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(FormattedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.delta, widget.delta)) {
      _controller.document = Document.fromJson(widget.delta);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.text,
    excludeSemantics: true,
    child: IgnorePointer(
      child: QuillEditor(
        controller: _controller,
        focusNode: _focus,
        scrollController: _scroll,
        config: QuillEditorConfig(
          scrollable: false,
          showCursor: false,
          enableInteractiveSelection: false,
          enableSelectionToolbar: false,
          customStyles: thoughtStyles(widget.style),
        ),
      ),
    ),
  );
}
