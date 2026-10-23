import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/html_to_delta.dart';

List<Map<String, dynamic>> read(String html) => deltaFromHtml(html).toJson();

void main() {
  test('keeps the bold and the list of a note', () {
    expect(
      read(
        '<meta charset="UTF-8"><div><b>Shopping</b> for Saturday</div>'
        '<ul><li>bread</li><li><b>tomatoes</b></li></ul><div>done</div>',
      ),
      [
        {
          'insert': 'Shopping',
          'attributes': {'bold': true},
        },
        {'insert': ' for Saturday\nbread'},
        {
          'insert': '\n',
          'attributes': {'list': 'bullet'},
        },
        {
          'insert': 'tomatoes',
          'attributes': {'bold': true},
        },
        {
          'insert': '\n',
          'attributes': {'list': 'bullet'},
        },
        {'insert': 'done'},
      ],
    );
  });

  test('leaves out colors, fonts and the line break after a few words', () {
    expect(
      read(
        '<span style="color: rgb(0, 0, 0); font-family: Arial; '
        'font-size: 16px">a <b>bold</b> word</span>',
      ),
      [
        {'insert': 'a '},
        {
          'insert': 'bold',
          'attributes': {'bold': true},
        },
        {'insert': ' word'},
      ],
    );
  });

  test('puts paragraphs and nested blocks on their own lines', () {
    expect(read('<p>one</p><p>two</p>'), [
      {'insert': 'one\ntwo'},
    ]);
    expect(read('<div><div>one</div><div>two</div></div><p>three</p>'), [
      {'insert': 'one\ntwo\nthree'},
    ]);
    expect(read('<div>one<br>two</div><div><br></div><div>three</div>'), [
      {'insert': 'one\ntwo\n\nthree'},
    ]);
  });

  test('collapses the white space of the markup', () {
    expect(
      read('<div>\n  one   <i> two </i>\n three  </div>\n<div>four</div>'),
      [
        {'insert': 'one '},
        {
          'insert': 'two ',
          'attributes': {'italic': true},
        },
        {'insert': 'three\nfour'},
      ],
    );
  });

  test('undoes the bold Google Docs wraps what it copies in', () {
    expect(
      read(
        '<b style="font-weight:normal;" id="docs-internal-guid-1">'
        '<p dir="ltr"><span style="font-weight:700;">Bold</span>'
        '<span> rest</span></p>'
        '<ul><li dir="ltr"><p dir="ltr"><span>item</span></p></li></ul></b>',
      ),
      [
        {
          'insert': 'Bold',
          'attributes': {'bold': true},
        },
        {'insert': ' rest\nitem'},
        {
          'insert': '\n',
          'attributes': {'list': 'bullet'},
        },
      ],
    );
  });

  test('numbers ordered lists and indents nested ones', () {
    expect(read('<ol><li>one<ul><li>sub</li></ul></li><li>two</li></ol>'), [
      {'insert': 'one'},
      {
        'insert': '\n',
        'attributes': {'list': 'ordered'},
      },
      {'insert': 'sub'},
      {
        'insert': '\n',
        'attributes': {'list': 'bullet', 'indent': 1},
      },
      {'insert': 'two'},
      {
        'insert': '\n',
        'attributes': {'list': 'ordered'},
      },
    ]);
  });

  test('ticks off the items of a checklist', () {
    expect(
      read(
        '<ul data-checked="true"><li>done</li></ul>'
        '<ul><li><input type="checkbox"> to do</li></ul>',
      ),
      [
        {'insert': 'done'},
        {
          'insert': '\n',
          'attributes': {'list': 'checked'},
        },
        {'insert': 'to do'},
        {
          'insert': '\n',
          'attributes': {'list': 'unchecked'},
        },
      ],
    );
  });

  test('keeps links, headings and code, but no images', () {
    expect(
      read(
        '<h2>Title</h2><p>see <a href="https://example.com">this</a>'
        '<img src="https://example.com/a.png"> <code>x</code></p>'
        '<pre>a\n  b</pre>',
      ),
      [
        {'insert': 'Title'},
        {
          'insert': '\n',
          'attributes': {'header': 2},
        },
        {'insert': 'see '},
        {
          'insert': 'this',
          'attributes': {'link': 'https://example.com'},
        },
        {'insert': ' '},
        {
          'insert': 'x',
          'attributes': {'code': true},
        },
        {'insert': '\na'},
        {
          'insert': '\n',
          'attributes': {'code-block': true},
        },
        {'insert': '  b'},
        {
          'insert': '\n',
          'attributes': {'code-block': true},
        },
      ],
    );
  });

  test('reads nothing from markup without text', () {
    expect(read('<img src="https://example.com/a.png">'), isEmpty);
    expect(read('<style>p { margin: 0 }</style>'), isEmpty);
  });
}
