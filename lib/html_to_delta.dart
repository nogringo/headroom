import 'package:flutter_quill/quill_delta.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// Reads pasted [source] into the formatting a thought keeps: bold, italic,
/// underline, strikethrough, inline code, links, headings, lists, quotes and
/// code blocks. Its colors, fonts, sizes and images are left out.
///
/// The last line only ends with a line break when it is a list item, a
/// heading or the like, so that a few pasted words stay in the line.
Delta deltaFromHtml(String source) {
  final reader = _Reader();
  final body = html.parse(source).body;
  if (body != null) reader.read(body, const {}, const {});
  return reader.finish();
}

const _skipped = {
  'head',
  'script',
  'style',
  'template',
  'noscript',
  'title',
  'meta',
  'img',
  'svg',
  'video',
  'audio',
  'iframe',
  'object',
};

const _blocks = {
  'address',
  'article',
  'aside',
  'blockquote',
  'dd',
  'details',
  'div',
  'dl',
  'dt',
  'figcaption',
  'figure',
  'footer',
  'form',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hr',
  'li',
  'main',
  'nav',
  'ol',
  'p',
  'pre',
  'section',
  'summary',
  'table',
  'tbody',
  'td',
  'tfoot',
  'th',
  'thead',
  'tr',
  'ul',
};

typedef _Attributes = Map<String, Object>;

class _Reader {
  final _delta = Delta();
  final _line = <({String text, _Attributes inline})>[];

  /// Whether a space ends what [_line] holds, or it holds nothing yet.
  var _spaced = true;

  /// The kind of list ('bullet' or 'ordered') of each list the reader is in.
  final _lists = <String>[];

  void read(dom.Element element, _Attributes inline, _Attributes block) {
    for (final node in element.nodes) {
      switch (node) {
        case dom.Text(:final data):
          _write(data, inline, block);
        case dom.Element(:final localName?):
          _readElement(node, localName, inline, block);
      }
    }
  }

  void _readElement(
    dom.Element element,
    String name,
    _Attributes inline,
    _Attributes block,
  ) {
    if (_skipped.contains(name)) return;
    if (name == 'br') {
      _endLine(block, empty: true);
      return;
    }
    final style = element.attributes['style'] ?? '';
    final inner = {...inline};
    void mark(String key, bool? on) {
      if (on == true) inner[key] = true;
      if (on == false) inner.remove(key);
    }

    mark('bold', const {'b', 'strong', 'th'}.contains(name) ? true : null);
    mark('bold', _fontWeight(style));
    mark(
      'italic',
      const {'i', 'em', 'cite', 'var'}.contains(name) ? true : null,
    );
    mark('italic', _fontStyle(style));
    mark('underline', name == 'u' || name == 'ins' ? true : null);
    mark('strike', const {'s', 'strike', 'del'}.contains(name) ? true : null);
    if (RegExp(r'text-decoration[^;]*underline').hasMatch(style)) {
      inner['underline'] = true;
    }
    if (RegExp(r'text-decoration[^;]*line-through').hasMatch(style)) {
      inner['strike'] = true;
    }
    if (const {'code', 'kbd', 'samp'}.contains(name) &&
        block['code-block'] == null) {
      inner['code'] = true;
    }
    final href = name == 'a' ? element.attributes['href'] : null;
    if (href != null && href.isNotEmpty && !href.startsWith('javascript:')) {
      inner['link'] = href;
    }

    if (!_blocks.contains(name)) {
      if (name == 'input' && element.attributes['type'] == 'checkbox') {
        // A task list item's box, which [block] already says.
        return;
      }
      read(element, inner, block);
      return;
    }

    _endLine(block);
    final inside = switch (name) {
      'ul' || 'ol' => block,
      'li' => _listItem(element, block),
      'blockquote' => {...block, 'blockquote': true},
      'pre' => {...block, 'code-block': true},
      _ when name.length == 2 && name.startsWith('h') => {
        ...block,
        'header': int.tryParse(name.substring(1)) ?? 1,
      },
      _ => block,
    };
    if (name == 'ul' || name == 'ol') {
      _lists.add(name == 'ol' ? 'ordered' : 'bullet');
    }
    read(element, inner, inside);
    if (name == 'ul' || name == 'ol') _lists.removeLast();
    _endLine(inside);
  }

