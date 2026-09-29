import 'dart:async';

import 'package:flutter/services.dart';
import 'package:helix_remote/app/deep_link.dart';

/// Links opened while the app is already running.
///
/// The link that starts the app arrives as the initial route (see
/// `main.dart`). One tapped later - an invite shared in a chat, say - reaches
/// the running activity as a new intent, which `MainActivity` forwards here
/// instead of letting Flutter push it as a route nothing could build.
class HelixLinkChannel {
  HelixLinkChannel._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'open') return;
      final link = HelixDeepLink.tryParse(call.arguments as String? ?? '');
      if (link != null) _links.add(link);
    });
  }

  static final instance = HelixLinkChannel._();

  static const _channel = MethodChannel('com.helix.remote/links');
  final _links = StreamController<HelixDeepLink>.broadcast();

  Stream<HelixDeepLink> get links => _links.stream;
}
