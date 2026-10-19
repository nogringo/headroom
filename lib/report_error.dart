import 'package:flutter/foundation.dart';

void reportError(Object error, StackTrace stack) => FlutterError.reportError(
  FlutterErrorDetails(exception: error, stack: stack, library: 'headroom'),
);
