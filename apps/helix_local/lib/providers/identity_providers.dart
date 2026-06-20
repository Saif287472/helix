// Identity providers: QR code, secret code, diagnostics, trust, notifications.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix_local_domain/application/contracts/repositories.dart'
    show TrustRepository;
import 'package:helix_local_protocol/application/contracts/use_cases.dart';
import 'package:helix/providers/session_provider.dart'
    show profileServiceProvider;
import 'package:helix/providers/infrastructure_providers.dart';
import 'package:helix/providers/controllers/diagnostics_service.dart';
import 'package:helix/providers/controllers/notification_service.dart';
import 'package:helix/providers/controllers/qr_code_service.dart';
import 'package:helix/providers/controllers/secret_code_service.dart';
import 'package:helix/providers/controllers/trust_service.dart';
import 'package:helix/application/diagnostics/diagnostics_use_case_impl.dart';
import 'package:helix/application/qr/qr_code_use_case_impl.dart';
import 'package:helix/application/secret_code/secret_code_use_case_impl.dart';
import 'package:helix/application/trust/trust_use_case_impl.dart';

export 'package:helix/providers/controllers/qr_code_service.dart'
    show QrCodeService;
export 'package:helix_local_domain/domain/qr/qr_payload.dart';

final qrCodeUseCaseProvider = Provider<QrCodeUseCase>((ref) {
  return const QrCodeUseCaseImpl();
});

final qrCodeServiceProvider = Provider<QrCodeService>((ref) {
  return QrCodeService(useCase: ref.watch(qrCodeUseCaseProvider));
});

final secretCodeUseCaseProvider = Provider<SecretCodeUseCase>((ref) {
  return SecretCodeUseCaseImpl();
});

final secretCodeServiceProvider = Provider<SecretCodeService>((ref) {
  return SecretCodeService(useCase: ref.watch(secretCodeUseCaseProvider));
});

final diagnosticsUseCaseProvider = Provider<DiagnosticsUseCase>((ref) {
  return DiagnosticsUseCaseImpl(gateway: ref.watch(diagnosticsGatewayProvider));
});

final diagnosticsServiceProvider = Provider<DiagnosticsService>((ref) {
  return DiagnosticsService(useCase: ref.watch(diagnosticsUseCaseProvider));
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final svc = NotificationService(
    notificationGateway: ref.watch(notificationGatewayProvider),
  );
  ref.onDispose(svc.dispose);
  return svc;
});

final trustRepositoryProvider = Provider<TrustRepository>((ref) {
  return ref.watch(compositionRootProvider).trustRepository;
});

final trustUseCaseProvider = Provider<TrustUseCase>((ref) {
  final useCase = TrustUseCaseImpl(
    repository: ref.watch(trustRepositoryProvider),
  );
  ref.onDispose(useCase.dispose);
  return useCase;
});

final trustServiceProvider = Provider<TrustService>((ref) {
  final svc = TrustService(trustUseCase: ref.watch(trustUseCaseProvider));
  ref.onDispose(svc.dispose);
  return svc;
});

final knownPeersProvider = StreamProvider<List<KnownPeer>>((ref) {
  return ref.watch(trustServiceProvider).changes;
});

final isFirstRunProvider = Provider<bool>((ref) {
  return ref.watch(profileServiceProvider).isFirstRun;
});

final notificationTapsProvider = StreamProvider<String>((ref) {
  return ref.watch(notificationServiceProvider).taps;
});
