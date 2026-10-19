import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'thought_storage.dart';

class StoredImage extends ImageProvider<StoredImage> {
  const StoredImage(this.storage, this.name);

  final ThoughtStorage storage;
  final String name;

  @override
  Future<StoredImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    StoredImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _decode(decode),
    scale: 1,
    debugLabel: name,
  );

  Future<ui.Codec> _decode(ImageDecoderCallback decode) async => decode(
    await ui.ImmutableBuffer.fromUint8List(await storage.readImage(name)),
  );

  @override
  bool operator ==(Object other) =>
      other is StoredImage && other.storage == storage && other.name == name;

  @override
  int get hashCode => Object.hash(storage, name);
}
