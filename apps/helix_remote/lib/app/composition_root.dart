// Single wiring point for all concrete Remote infrastructure.
// Phase 5 — P5-009/P5-010/P5-011/P5-012.
//
// Rules enforced by construction:
//   - No LAN discovery, secret-code lookup, or Local trust store.
//   - No Local wipe scheduler (Remote has its own lifecycle).
//   - Product config is validated at construction time; missing required fields
//     throw StateError before the app reaches its first screen.

/// Immutable product configuration for the Remote product.
/// All fields must be non-empty; validated by [RemoteCompositionRoot.production].
class RemoteProductConfig {
  const RemoteProductConfig({
    required this.displayName,
    required this.packageId,
    required this.secureStoragePrefix,
    required this.methodChannelNamespace,
    required this.logNamespace,
  });

  final String displayName;
  final String packageId;
  final String secureStoragePrefix;
  final String methodChannelNamespace;
  final String logNamespace;
}

/// Composition root for Helix Remote.
///
/// Currently binds only placeholder interfaces (Phase 5, P5-010). Concrete
/// Remote infrastructure (account store, push gateway, sync engine, TURN
/// client) will be added in Phase 8 when Remote features are implemented.
class RemoteCompositionRoot {
  RemoteCompositionRoot._({required this.config});

  /// Creates the production Remote root and validates required configuration.
  /// Throws [StateError] if any required config field is empty.
  factory RemoteCompositionRoot.production() {
    const config = RemoteProductConfig(
      displayName: 'Helix Remote',
      packageId: 'com.helix.remote',
      secureStoragePrefix: 'helix_remote_v1_',
      methodChannelNamespace: 'com.helix.remote',
      logNamespace: 'helix_remote',
    );
    final root = RemoteCompositionRoot._(config: config);
    root._validate();
    return root;
  }

  /// Test constructor — accepts an explicit config for startup-failure tests.
  factory RemoteCompositionRoot.withConfig(RemoteProductConfig config) {
    final root = RemoteCompositionRoot._(config: config);
    root._validate();
    return root;
  }

  final RemoteProductConfig config;

  void _validate() {
    if (config.displayName.isEmpty) {
      throw StateError('RemoteProductConfig.displayName must not be empty');
    }
    if (config.packageId.isEmpty) {
      throw StateError('RemoteProductConfig.packageId must not be empty');
    }
    if (config.secureStoragePrefix.isEmpty) {
      throw StateError(
        'RemoteProductConfig.secureStoragePrefix must not be empty',
      );
    }
    if (!config.secureStoragePrefix.endsWith('_')) {
      throw StateError(
        'RemoteProductConfig.secureStoragePrefix must end with "_" '
        'to prevent key collisions between products',
      );
    }
    if (config.methodChannelNamespace.isEmpty) {
      throw StateError(
        'RemoteProductConfig.methodChannelNamespace must not be empty',
      );
    }
    if (config.logNamespace.isEmpty) {
      throw StateError(
        'RemoteProductConfig.logNamespace must not be empty',
      );
    }
  }

  // ------------------------------------------------------------------
  // Placeholder slot — Remote infrastructure bound here in Phase 8+.
  // Each concrete binding will be a named field with a domain-interface
  // type (e.g. AccountRepository, PushGateway) so the type is visible
  // at the call site and Remote-specific.
  // ------------------------------------------------------------------

  void dispose() {
    // No resources to release in the Phase 5 placeholder.
  }
}
