import 'package:helix_protocol/application/contracts/use_cases.dart';
import 'package:helix/application/diagnostics/diagnostics_use_case_impl.dart';
import 'package:helix_domain/domain/models.dart';
import 'package:helix_platform/infrastructure/platform/platform_diagnostics_gateway.dart';

class DiagnosticsService {
  final DiagnosticsUseCase _useCase;

  DiagnosticsService({DiagnosticsUseCase? useCase})
    : _useCase =
          useCase ??
          DiagnosticsUseCaseImpl(gateway: PlatformDiagnosticsGateway());

  void recordBindError(String message) {
    _useCase.recordBindError(message);
  }

  Future<NetworkDiagnostics> getDiagnostics({
    int tcpPort = 0,
    bool tcpActive = false,
    bool mdnsActive = false,
    bool udpActive = false,
  }) {
    return _useCase.getDiagnostics(
      tcpPort: tcpPort,
      tcpActive: tcpActive,
      mdnsActive: mdnsActive,
      udpActive: udpActive,
    );
  }
}
