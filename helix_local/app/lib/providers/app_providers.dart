// app_providers.dart — re-exports all feature-domain provider files.
// Screens that previously imported this file directly continue to work
// without changes; imports can be migrated to the specific feature files
// incrementally.

export 'package:flutter_riverpod/legacy.dart';

export 'package:helix/providers/session_provider.dart'
    show
        productDescriptorProvider,
        profileServiceProvider,
        appInitProvider,
        profileProvider,
        sessionStateProvider,
        activeChatCountProvider,
        pendingRequestCountProvider,
        hasActiveSessionProvider;

export 'package:helix/providers/infrastructure_providers.dart';
export 'package:helix/providers/identity_providers.dart';
export 'package:helix/providers/messaging_providers.dart';
export 'package:helix/providers/discovery_providers.dart';
export 'package:helix/providers/connection_providers.dart';
export 'package:helix/providers/calls_providers.dart';
export 'package:helix/providers/transfer_providers.dart';
export 'package:helix/providers/groups_providers.dart';
export 'package:helix/providers/wipe_providers.dart';
export 'package:helix/providers/bridges_providers.dart';
