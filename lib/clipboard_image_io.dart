import 'package:flutter/foundation.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:quill_native_bridge/quill_native_bridge.dart';

Future<Uint8List?> readClipboardImage() => Pasteboard.image;

/// Only the web delivers images through paste events. Elsewhere, call
/// [readClipboardImage] when the user pastes.
VoidCallback listenToPastedImages({
  required bool Function() accept,
  required ValueChanged<Uint8List> onImage,
}) => () {};

/// Only the web delivers HTML through paste events. Elsewhere, call
/// [clipboardHtml] when the user pastes.
VoidCallback listenToPastedHtml({
  required bool Function() accept,
  required bool Function(String html) onHtml,
}) => () {};

/// Tests replace this, as the bridge reaches the clipboard without a channel
/// to mock.
@visibleForTesting
Future<String?> Function() readClipboardHtml = () async {
  final bridge = QuillNativeBridge();
  if (!await bridge.isSupported(QuillNativeBridgeFeature.getClipboardHtml)) {
    return null;
  }
  return bridge.getClipboardHtml();
};

Future<String?> clipboardHtml() => readClipboardHtml();

/// The pasteboard plugin cannot write images on Linux.
bool get canCopyImages => defaultTargetPlatform != TargetPlatform.linux;

/// Tests replace this: the plugin picks its code path from the host OS, so
/// on a Linux CI runner it would never reach a mocked channel.
@visibleForTesting
Future<void> Function(Uint8List image) writeClipboardImage =
    Pasteboard.writeImage;

Future<void> copyImage(Future<Uint8List> bytes) async =>
    writeClipboardImage(await bytes);
