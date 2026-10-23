import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// For "Paste image" in the field's menu. Cmd/Ctrl+V goes through
/// [listenToPastedImages] instead, which needs no permission.
Future<Uint8List?> readClipboardImage() async {
  final items = await web.window.navigator.clipboard.read().toDart;
  for (final item in items.toDart) {
    for (final type in item.types.toDart.map((type) => type.toDart)) {
      if (!type.startsWith('image/')) continue;
      final blob = await item.getType(type).toDart;
      return (await blob.arrayBuffer().toDart).toDart.asUint8List();
    }
  }
  return null;
}

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

/// Calls [onHtml] with the HTML of a paste that has some, when [accept]
/// returns true. Once [onHtml] returns true, having pasted it, the browser
/// does not paste its plain text.
VoidCallback listenToPastedHtml({
  required bool Function() accept,
  required bool Function(String html) onHtml,
}) {
  final listener = ((web.ClipboardEvent event) {
    final data = event.clipboardData;
    // Only along with text: a copied image can come with an <img> alone.
    if (data == null || data.getData('text/plain').isEmpty || !accept()) {
      return;
    }
    final html = data.getData('text/html');
    if (html.isNotEmpty && onHtml(html)) event.preventDefault();
  }).toJS;
  web.document.addEventListener('paste', listener);
  return () => web.document.removeEventListener('paste', listener);
}

/// Pastes come through [listenToPastedHtml] instead, which needs no
/// permission.
Future<String?> clipboardHtml() async => null;

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

/// The clipboard API is missing outside secure contexts, such as plain http.
bool get canCopyImages =>
    web.window.navigator.has('clipboard') && globalContext.has('ClipboardItem');

/// Calls the browser right away, still inside the click as Safari requires,
/// with a promise of the PNG that browsers accept.
Future<void> copyImage(Future<Uint8List> bytes) async {
  final blob = bytes
      .then(_png)
      .then(
        (png) =>
            web.Blob([png.toJS].toJS, web.BlobPropertyBag(type: 'image/png')),
      );
  final item = web.ClipboardItem(JSObject()..['image/png'] = blob.toJS);
  await web.window.navigator.clipboard.write([item].toJS).toDart;
}

const _pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

Future<Uint8List> _png(Uint8List bytes) async {
  if (bytes.length >= 8 && listEquals(bytes.sublist(0, 8), _pngSignature)) {
    return bytes;
  }
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  codec.dispose();
  return png!.buffer.asUint8List();
}
