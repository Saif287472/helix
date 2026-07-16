import 'package:flutter/services.dart';
import 'package:helix_local_groups/platform/multicast_lock.dart';

class MulticastLockAndroid implements MulticastLock {
  final MethodChannel _channel;

  MulticastLockAndroid(String channelName)
    : _channel = MethodChannel(channelName);

  @override
  Future<void> acquire() => _channel.invokeMethod<void>('acquire');

  @override
  Future<void> release() => _channel.invokeMethod<void>('release');
}
