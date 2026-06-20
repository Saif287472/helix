import 'package:helix_local_protocol/application/contracts/use_cases.dart';
import 'package:helix_local_domain/domain/models.dart';

export 'package:helix_local_domain/domain/qr/qr_payload.dart';

class QrCodeService {
  final QrCodeUseCase _useCase;

  const QrCodeService({required this._useCase});

  String encode(QrPayload payload) => _useCase.encode(payload);

  QrPayload? decode(String raw) => _useCase.decode(raw);

  Peer payloadToPeer(QrPayload payload) => _useCase.payloadToPeer(payload);

  List<Peer> payloadToPeers(QrPayload payload) =>
      _useCase.payloadToPeers(payload);
}