  _Attributes _listItem(dom.Element item, _Attributes block) {
    final checkbox = item.querySelector('input[type=checkbox]');
    final checked =
        _checked(item) ??
        _checked(item.parent) ??
        checkbox?.attributes.containsKey('checked');
    final depth = _lists.length - 1;
    return {
      for (final entry in block.entries)
        if (entry.key != 'list' && entry.key != 'indent')
          entry.key: entry.value,
      'list': switch (checked) {
        true => 'checked',
        false => 'unchecked',
        null => _lists.lastOrNull ?? 'bullet',
      },
      if (depth > 0) 'indent': depth,
    };
  }

  /// Read from Quill's own HTML, `data-checked`, or a class such as
  /// "checked" on the item.
  bool? _checked(dom.Element? element) {
    if (element == null) return null;
    switch (element.attributes['data-checked']) {
      case 'true':
        return true;
      case 'false':
        return false;
    }
    final classes = element.classes;
    if (classes.contains('checked') || classes.contains('done')) return true;
    if (classes.contains('unchecked') ||
        classes.contains('todo') ||
        classes.contains('checklist')) {
      return false;
    }
    return null;
  }

  void _write(String data, _Attributes inline, _Attributes block) {
    if (block['code-block'] != null) {
      final lines = data.split('\n');
      for (final (index, line) in lines.indexed) {
        if (index > 0) _endLine(block, empty: true);
        if (line.isNotEmpty) _append(line, inline);
      }
      return;
    }
    var text = data.replaceAll(RegExp(r'[ \t\n\r\f]+'), ' ');
    text = text.replaceAll(' ', ' ');
    if (_spaced && text.startsWith(' ')) text = text.substring(1);
    if (text.isEmpty) return;
    _append(text, inline);
  }

  void _append(String text, _Attributes inline) {
    _line.add((text: text, inline: inline));
    _spaced = text.endsWith(' ');
  }

  /// Ends the line, as [block] formats it, if it holds anything. [empty]
  /// ends it even then, as a `<br>` does.
  void _endLine(_Attributes block, {bool empty = false}) {
    if (_line.isEmpty && !empty) return;
    _flush();
    _delta.insert('\n', block.isEmpty ? null : {...block});
  }

  /// Moves [_line] to the delta, without the space it ends with.
  void _flush() {
    if (_line case [..., final last] when last.text.endsWith(' ')) {
      final trimmed = last.text.trimRight();
      _line.removeLast();
      if (trimmed.isNotEmpty) _line.add((text: trimmed, inline: last.inline));
    }
    for (final run in _line) {
      _delta.insert(run.text, run.inline.isEmpty ? null : {...run.inline});
    }
    _line.clear();
    _spaced = true;
  }

  Delta finish() {
    _flush();
    // A plain line break at the end would split the line pasted into.
    if (_delta.isEmpty) return _delta;
    final last = _delta.last;
    if (last.attributes == null && '${last.data}'.endsWith('\n')) {
      return _delta.slice(0, lengthOf(_delta) - 1);
    }
    return _delta;
  }
}

/// The number of characters [delta] inserts.
int lengthOf(Delta delta) =>
    delta.toList().fold(0, (sum, operation) => sum + operation.length!);

/// True for bold, false for a weight that undoes it, as Google Docs wraps
/// what it copies in.
bool? _fontWeight(String style) {
  final weight = RegExp(r'font-weight\s*:\s*([a-z0-9]+)')
      .firstMatch(style)
      ?.group(1);
  return switch (weight) {
    null => null,
    'bold' || 'bolder' => true,
    'normal' || 'lighter' => false,
    _ => (int.tryParse(weight) ?? 400) >= 600,
  };
}

bool? _fontStyle(String style) =>
    switch (RegExp(r'font-style\s*:\s*([a-z]+)').firstMatch(style)?.group(1)) {
      null => null,
      'italic' || 'oblique' => true,
      _ => false,
    };
