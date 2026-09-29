import 'dart:io';
import 'dart:typed_data';

import 'package:helix_remote_backend/src/turn_probe.dart';
import 'package:test/test.dart';

void main() {
  group('parseTurnTarget', () {
    test('reads host, port and transport', () {
      expect(parseTurnTarget('turn:relay.example:3478?transport=udp'), (
        host: 'relay.example',
        port: 3478,
        tcp: false,
      ));
      expect(parseTurnTarget('turn:relay.example:3479?transport=tcp'), (
        host: 'relay.example',
        port: 3479,
        tcp: true,
      ));
      expect(parseTurnTarget('turns:relay.example'), (
        host: 'relay.example',
        port: 5349,
        tcp: true,
      ));
      expect(parseTurnTarget('stun:relay.example'), isNull);
    });
  });

  group('TurnProbe', () {
    late RawDatagramSocket fakeRelay;

    /// A UDP socket answering every Binding Request with a Binding Success
    /// Response for the same transaction - what coturn does.
    Future<void> startFakeRelay() async {
      fakeRelay = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      fakeRelay.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = fakeRelay.receive();
        if (datagram == null || datagram.data.length < 20) return;
        final response = Uint8List.fromList(datagram.data.sublist(0, 20));
        response[0] = 0x01;
        response[1] = 0x01;
        fakeRelay.send(response, datagram.address, datagram.port);
      });
    }

    test('a relay that answers STUN is reachable', () async {
      await startFakeRelay();
      addTearDown(fakeRelay.close);
      final probe = TurnProbe(timeout: const Duration(seconds: 1));
      expect(await probe.probe('turn:127.0.0.1:${fakeRelay.port}'), isTrue);
    });

    test('silence is unreachable, not configured-and-fine', () async {
      // Bound but never answering: the "settings present, relay gone" case.
      final silent = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(silent.close);
      final probe = TurnProbe(timeout: const Duration(milliseconds: 300));
      expect(await probe.probe('turn:127.0.0.1:${silent.port}'), isFalse);
    });

    test('statusFor never waits and reports the result once known', () async {
      await startFakeRelay();
      addTearDown(fakeRelay.close);
      final probe = TurnProbe(timeout: const Duration(seconds: 1));
      final url = 'turn:127.0.0.1:${fakeRelay.port}';

      expect(probe.statusFor(url), 'checking');
      for (var i = 0; i < 50 && probe.statusFor(url) == 'checking'; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(probe.statusFor(url), 'reachable');
      expect(probe.statusFor(null), 'not_checked');
    });

    test('a response for another transaction does not count', () {
      final request = stunBindingRequest();
      final response = Uint8List.fromList(request)
        ..[0] = 0x01
        ..[1] = 0x01;
      expect(isStunBindingSuccess(response, request.sublist(8, 20)), isTrue);
      response[19] ^= 0xFF;
      expect(isStunBindingSuccess(response, request.sublist(8, 20)), isFalse);
    });
  });
}
