import 'package:path/path.dart' as p;

enum RemoteProxyMode { direct, http, socks5 }

enum RemotePlatformKind {
  android,
  ios,
  windows,
  macos,
  linux,
  tablet,
  watch,
  constrained,
}

class RemoteRuntimeException implements Exception {
  const RemoteRuntimeException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RemoteAccountRuntimeDescriptor {
  const RemoteAccountRuntimeDescriptor({
    required this.accountId,
    required this.displayName,
    required this.databasePath,
    required this.secureStorageNamespace,
    required this.attachmentCachePath,
    required this.notificationChannelId,
    required this.serverBaseUrl,
    this.active = false,
    this.lastUsedAtMs = 0,
    this.status = 'active',
  });

  final String accountId;
  final String displayName;
  final String databasePath;
  final String secureStorageNamespace;
  final String attachmentCachePath;
  final String notificationChannelId;
  final String serverBaseUrl;
  final bool active;
  final int lastUsedAtMs;
  final String status;

  String get tokenKeyPrefix => '$secureStorageNamespace:tokens:$accountId';
  String get keyMaterialPrefix => '$secureStorageNamespace:keys:$accountId';
  String get syncTaskNamespace => 'remote.sync.$accountId';
  String get callTaskNamespace => 'remote.calls.$accountId';
  String get shareTargetNamespace => 'remote.share.$accountId';
  String get clipboardNamespace => 'remote.clipboard.$accountId';
  String get notificationNamespace => '$notificationChannelId:$accountId';

  RemoteAccountRuntimeDescriptor copyWith({
    bool? active,
    int? lastUsedAtMs,
    String? status,
  }) {
    return RemoteAccountRuntimeDescriptor(
      accountId: accountId,
      displayName: displayName,
      databasePath: databasePath,
      secureStorageNamespace: secureStorageNamespace,
      attachmentCachePath: attachmentCachePath,
      notificationChannelId: notificationChannelId,
      serverBaseUrl: serverBaseUrl,
      active: active ?? this.active,
      lastUsedAtMs: lastUsedAtMs ?? this.lastUsedAtMs,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> publicIndicator(String surface) => {
    'surface': surface,
    'account_id': accountId,
    'display_name': displayName,
    'notification_channel_id': notificationChannelId,
  };

  Map<String, dynamic> redactedDiagnostics() => {
    'account_id': accountId,
    'display_name': displayName,
    'database_path_hash': databasePath.hashCode.toUnsigned(32).toString(),
    'secure_storage_namespace': secureStorageNamespace,
    'attachment_cache_path_hash': attachmentCachePath.hashCode
        .toUnsigned(32)
        .toString(),
    'notification_channel_id': notificationChannelId,
    'server_host': Uri.tryParse(serverBaseUrl)?.host ?? '',
    'status': status,
    'active': active,
  };
}

class RemoteProxySettings {
  const RemoteProxySettings({
    required this.mode,
    this.host = '',
    this.port = 0,
    this.username = '',
    this.passwordRef = '',
    this.allowInvalidCertificates = false,
  });

  final RemoteProxyMode mode;
  final String host;
  final int port;
  final String username;
  final String passwordRef;
  final bool allowInvalidCertificates;

  bool get enabled => mode != RemoteProxyMode.direct;

  void validate() {
    if (allowInvalidCertificates) {
      throw const RemoteRuntimeException(
        'Proxy certificate validation cannot be disabled.',
      );
    }
    if (!enabled) return;
    if (host.trim().isEmpty) {
      throw const RemoteRuntimeException('Proxy host is required.');
    }
    if (port <= 0 || port > 65535) {
      throw const RemoteRuntimeException('Proxy port is invalid.');
    }
  }

  Map<String, dynamic> redactedDiagnostics() => {
    'mode': mode.name,
    'enabled': enabled,
    'host': host,
    'port': port,
    'username_present': username.isNotEmpty,
    'password_ref_present': passwordRef.isNotEmpty,
    'certificate_validation': allowInvalidCertificates ? 'invalid' : 'required',
    'rest': enabled ? 'proxied' : 'direct',
    'websocket': enabled ? 'proxied' : 'direct',
    'attachment_transfer': enabled ? 'proxied' : 'direct',
    'call_signaling': enabled ? 'proxied' : 'direct',
    'turn_media': 'separate',
  };
}

class RemotePlatformCapabilities {
  const RemotePlatformCapabilities({
    required this.kind,
    required this.desktop,
    required this.mobile,
    required this.tabletLayout,
    required this.backgroundSync,
    required this.notifications,
    required this.tray,
    required this.deepLinks,
    required this.dragDrop,
    required this.fileAssociations,
    required this.callWindow,
    required this.autoUpdates,
    required this.crashRecovery,
    required this.camera,
    required this.microphone,
    required this.screenShare,
    required this.constrainedOs,
    this.notes = const [],
  });

  final RemotePlatformKind kind;
  final bool desktop;
  final bool mobile;
  final bool tabletLayout;
  final bool backgroundSync;
  final bool notifications;
  final bool tray;
  final bool deepLinks;
  final bool dragDrop;
  final bool fileAssociations;
  final bool callWindow;
  final bool autoUpdates;
  final bool crashRecovery;
  final bool camera;
  final bool microphone;
  final bool screenShare;
  final bool constrainedOs;
  final List<String> notes;

  factory RemotePlatformCapabilities.forKind(RemotePlatformKind kind) {
    switch (kind) {
      case RemotePlatformKind.windows:
        return const RemotePlatformCapabilities(
          kind: RemotePlatformKind.windows,
          desktop: true,
          mobile: false,
          tabletLayout: false,
          backgroundSync: true,
          notifications: true,
          tray: true,
          deepLinks: true,
          dragDrop: true,
          fileAssociations: true,
          callWindow: true,
          autoUpdates: true,
          crashRecovery: true,
          camera: true,
          microphone: true,
          screenShare: true,
          constrainedOs: false,
        );
      case RemotePlatformKind.macos:
        return const RemotePlatformCapabilities(
          kind: RemotePlatformKind.macos,
          desktop: true,
          mobile: false,
          tabletLayout: false,
          backgroundSync: true,
          notifications: true,
          tray: true,
          deepLinks: true,
          dragDrop: true,
          fileAssociations: true,
          callWindow: true,
          autoUpdates: false,
          crashRecovery: true,
          camera: true,
          microphone: true,
          screenShare: true,
          constrainedOs: false,
          notes: ['macos_after_windows_stable'],
        );
      case RemotePlatformKind.tablet:
        return const RemotePlatformCapabilities(
          kind: RemotePlatformKind.tablet,
          desktop: false,
          mobile: true,
          tabletLayout: true,
          backgroundSync: true,
          notifications: true,
          tray: false,
          deepLinks: true,
          dragDrop: true,
          fileAssociations: false,
          callWindow: false,
          autoUpdates: false,
          crashRecovery: true,
          camera: true,
          microphone: true,
          screenShare: false,
          constrainedOs: false,
        );
      case RemotePlatformKind.watch:
      case RemotePlatformKind.constrained:
        return RemotePlatformCapabilities.deferred(kind);
      case RemotePlatformKind.android:
      case RemotePlatformKind.ios:
      case RemotePlatformKind.linux:
        return RemotePlatformCapabilities(
          kind: kind,
          desktop: kind == RemotePlatformKind.linux,
          mobile: kind != RemotePlatformKind.linux,
          tabletLayout: false,
          backgroundSync: true,
          notifications: true,
          tray: kind == RemotePlatformKind.linux,
          deepLinks: true,
          dragDrop: kind == RemotePlatformKind.linux,
          fileAssociations: kind == RemotePlatformKind.linux,
          callWindow: kind == RemotePlatformKind.linux,
          autoUpdates: false,
          crashRecovery: true,
          camera: true,
          microphone: true,
          screenShare: kind == RemotePlatformKind.linux,
          constrainedOs: false,
        );
    }
  }

  factory RemotePlatformCapabilities.deferred(RemotePlatformKind kind) {
    return RemotePlatformCapabilities(
      kind: kind,
      desktop: false,
      mobile: false,
      tabletLayout: false,
      backgroundSync: false,
      notifications: false,
      tray: false,
      deepLinks: false,
      dragDrop: false,
      fileAssociations: false,
      callWindow: false,
      autoUpdates: false,
      crashRecovery: false,
      camera: false,
      microphone: false,
      screenShare: false,
      constrainedOs: true,
      notes: const ['deferred_until_core_account_sync_apis_are_stable'],
    );
  }

  bool supportsFeature(String feature) {
    return switch (feature) {
      'background_sync' => backgroundSync,
      'notifications' => notifications,
      'tray' => tray,
      'deep_links' => deepLinks,
      'drag_drop' => dragDrop,
      'file_associations' => fileAssociations,
      'call_window' => callWindow,
      'auto_updates' => autoUpdates,
      'crash_recovery' => crashRecovery,
      'camera' => camera,
      'microphone' => microphone,
      'screen_share' => screenShare,
      'two_pane_chat' => tabletLayout || desktop,
      'default_messaging_integration' => false,
      'smartwatch_client' => false,
      _ => false,
    };
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'desktop': desktop,
    'mobile': mobile,
    'tablet_layout': tabletLayout,
    'background_sync': backgroundSync,
    'notifications': notifications,
    'tray': tray,
    'deep_links': deepLinks,
    'drag_drop': dragDrop,
    'file_associations': fileAssociations,
    'call_window': callWindow,
    'auto_updates': autoUpdates,
    'crash_recovery': crashRecovery,
    'camera': camera,
    'microphone': microphone,
    'screen_share': screenShare,
    'constrained_os': constrainedOs,
    'notes': notes,
  };
}

class RemoteAccountRuntimeRegistry {
  RemoteAccountRuntimeRegistry({
    RemotePlatformCapabilities platform = const RemotePlatformCapabilities(
      kind: RemotePlatformKind.android,
      desktop: false,
      mobile: true,
      tabletLayout: false,
      backgroundSync: true,
      notifications: true,
      tray: false,
      deepLinks: true,
      dragDrop: false,
      fileAssociations: false,
      callWindow: false,
      autoUpdates: false,
      crashRecovery: true,
      camera: true,
      microphone: true,
      screenShare: false,
      constrainedOs: false,
    ),
  }) : _platform = platform;

  final Map<String, RemoteAccountRuntimeDescriptor> _accounts = {};
  final Map<String, RemoteProxySettings> _proxies = {};
  RemotePlatformCapabilities _platform;
  String? _activeAccountId;

  RemotePlatformCapabilities get platform => _platform;

  List<RemoteAccountRuntimeDescriptor> get accounts =>
      List.unmodifiable(_accounts.values);

  RemoteAccountRuntimeDescriptor? get activeAccount =>
      _activeAccountId == null ? null : _accounts[_activeAccountId];

  void updatePlatform(RemotePlatformCapabilities platform) {
    _platform = platform;
  }

  void addAccount(RemoteAccountRuntimeDescriptor descriptor) {
    _validateDescriptor(descriptor);
    _accounts[descriptor.accountId] = descriptor;
    if (descriptor.active || _activeAccountId == null) {
      switchAccount(descriptor.accountId, nowMs: descriptor.lastUsedAtMs);
    }
  }

  RemoteAccountRuntimeDescriptor switchAccount(
    String accountId, {
    required int nowMs,
  }) {
    final next = _accounts[accountId];
    if (next == null || next.status == 'deleted') {
      throw RemoteRuntimeException('Unknown account runtime: $accountId');
    }
    for (final entry in _accounts.entries.toList()) {
      _accounts[entry.key] = entry.value.copyWith(active: false);
    }
    final active = next.copyWith(active: true, lastUsedAtMs: nowMs);
    _accounts[accountId] = active;
    _activeAccountId = accountId;
    return active;
  }

  void removeAccount(String accountId, {required int nowMs}) {
    // Evict the descriptor entirely: keeping tombstones in the registry leaks
    // memory for every account ever removed over the process lifetime.
    final account = _accounts.remove(accountId);
    if (account == null) return;
    _proxies.remove(accountId);
    if (_activeAccountId == accountId) {
      _activeAccountId = null;
    }
  }

  List<RemoteAccountRuntimeDescriptor> cleanupInactive({
    required int olderThanMs,
    int maxInactiveAccounts = 3,
  }) {
    final inactive =
        _accounts.values
            .where((account) => !account.active && account.status != 'deleted')
            .where((account) => account.lastUsedAtMs < olderThanMs)
            .toList()
          ..sort((a, b) => a.lastUsedAtMs.compareTo(b.lastUsedAtMs));
    final removable = inactive.take(
      inactive.length > maxInactiveAccounts
          ? inactive.length - maxInactiveAccounts
          : 0,
    );
    for (final account in removable) {
      removeAccount(account.accountId, nowMs: olderThanMs);
    }
    return List.unmodifiable(removable);
  }

  void setProxy(String accountId, RemoteProxySettings proxy) {
    if (!_accounts.containsKey(accountId)) {
      throw RemoteRuntimeException('Unknown account runtime: $accountId');
    }
    proxy.validate();
    _proxies[accountId] = proxy;
  }

  RemoteProxySettings proxyFor(String accountId) {
    return _proxies[accountId] ??
        const RemoteProxySettings(mode: RemoteProxyMode.direct);
  }

  Map<String, dynamic> accountBoundContext(String surface) {
    final active = activeAccount;
    if (active == null) {
      throw const RemoteRuntimeException('No active account runtime.');
    }
    return {
      ...active.publicIndicator(surface),
      'database_path': active.databasePath,
      'secure_storage_namespace': active.secureStorageNamespace,
      'attachment_cache_path': active.attachmentCachePath,
      'token_key_prefix': active.tokenKeyPrefix,
      'key_material_prefix': active.keyMaterialPrefix,
      'sync_task_namespace': active.syncTaskNamespace,
      'call_task_namespace': active.callTaskNamespace,
      'share_target_namespace': active.shareTargetNamespace,
      'clipboard_namespace': active.clipboardNamespace,
      'notification_namespace': active.notificationNamespace,
    };
  }

  Map<String, dynamic> redactedConnectivityDiagnostics(String accountId) {
    final account = _accounts[accountId];
    if (account == null) {
      throw RemoteRuntimeException('Unknown account runtime: $accountId');
    }
    return {
      'account': account.redactedDiagnostics(),
      'proxy': proxyFor(accountId).redactedDiagnostics(),
      'platform': _platform.toJson(),
    };
  }

  bool featureAvailable(String feature) {
    return !_platform.constrainedOs && _platform.supportsFeature(feature);
  }

  void _validateDescriptor(RemoteAccountRuntimeDescriptor descriptor) {
    if (descriptor.accountId.trim().isEmpty) {
      throw const RemoteRuntimeException('Account id is required.');
    }
    if (descriptor.secureStorageNamespace.trim().isEmpty) {
      throw const RemoteRuntimeException(
        'Secure storage namespace is required.',
      );
    }
    for (final existing in _accounts.values) {
      if (existing.accountId == descriptor.accountId) continue;
      if (p.equals(existing.databasePath, descriptor.databasePath)) {
        throw const RemoteRuntimeException(
          'Account database paths must be isolated.',
        );
      }
      if (existing.secureStorageNamespace ==
          descriptor.secureStorageNamespace) {
        throw const RemoteRuntimeException(
          'Secure storage namespaces must be isolated.',
        );
      }
      if (p.equals(
        existing.attachmentCachePath,
        descriptor.attachmentCachePath,
      )) {
        throw const RemoteRuntimeException(
          'Attachment cache paths must be isolated.',
        );
      }
      if (existing.notificationChannelId == descriptor.notificationChannelId) {
        throw const RemoteRuntimeException(
          'Notification channels must be account scoped.',
        );
      }
    }
  }
}
