abstract class MulticastLock {
  Future<void> acquire();
  Future<void> release();
}
