// lib/platform/windows_tray.dart
import 'dart:async';
import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:helix_domain/core/constants.dart';

/// Desktop system-tray integration using the `tray_manager` package.
///
/// Usage:
/// ```dart
/// final tray = WindowsTrayService();
/// await tray.init(
///   onOpenWindow: () => windowManager.show(),
///   onToggleDiscoverability: () { ... },
///   onExitSession: () async { await sessionService.stop(); exit(0); },
///   isDiscoverable: () => profile.discoverability == DiscoverabilityState.discoverable,
/// );
/// ```
class WindowsTrayService with TrayListener {
  FutureOr<void> Function()? _onOpenWindow;
  FutureOr<void> Function()? _onToggleDiscoverability;
  FutureOr<void> Function()? _onExitSession;
  bool Function()? _isDiscoverable;

  String _displayName = 'Helix';
  bool _initialised = false;

  // ── Public API ──────────────────────────────────────────────────────────────

  Future<void> init({
    required String displayName,
    required FutureOr<void> Function() onOpenWindow,
    required FutureOr<void> Function() onToggleDiscoverability,
    required FutureOr<void> Function() onExitSession,
    required bool Function() isDiscoverable,
  }) async {
    if (!isDesktop) return;

    _displayName = displayName;
    _onOpenWindow = onOpenWindow;
    _onToggleDiscoverability = onToggleDiscoverability;
    _onExitSession = onExitSession;
    _isDiscoverable = isDiscoverable;

    trayManager.addListener(this);

    final iconPath = _resolveTrayIconPath();
    if (iconPath != null) {
      await trayManager.setIcon(iconPath);
    }
    await trayManager.setToolTip(_displayName);
    await _rebuildMenu(isDiscoverable());

    _initialised = true;
  }

  String? _resolveTrayIconPath() {
    final candidates = [
      if (Platform.isWindows) 'assets/tray_icon.ico',
      if (Platform.isWindows) 'windows/runner/resources/app_icon.ico',
      if (Platform.isWindows) 'apps/helix_local/assets/tray_icon.ico',
      if (Platform.isWindows) 'apps/helix_local/windows/runner/resources/app_icon.ico',
      if (Platform.isWindows) 'apps/helix_remote/assets/tray_icon.ico',
      if (Platform.isWindows) 'apps/helix_remote/windows/runner/resources/app_icon.ico',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  /// Call this whenever discoverability changes so the menu label updates.
  Future<void> updateDiscoverabilityStatus(bool discoverable) async {
    if (!_initialised) return;
    await _rebuildMenu(discoverable);
  }

  Future<void> dispose() async {
    if (!_initialised) return;
    trayManager.removeListener(this);
    await trayManager.destroy();
    _initialised = false;
  }

  // ── TrayListener callbacks ──────────────────────────────────────────────────

  @override
  void onTrayIconMouseDown() {
    unawaited(Future.sync(() => _onOpenWindow?.call()));
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open':
        unawaited(Future.sync(() => _onOpenWindow?.call()));
      case 'toggle_discoverable':
        unawaited(Future.sync(() => _onToggleDiscoverability?.call()));
        // Refresh menu label to reflect the new state immediately.
        if (_isDiscoverable != null) {
          unawaited(updateDiscoverabilityStatus(_isDiscoverable!()));
        }
      case 'exit':
        unawaited(Future.sync(() => _onExitSession?.call()));
    }
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  Future<void> _rebuildMenu(bool discoverable) async {
    final discLabel = discoverable ? 'Discoverable: On' : 'Discoverable: Off';

    final menu = Menu(
      items: [
        MenuItem(key: 'open', label: 'Open $_displayName'),
        MenuItem.separator(),
        MenuItem(
          key: 'disc_status',
          label: discLabel,
          disabled: true, // status label — not clickable
        ),
        MenuItem(key: 'toggle_discoverable', label: 'Toggle discoverability'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: 'End $_displayName session and exit'),
      ],
    );

    await trayManager.setContextMenu(menu);
  }
}
