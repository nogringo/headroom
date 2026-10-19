import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'thought.dart';
import 'thought_storage.dart';

Future<ThoughtStorage> openThoughtStorage() async => WebThoughtStorage();

const _images = 'images';

/// Thoughts live in localStorage. Images live in IndexedDB, since
/// localStorage holds about 5 MB.
class WebThoughtStorage implements ThoughtStorage {
  WebThoughtStorage({
    this.key = 'headroom.thoughts',
    this.database = 'headroom',
  });

  final String key;
  final String database;
  Future<web.IDBDatabase>? _opened;

  Future<web.IDBDatabase> get _db => _opened ??= _open();

  Future<web.IDBDatabase> _open() {
    final request = web.window.indexedDB.open(database, 1);
    request.onupgradeneeded = ((web.Event _) {
      (request.result as web.IDBDatabase).createObjectStore(_images);
    }).toJS;
    return _result<web.IDBDatabase>(request);
  }

  @override
  Future<List<Thought>> read() async {
    final json = web.window.localStorage.getItem(key);
    return json == null ? [] : decodeThoughts(json);
  }

  @override
  Future<void> write(List<Thought> thoughts) async =>
      web.window.localStorage.setItem(key, encodeThoughts(thoughts));

  @override
  Future<String> saveImage(Uint8List bytes) async {
    final name = newImageName();
    final transaction = (await _db).transaction(_images.toJS, 'readwrite');
    transaction.objectStore(_images).put(bytes.toJS, name.toJS);
    await _completion(transaction);
    return name;
  }

  @override
  Future<Uint8List> readImage(String name) async {
    final request = (await _db)
        .transaction(_images.toJS)
        .objectStore(_images)
        .get(name.toJS);
    final bytes = await _result<JSUint8Array?>(request);
    if (bytes == null) throw StateError('No image named $name');
    return bytes.toDart;
  }

  @override
  Future<void> deleteImagesExcept(Set<String> keep) async {
    final db = await _db;
    final names = await _result<JSArray<JSString>>(
      db.transaction(_images.toJS).objectStore(_images).getAllKeys(),
    );
    final transaction = db.transaction(_images.toJS, 'readwrite');
    final images = transaction.objectStore(_images);
    for (final name in names.toDart) {
      if (!keep.contains(name.toDart)) images.delete(name);
    }
    await _completion(transaction);
  }
}

Future<T> _result<T extends JSAny?>(web.IDBRequest request) {
  final completer = Completer<T>();
  request.onsuccess = ((web.Event _) {
    completer.complete(request.result as T);
  }).toJS;
  request.onerror = ((web.Event _) {
    completer.completeError(request.error ?? StateError('IndexedDB failed'));
  }).toJS;
  return completer.future;
}

Future<void> _completion(web.IDBTransaction transaction) {
  final completer = Completer<void>();
  void fail(web.Event _) => completer.completeError(
    transaction.error ?? StateError('IndexedDB transaction failed'),
  );
  transaction.oncomplete = ((web.Event _) => completer.complete()).toJS;
  transaction.onerror = fail.toJS;
  transaction.onabort = fail.toJS;
  return completer.future;
}
