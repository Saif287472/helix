import 'package:flutter/services.dart';
import 'package:helix_groups/platform/multicast_lock.dart';

class MulticastLockAndroid implements MulticastLock {
  static const _channel = MethodChannel('com.helix.app/multicast_lock');

  @override
  Future<void> acquire() => _channel.invokeMethod<void>('acquire');

  @override
  Future<void> release() => _channel.invokeMethod<void>('release');
}
