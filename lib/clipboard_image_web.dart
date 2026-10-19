import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Browsers only hand clipboard images to paste events, see
/// [listenToPastedImages].
Future<Uint8List?> readClipboardImage() async => null;

/// Calls [onImage] when an image is pasted and [accept] returns true.
/// Returns a function that stops listening.
VoidCallback listenToPastedImages({
  required bool Function() accept,
  required ValueChanged<Uint8List> onImage,
}) {
  final listener = ((web.ClipboardEvent event) {
    final file = _imageIn(event.clipboardData);
    if (file == null || !accept()) return;
    // Otherwise the browser also pastes the image's text alternative, if any.
    event.preventDefault();
    file.arrayBuffer().toDart.then(
      (buffer) => onImage(buffer.toDart.asUint8List()),
    );
  }).toJS;
  web.document.addEventListener('paste', listener);
  return () => web.document.removeEventListener('paste', listener);
}

web.File? _imageIn(web.DataTransfer? data) {
  // Text wins, as on other platforms: apps such as Word also put a picture of
  // copied text on the clipboard.
  if (data == null || data.getData('text/plain').isNotEmpty) return null;
  for (var i = 0; i < data.items.length; i++) {
    final item = data.items[i];
    if (item.kind == 'file' && item.type.startsWith('image/')) {
      return item.getAsFile();
    }
  }
  return null;
}
