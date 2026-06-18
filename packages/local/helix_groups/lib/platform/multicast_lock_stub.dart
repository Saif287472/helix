import 'package:helix_groups/platform/multicast_lock.dart';

class MulticastLockStub implements MulticastLock {
  @override
  Future<void> acquire() async {}

  @override
  Future<void> release() async {}
}
