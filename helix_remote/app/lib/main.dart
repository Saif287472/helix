import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:helix_remote/app/helix_remote_app_shell.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/routes.dart';
import 'package:helix_remote/app/remote_account_validation.dart';
import 'package:helix_remote/app/remote_config.dart';
import 'package:helix_remote/app/remote_error_copy.dart';
import 'package:helix_remote/app/remote_rest_client.dart';
import 'package:helix_remote/screens/home_screen.dart';
import 'package:helix_remote/screens/invite_entry_screen.dart';
import 'package:helix_remote/services/android_call_runtime_service.dart';
import 'package:helix_remote/services/app_logger.dart';
import 'package:helix_remote/services/firebase_push_token_source.dart';
import 'package:helix_remote/services/local_notification_service.dart';
import 'package:helix_remote/services/onboarding_state_store.dart';
import 'package:helix_remote/services/server_url_store.dart';
import 'package:helix_remote/widgets/country_code_picker.dart';
import 'package:helix_remote/widgets/onboarding_security_badges.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app/bootstrap.dart';
part 'app/connection_setup.dart';
part 'app/remote_app_shell.dart';
part 'app/remote_app_registration.dart';
part 'app/remote_app_runtime_views.dart';
part 'app/configuration_error.dart';

void main() {
  FlutterError.onError = (details) {
    debugPrint('[Helix ERROR] ${details.exception}');
    debugPrint('[Helix STACK] ${details.stack}');
    AppLogger.instance.error('flutter', '${details.exception}', details.stack);
  };

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      if (Platform.isAndroid) {
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );
      }
      await AppLogger.instance.init('helix_remote');
      await LocalNotificationService.init();
      runApp(const HelixRemoteAppShell(home: HelixRemoteBootstrap()));
    },
    (error, stack) {
      debugPrint('[Helix UNCAUGHT] $error');
      debugPrint('[Helix STACK] $stack');
      AppLogger.instance.error('uncaught', '$error', stack);
    },
  );
}
