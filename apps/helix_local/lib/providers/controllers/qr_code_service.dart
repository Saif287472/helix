import 'package:helix_local_protocol/application/contracts/use_cases.dart';
import 'package:helix_local_domain/domain/models.dart';

export 'package:helix_local_domain/domain/qr/qr_payload.dart';

class QrCodeService {
  final QrCodeUseCase useCase;

  const QrCodeService({required this.useCase});

  String encode(QrPayload payload) => useCase.encode(payload);

  QrPayload? decode(String raw) => useCase.decode(raw);

  Peer payloadToPeer(QrPayload payload) => useCase.payloadToPeer(payload);

  List<Peer> payloadToPeers(QrPayload payload) =>
      useCase.payloadToPeers(payload);
}
