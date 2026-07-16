import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/helix_isolate_compute.dart';

int _square(int value) => value * value;

void main() {
  test('P10 isolate compute returns result and reports progress', () async {
    final progress = <double>[];

    final result = await HelixIsolateCompute.run<int, int>(
      _square,
      7,
      onProgress: progress.add,
      debugLabel: 'phase10_square',
    );

    expect(result, equals(49));
    expect(progress, equals([0, 1]));
  });

  test('P10 isolate compute observes cancellation before dispatch', () async {
    final token = HelixCancellationToken()..cancel();

    expect(
      HelixIsolateCompute.run<int, int>(_square, 7, cancellationToken: token),
      throwsA(isA<HelixOperationCancelledException>()),
    );
  });
}
