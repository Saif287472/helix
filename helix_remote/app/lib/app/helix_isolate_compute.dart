import 'dart:async';

import 'package:flutter/foundation.dart';

class HelixCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }

  void throwIfCancelled() {
    if (_cancelled) {
      throw const HelixOperationCancelledException();
    }
  }
}

class HelixOperationCancelledException implements Exception {
  const HelixOperationCancelledException();

  @override
  String toString() => 'HelixOperationCancelledException';
}

typedef HelixProgressCallback = void Function(double progress);

final class HelixIsolateCompute {
  const HelixIsolateCompute._();

  static Future<R> run<Q, R>(
    FutureOr<R> Function(Q message) task,
    Q message, {
    HelixCancellationToken? cancellationToken,
    HelixProgressCallback? onProgress,
    String? debugLabel,
  }) async {
    cancellationToken?.throwIfCancelled();
    onProgress?.call(0);
    final result = await compute<Q, R>(task, message, debugLabel: debugLabel);
    cancellationToken?.throwIfCancelled();
    onProgress?.call(1);
    return result;
  }

  static Future<Duration> benchmark<Q, R>(
    FutureOr<R> Function(Q message) task,
    Q message, {
    String? debugLabel,
  }) async {
    final stopwatch = Stopwatch()..start();
    await run(task, message, debugLabel: debugLabel);
    stopwatch.stop();
    return stopwatch.elapsed;
  }
}
