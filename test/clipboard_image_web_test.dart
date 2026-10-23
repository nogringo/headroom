@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:headroom/clipboard_image_web.dart';
import 'package:web/web.dart' as web;

void main() {
  final bytes = Uint8List.fromList([137, 80, 78, 71]);
  var accept = true;
  late StreamController<Uint8List> pasted;
  late VoidCallback stop;

  setUp(() {
    accept = true;
    pasted = StreamController();
    stop = listenToPastedImages(accept: () => accept, onImage: pasted.add);
  });

  tearDown(() {
    stop();
    pasted.close();
  });

  web.ClipboardEvent paste({bool image = true, String? text, String? html}) {
    final data = web.DataTransfer();
    if (image) {
      data.items.add(
        web.File(
          [bytes.toJS].toJS,
          'shot.png',
          web.FilePropertyBag(type: 'image/png'),
        ),
      );
    }
    if (text != null) data.setData('text/plain', text);
    if (html != null) data.setData('text/html', html);
    final event = web.ClipboardEvent(
      'paste',
      web.ClipboardEventInit(clipboardData: data, cancelable: true),
    );
    web.document.dispatchEvent(event);
    return event;
  }

  test('takes a pasted image and keeps the browser from pasting', () async {
    final event = paste();

    expect(event.defaultPrevented, isTrue);
    expect(await pasted.stream.first, bytes);
  });

  test('leaves the paste to the browser when it has text', () {
    expect(paste(text: 'Copied from Word').defaultPrevented, isFalse);
  });

  test('leaves the paste to the browser when not accepted', () {
    accept = false;
    expect(paste().defaultPrevented, isFalse);
  });

  test('stops listening', () {
    stop();
    expect(paste().defaultPrevented, isFalse);
  });

  group('HTML', () {
    final pastedHtml = <String>[];
    var hasText = true;
    late VoidCallback stopHtml;

    setUp(() {
      pastedHtml.clear();
      hasText = true;
      stopHtml = listenToPastedHtml(
        accept: () => accept,
        onHtml: (html) {
          pastedHtml.add(html);
          return hasText;
        },
      );
    });

    tearDown(() => stopHtml());

    test('takes the HTML pasted with text', () {
      final event = paste(image: false, text: 'Bread', html: '<b>Bread</b>');

      expect(event.defaultPrevented, isTrue);
      expect(pastedHtml, ['<b>Bread</b>']);
    });

    test('leaves the paste to the browser when the HTML has no text', () {
      hasText = false;

      expect(
        paste(image: false, text: 'a.png', html: '<img>').defaultPrevented,
        isFalse,
      );
    });

    test('leaves an image pasted with an <img> to the image', () async {
      paste(html: '<img src="a.png">');

      expect(await pasted.stream.first, bytes);
      expect(pastedHtml, isEmpty);
    });

    test('leaves the paste to the browser when not accepted', () {
      accept = false;

      expect(
        paste(
          image: false,
          text: 'Bread',
          html: '<b>Bread</b>',
        ).defaultPrevented,
        isFalse,
      );
      expect(pastedHtml, isEmpty);
    });
  });
}
