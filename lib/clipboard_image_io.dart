import 'package:flutter/foundation.dart';
import 'package:pasteboard/pasteboard.dart';

Future<Uint8List?> readClipboardImage() => Pasteboard.image;

/// Only the web delivers images through paste events. Elsewhere, call
/// [readClipboardImage] when the user pastes.
VoidCallback listenToPastedImages({
  required bool Function() accept,
  required ValueChanged<Uint8List> onImage,
}) => () {};

/// The pasteboard plugin cannot write images on Linux.
bool get canCopyImages => defaultTargetPlatform != TargetPlatform.linux;

/// Tests replace this: the plugin picks its code path from the host OS, so
/// on a Linux CI runner it would never reach a mocked channel.
@visibleForTesting
Future<void> Function(Uint8List image) writeClipboardImage =
    Pasteboard.writeImage;

Future<void> copyImage(Future<Uint8List> bytes) async =>
    writeClipboardImage(await bytes);
