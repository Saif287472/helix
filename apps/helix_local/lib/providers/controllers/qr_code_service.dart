import 'package:helix_local_protocol/application/contracts/use_cases.dart';
import 'package:helix/application/qr/qr_code_use_case_impl.dart';
import 'package:helix_local_domain/domain/models.dart';

export 'package:helix_local_domain/domain/qr/qr_payload.dart';

class QrCodeService {
  static QrCodeUseCase? globalUseCase;

  final QrCodeUseCase? _useCase;

  const QrCodeService({this._useCase});

  QrCodeUseCase get _effectiveUseCase =>
      _useCase ?? globalUseCase ?? const QrCodeUseCaseImpl();

  String encode(QrPayload payload) {
    return _effectiveUseCase.encode(payload);
  }

  QrPayload? decode(String raw) {
    return _effectiveUseCase.decode(raw);
  }

  Peer payloadToPeer(QrPayload payload) {
    return _effectiveUseCase.payloadToPeer(payload);
  }

  List<Peer> payloadToPeers(QrPayload payload) {
    return _effectiveUseCase.payloadToPeers(payload);
  }
}
