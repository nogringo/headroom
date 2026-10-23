import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/formatting.dart';

void main() {
  test('keeps plain text without formatting', () {
    final content = contentOf(documentOf('  Buy bread\nAnd milk \n\n', []));

    expect(content.text, 'Buy bread\nAnd milk');
    expect(content.delta, isEmpty);
  });

  test('keeps formatting, without the blanks around the text', () {
    final document = Document.fromJson([
      {'insert': '\n  '},
      {
        'insert': 'Bread',
        'attributes': {'bold': true},
      },
      {'insert': ' and milk  \n\n'},
    ]);

    final content = contentOf(document);

    expect(content.text, 'Bread and milk');
    expect(content.delta, [
      {
        'insert': 'Bread',
        'attributes': {'bold': true},
      },
      {'insert': ' and milk\n'},
    ]);
    expect(
      contentOf(documentOf(content.text, content.delta)).delta,
      content.delta,
    );
  });

  test('keeps the list its last line is in', () {
    final document = Document.fromJson([
      {'insert': 'Bread'},
      {
        'insert': '\n',
        'attributes': {'list': 'bullet'},
      },
      {'insert': '\n'},
    ]);

    expect(contentOf(document).delta, [
      {'insert': 'Bread'},
      {
        'insert': '\n',
        'attributes': {'list': 'bullet'},
      },
    ]);
  });

  test('marks list items in its text as Markdown does', () {
    final document = Document.fromJson([
      {'insert': 'Errands\nBread'},
      {
        'insert': '\n',
        'attributes': {'list': 'bullet'},
      },
      {'insert': 'Wholemeal'},
      {
        'insert': '\n',
        'attributes': {'list': 'bullet', 'indent': 1},
      },
      {'insert': 'Call'},
      {
        'insert': '\n',
        'attributes': {'list': 'ordered'},
      },
      {'insert': 'Pay'},
      {
        'insert': '\n',
        'attributes': {'list': 'ordered'},
      },
      {'insert': 'Garage'},
      {
        'insert': '\n',
        'attributes': {'list': 'checked'},
      },
      {'insert': 'Tyres'},
      {
        'insert': '\n',
        'attributes': {'list': 'unchecked'},
      },
      {'insert': 'Then\nFirst'},
      {
        'insert': '\n',
        'attributes': {'list': 'ordered'},
      },
    ]);

    expect(
      contentOf(document).text,
      'Errands\n'
      '- Bread\n'
      '  - Wholemeal\n'
      '1. Call\n'
      '2. Pay\n'
      '- [x] Garage\n'
      '- [ ] Tyres\n'
      'Then\n'
      '1. First',
    );
  });

  test('reads blank documents as empty', () {
    final content = contentOf(documentOf(' \n ', []));

    expect(content.text, isEmpty);
    expect(content.delta, isEmpty);
  });

  test('pastes HTML over the selection', () {
    final controller = thoughtController(text: 'Buy  today')
      ..updateSelection(
        const TextSelection.collapsed(offset: 4),
        ChangeSource.local,
      );
    addTearDown(controller.dispose);

    expect(pasteHtml(controller, '<b>bread</b>'), isTrue);
    expect(controller.document.toDelta().toJson(), [
      {'insert': 'Buy '},
      {
        'insert': 'bread',
        'attributes': {'bold': true},
      },
      {'insert': ' today\n'},
    ]);
    expect(controller.selection, const TextSelection.collapsed(offset: 9));

    expect(pasteHtml(controller, '<img src="a.png">'), isFalse);
  });
}
