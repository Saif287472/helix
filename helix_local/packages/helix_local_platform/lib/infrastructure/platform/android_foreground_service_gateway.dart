import 'package:helix_local_platform/platform/android_foreground.dart';
import 'package:helix_local_protocol/application/contracts/gateways.dart';

class AndroidForegroundServiceGateway implements ForegroundServiceGateway {
  const AndroidForegroundServiceGateway();

  @override
  Future<void> stopService() async {
    await AndroidForegroundService.stopService();
  }
}
