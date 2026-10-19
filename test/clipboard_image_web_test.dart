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

  web.ClipboardEvent paste({bool image = true, String? text}) {
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
}
