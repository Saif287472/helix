import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_protocol/protocol/protocol_messages.dart';
import 'package:helix_transport/services/transport/frame_io.dart';

void main() {
  test('encodeFrame prefixes a protocol payload length', () {
    final frame = KeepaliveFrame(counter: 42);
    final encoded = encodeFrame(frame);

    final length = ByteData.sublistView(encoded, 0, 4).getUint32(0, Endian.big);

    expect(length, frame.encode().length);
    expect(
      ProtocolFrame.decode(Uint8List.sublistView(encoded, 4)),
      isA<KeepaliveFrame>(),
    );
  });

  test('LengthPrefixedFrameReader buffers split stream chunks', () async {
    final encoded = encodeFrame(ChatAckFrame(messageId: 'm1', ok: true));
    final controller = StreamController<Uint8List>();
    final reader = LengthPrefixedFrameReader(controller.stream);
    final decodedFuture = reader.readFrame();

    controller.add(Uint8List.sublistView(encoded, 0, 2));
    controller.add(Uint8List.sublistView(encoded, 2, encoded.length - 1));
    controller.add(Uint8List.sublistView(encoded, encoded.length - 1));

    final decoded = await decodedFuture;
    await reader.cancel();
    await controller.close();

    expect(decoded, isA<ChatAckFrame>());
    expect((decoded as ChatAckFrame).messageId, 'm1');
    expect(decoded.ok, isTrue);
  });
}
