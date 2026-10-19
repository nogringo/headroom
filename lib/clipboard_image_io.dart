import 'package:flutter/foundation.dart';
import 'package:pasteboard/pasteboard.dart';

Future<Uint8List?> readClipboardImage() => Pasteboard.image;

/// Only the web delivers images through paste events. Elsewhere, call
/// [readClipboardImage] when the user pastes.
VoidCallback listenToPastedImages({
  required bool Function() accept,
  required ValueChanged<Uint8List> onImage,
}) => () {};
