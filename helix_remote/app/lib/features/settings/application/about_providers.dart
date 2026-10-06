import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/clock.dart';
import 'package:helix_remote/core/engine/failure_copy.dart';
import 'package:helix_remote/core/format/labels.dart';
import 'package:helix_remote/core/platform/app_info.dart';
import 'package:helix_remote/core/platform/storage_usage.dart';
import 'package:helix_remote/features/settings/application/settings_gateway.dart';
import 'package:helix_remote/features/settings/application/settings_models.dart';

/// This build's name and version.
final aboutAppProvider = Provider<({String name, String version})>((ref) {
  final info = ref.watch(appInfoProvider);
  return (name: info.name, version: info.version);
});

/// What the server says about itself: name, version, whether it accepts new
/// accounts, the legal document versions and the feature flags it allows.
final serverDetailsProvider = FutureProvider.autoDispose<ServerDetails>(
  (ref) => ref.watch(settingsGatewayProvider).serverDetails(),
);

/// The Terms and the Privacy Policy, from the server, or the copies shipped
/// with the app when the server cannot be reached.
final legalProvider = FutureProvider.autoDispose<LegalText>(
  (ref) => ref.watch(settingsGatewayProvider).legal(),
);

/// The server's name for the About page: "Helix Global" for the default
/// server, the operator's own name for a personal one.
final serverTitleProvider = Provider.autoDispose<String?>(
  (ref) => ref.watch(serverDetailsProvider).value?.name,
);

/// One line per fact the Advanced page lists about the server.
final serverFactsProvider = Provider.autoDispose<List<(String, String)>?>((
  ref,
) {
  final d = ref.watch(serverDetailsProvider).value;
  if (d == null) return null;
  return [
    ('Name', d.name),
    ('Address', d.host),
    ('Server version', d.version),
    ('New accounts', d.openRegistration ? 'Can join' : 'Closed'),
    ('Largest attachment', formatBytes(d.maxAttachmentBytes)),
    ('Terms version', d.termsVersion),
    ('Privacy policy version', d.privacyVersion),
    if (d.federationDomain != null) ('Federation', d.federationDomain!),
  ];
});

/// The feature flags the server allows, as `(label, on)` for the flags this
/// version of the app knows how to describe.
final serverFlagsProvider = Provider.autoDispose<List<(String, bool)>>((ref) {
  final d = ref.watch(serverDetailsProvider).value;
  if (d == null) return const [];
  const labels = {
    'crash_reporting_upload': 'Crash reports accepted',
    'minimal_analytics': 'Minimal usage counts',
    'group_calls': 'Group calls',
  };
  return [
    for (final entry in d.features.entries)
      if (labels.containsKey(entry.key)) (labels[entry.key]!, entry.value),
  ];
});

// ----------------------------------------------------------------- storage

final storageSummaryProvider = FutureProvider.autoDispose<StorageSummary>((
  ref,
) async {
  final usage = await ref.watch(storageUsageProbeProvider).measure();
  return StorageSummary(
    databaseBytes: usage.databaseBytes,
    mediaBytes: usage.mediaBytes,
  );
});

// ---------------------------------------------------------------- advanced

class SyncState {
  const SyncState({this.busy = false, this.notice, this.error});

  final bool busy;
  final String? notice;
  final String? error;
}

final syncNowProvider = NotifierProvider.autoDispose<SyncNow, SyncState>(
  SyncNow.new,
);

final class SyncNow extends Notifier<SyncState> {
  @override
  SyncState build() => const SyncState();

  Future<void> run() async {
    if (state.busy) return;
    state = const SyncState(busy: true);
    try {
      await ref.read(settingsGatewayProvider).syncNow();
      state = const SyncState(notice: 'Up to date.');
    } on Object catch (error) {
      state = SyncState(
        error: describeFailure(error, now: ref.read(clockProvider)()).message,
      );
    }
  }
}
