import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/location/live_location_service.dart';
import 'package:helix_remote/core/platform/location_source.dart';

import 'support/chat_harness.dart';
import 'support/location_fakes.dart';

/// Sending a place, and the live shares kept running while the app lives.
void main() {
  late TestChatGateway gateway;
  late FakeLocationSource phone;
  late DateTime clock;
  late LiveLocationService service;
  late String chat;

  setUp(() async {
    gateway = await TestChatGateway.create();
    chat = await gateway.chatWith('bob', name: 'Bob');
    phone = FakeLocationSource();
    clock = testNow;
    service = LiveLocationService(
      gateway: () async => gateway,
      source: phone,
      now: () => clock,
    );
  });
  tearDown(() async {
    service.dispose();
    await gateway.close();
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  LocationFix at(int lat) =>
      LocationFix(latE7: lat, lngE7: 903560000, accuracyM: 5);

  test('sending once sends the place and starts no share', () async {
    expect(await service.sendOnce(chat), isNull);
    expect(gateway.log.last, startsWith('sendLocation:$chat'));
    expect(phone.tracking, isFalse);
    expect(service.running, isEmpty);
  });

  test('a phone that will not say where it is sends nothing', () async {
    phone.granted = LocationAccess.denied;
    expect(await service.sendOnce(chat), contains('Allow location access'));
    phone.granted = LocationAccess.serviceOff;
    expect(
      await service.startLive(chat, const Duration(hours: 1)),
      contains('Turn on location'),
    );
    phone.granted = LocationAccess.granted;
    phone.here = null;
    expect(await service.sendOnce(chat), contains('could not be found'));
    expect(gateway.log.where((l) => l.startsWith('send')), isEmpty);
    expect(gateway.log.where((l) => l.startsWith('startLive')), isEmpty);
  });

  test(
    'a live share follows the phone, no faster than every 10 seconds',
    () async {
      expect(
        await service.startLive(chat, const Duration(minutes: 15)),
        isNull,
      );
      expect(phone.tracking, isTrue);
      expect(service.running, hasLength(1));

      clock = clock.add(const Duration(seconds: 12));
      phone.move(at(236820000));
      await settle();
      clock = clock.add(const Duration(seconds: 3));
      phone.move(at(236830000));
      await settle();
      clock = clock.add(const Duration(seconds: 11));
      phone.move(at(236840000));
      await settle();

      final updates = gateway.log.where((l) => l.startsWith('updateLive'));
      expect(updates, hasLength(2));
      expect(updates.last, endsWith('236840000,903560000'));
    },
  );

  test('stopping tells the chat and closes the position stream', () async {
    await service.startLive(chat, const Duration(hours: 1));
    final rowid = service.running.single;
    await service.stop(rowid);
    expect(gateway.log, contains('stopLive:$rowid'));
    expect(service.running, isEmpty);
    await settle();
    expect(phone.tracking, isFalse);
  });

  test('a share whose time is up is dropped at the next reading', () async {
    await service.startLive(chat, const Duration(minutes: 15));
    clock = clock.add(const Duration(minutes: 16));
    phone.move(at(236820000));
    await settle();
    expect(service.running, isEmpty);
    expect(gateway.log.where((l) => l.startsWith('updateLive')), isEmpty);
    expect(phone.tracking, isFalse);
  });

  test('two shares use one stream, which stays until the last ends', () async {
    final other = await gateway.chatWith('cara', name: 'Cara');
    await service.startLive(chat, const Duration(hours: 1));
    await service.startLive(other, const Duration(hours: 8));
    clock = clock.add(const Duration(seconds: 20));
    phone.move(at(236820000));
    await settle();
    expect(gateway.log.where((l) => l.startsWith('updateLive')), hasLength(2));

    final first = service.running.first;
    await service.stop(first);
    await settle();
    expect(phone.tracking, isTrue);
    await service.stop(service.running.single);
    await settle();
    expect(phone.tracking, isFalse);
  });

  test('after a restart the shares carry on, without asking again', () async {
    await service.startLive(chat, const Duration(hours: 1));
    service.dispose();

    final again = LiveLocationService(
      gateway: () async => gateway,
      source: phone,
      now: () => clock,
    );
    addTearDown(again.dispose);
    final asked = phone.asked;
    await again.resume();
    expect(again.running, hasLength(1));
    expect(phone.tracking, isTrue);
    expect(phone.asked, asked, reason: 'resuming never shows the prompt');
  });

  test('without permission nothing carries on after a restart', () async {
    await service.startLive(chat, const Duration(hours: 1));
    service.dispose();
    phone.granted = LocationAccess.denied;
    final again = LiveLocationService(
      gateway: () async => gateway,
      source: phone,
      now: () => clock,
    );
    addTearDown(again.dispose);
    await again.resume();
    expect(again.running, isEmpty);
    expect(phone.tracking, isFalse);
  });
}
