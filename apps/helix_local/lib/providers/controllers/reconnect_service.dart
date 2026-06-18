import 'package:helix_discovery/helix_discovery.dart';
import 'package:helix/providers/controllers/messaging_service.dart';
import 'package:helix/providers/controllers/profile_service.dart';
import 'package:helix/providers/controllers/request_service.dart';
import 'package:helix/providers/controllers/session_service.dart';
import 'package:helix_protocol/application/contracts/use_cases.dart';
import 'package:helix/application/connection/reconnection_coordinator_impl.dart';

class ReconnectService {
  ReconnectService({
    required MessagingService messaging,
    required RequestService requests,
    required DiscoveryCoordinator discovery,
    required ProfileService profile,
    required SessionService session,
    required int Function() localTcpPort,
    ReconnectionCoordinator? reconnectionCoordinator,
  }) : _reconnectionCoordinator =
           reconnectionCoordinator ??
           ReconnectionCoordinatorImpl(
             messaging: messaging,
             requests: requests,
             discovery: discovery,
             profile: profile,
             session: session,
             localTcpPort: localTcpPort,
           );

  final ReconnectionCoordinator _reconnectionCoordinator;

  void start() {
    _reconnectionCoordinator.start();
  }

  void stop() {
    _reconnectionCoordinator.stop();
  }
}
