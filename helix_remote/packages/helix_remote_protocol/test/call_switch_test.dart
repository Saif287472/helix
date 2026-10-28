import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('a switch offer carries its media, description and segment', () {
    const payload = CallSignalPayload(
      type: CallSignalType.switchOffer,
      callId: 'call-0001',
      media: CallMedia.video,
      sdp: 'v=0',
      segment: 2,
    );
    final back = CallSignalPayload.decode(payload.encode());
    expect(back.type, CallSignalType.switchOffer);
    expect(back.media, CallMedia.video);
    expect(back.segment, 2);
    expect(back.type.routedAs, CallSignalKind.update);
  });

  test('every switch signal is live only', () {
    for (final t in [
      CallSignalType.switchAsk,
      CallSignalType.switchAccept,
      CallSignalType.switchDecline,
      CallSignalType.switchOffer,
      CallSignalType.switchAnswer,
    ]) {
      expect(t.routedAs, CallSignalKind.update);
    }
  });

  test('a first-segment ice signal omits the segment', () {
    const payload = CallSignalPayload(
      type: CallSignalType.ice,
      callId: 'call-0001',
    );
    expect(payload.toJson().containsKey('segment'), isFalse);
  });
}
