import 'dart:async';

/// The latest value of [a] and [b], combined, once both have emitted. Errors
/// of either are passed on; the result closes when both have.
///
/// A small stand-in for rxdart's `combineLatest2`, for the few places that
/// join two drift watch queries (a message's attachment rows and their
/// transfer state, say) without a dependency for it.
Stream<R> combineLatest2<A, B, R>(
  Stream<A> a,
  Stream<B> b,
  R Function(A a, B b) combine,
) {
  late final StreamController<R> controller;
  StreamSubscription<A>? subscriptionA;
  StreamSubscription<B>? subscriptionB;
  A? latestA;
  B? latestB;
  var hasA = false;
  var hasB = false;
  var doneA = false;
  var doneB = false;

  void emit() {
    if (hasA && hasB && !controller.isClosed) {
      controller.add(combine(latestA as A, latestB as B));
    }
  }

  void maybeClose() {
    if (doneA && doneB && !controller.isClosed) unawaited(controller.close());
  }

  controller = StreamController<R>(
    onListen: () {
      subscriptionA = a.listen(
        (value) {
          latestA = value;
          hasA = true;
          emit();
        },
        onError: controller.addError,
        onDone: () {
          doneA = true;
          maybeClose();
        },
      );
      subscriptionB = b.listen(
        (value) {
          latestB = value;
          hasB = true;
          emit();
        },
        onError: controller.addError,
        onDone: () {
          doneB = true;
          maybeClose();
        },
      );
    },
    onCancel: () async {
      await subscriptionA?.cancel();
      await subscriptionB?.cancel();
    },
  );
  return controller.stream;
}
