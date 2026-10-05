import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/clock.dart';
import 'package:helix_remote/core/engine/local_settings.dart';
import 'package:helix_remote/core/format/labels.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote/features/backup/application/backup_copy.dart';
import 'package:helix_remote/features/backup/application/backup_gateway.dart';
import 'package:helix_remote/features/backup/application/backup_models.dart';

// ------------------------------------------------------------------ status

/// The state of the automatic backup, live.
final backupSummaryProvider = StreamProvider<BackupSummary>(
  (ref) => ref.watch(backupGatewayProvider).watchSummary(),
);

/// What the Backup page draws: the summary as sentences.
final class BackupPageView {
  const BackupPageView({
    required this.autoBackup,
    required this.lastBackup,
    required this.lastBackupDetail,
    required this.recoveryBackup,
    this.problem,
  });

  final bool autoBackup;

  /// "Never", "5 minutes ago".
  final String lastBackup;

  /// "1,204 messages, 2.4 MB", or null before the first backup.
  final String? lastBackupDetail;
  final String recoveryBackup;

  /// Why the last attempt failed, as a sentence; cleared by the next success.
  final String? problem;
}

final backupPageViewProvider = Provider<AsyncValue<BackupPageView>>((ref) {
  final now = ref.watch(clockProvider)();
  return ref.watch(backupSummaryProvider).whenData((s) {
    final problem = s.lastProblem;
    return BackupPageView(
      autoBackup: s.autoBackup,
      lastBackup: formatAgo(s.lastBackupAt, now),
      lastBackupDetail: s.lastBackupAt == null
          ? null
          : '${_count(s.messages)} messages, ${formatBytes(s.bytes)}'
                '${s.truncated ? '. The oldest messages did not fit.' : ''}',
      recoveryBackup: s.lastRecoveryBackupAt == null
          ? 'Not made'
          : formatAgo(s.lastRecoveryBackupAt, now),
      problem: problem == null ? null : backupProblemText(problem),
    );
  });
});

String _count(int n) {
  final digits = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Whether backups may use mobile data.
final backupOverMobileProvider = settingProvider(AppSettings.backupOverMobile);

/// The switches on the Backup page.
final backupSettingsActionsProvider = Provider<BackupSettingsActions>(
  BackupSettingsActions.new,
);

final class BackupSettingsActions {
  BackupSettingsActions(this._ref);

  final Ref _ref;

  Future<void> setAutoBackup(bool enabled) =>
      _ref.read(backupGatewayProvider).setAutoBackup(enabled);

  Future<void> setOverMobile(bool enabled) => _ref
      .read(localSettingsProvider)
      .set(AppSettings.backupOverMobile, enabled);
}

// -------------------------------------------------------------- back up now

class BackupRunState {
  const BackupRunState({
    this.running = false,
    this.messages = 0,
    this.error,
    this.finished = false,
    this.skipped = false,
  });

  final bool running;

  /// Messages read so far, while running.
  final int messages;
  final String? error;

  /// A run completed since the page opened.
  final bool finished;

  /// The last run found no history to back up.
  final bool skipped;
}

final backupRunProvider = NotifierProvider<BackupRunController, BackupRunState>(
  BackupRunController.new,
);

final class BackupRunController extends Notifier<BackupRunState> {
  @override
  BackupRunState build() => const BackupRunState();

  Future<void> backUpNow() async {
    if (state.running) return;
    state = const BackupRunState(running: true);
    final gateway = ref.read(backupGatewayProvider);
    final progress = gateway.backupProgress.listen((p) {
      if (state.running &&
          (p.phase == RunPhase.preparing || p.phase == RunPhase.uploading)) {
        state = BackupRunState(running: true, messages: p.messages);
      }
    }, onError: (_) {});
    try {
      final outcome = await gateway.backUpNow();
      state = BackupRunState(finished: true, skipped: outcome.skipped);
    } on BackupProblemException catch (e) {
      state = BackupRunState(error: backupProblemText(e.problem));
    } finally {
      await progress.cancel();
    }
  }

  /// Deletes the copy on the server (not the history on this phone).
  Future<void> deleteServerBackup() async {
    state = const BackupRunState(running: true);
    try {
      await ref.read(backupGatewayProvider).deleteServerBackup();
      state = const BackupRunState();
    } on BackupProblemException catch (e) {
      state = BackupRunState(error: backupProblemText(e.problem));
    }
  }

  void clearError() => state = const BackupRunState();
}

// ------------------------------------------------------------------ restore

enum RestoreStage { idle, running, done, failed }

class RestoreFlowState {
  const RestoreFlowState({
    this.stage = RestoreStage.idle,
    this.phase,
    this.added = 0,
    this.existing = 0,
    this.problem,
  });

  final RestoreStage stage;

  /// A sentence for what is happening now.
  final String? phase;
  final int added;
  final int existing;
  final BackupProblem? problem;

  String? get error => problem == null ? null : backupProblemText(problem!);
}

/// Restores the history backup. Used by the page shown after a sign-in on a
/// new device and by "Restore history" in Settings > Backup.
final restoreFlowProvider =
    NotifierProvider.autoDispose<RestoreFlowController, RestoreFlowState>(
      RestoreFlowController.new,
    );

final class RestoreFlowController extends Notifier<RestoreFlowState> {
  @override
  RestoreFlowState build() => const RestoreFlowState();

  Future<void> restore() async {
    if (state.stage == RestoreStage.running) return;
    state = const RestoreFlowState(
      stage: RestoreStage.running,
      phase: 'Looking for your backup...',
    );
    final gateway = ref.read(backupGatewayProvider);
    final progress = gateway.restoreProgress.listen((p) {
      if (state.stage != RestoreStage.running) return;
      state = RestoreFlowState(
        stage: RestoreStage.running,
        phase: switch (p.phase) {
          RestorePhase.downloading => 'Downloading your backup...',
          RestorePhase.decrypting => 'Unlocking it...',
          RestorePhase.importing => 'Adding messages...',
          RestorePhase.done || RestorePhase.failed => null,
        },
        added: p.added,
        existing: p.existing,
      );
    }, onError: (_) {});
    try {
      final outcome = await gateway.restoreHistory();
      state = RestoreFlowState(
        stage: RestoreStage.done,
        added: outcome.added,
        existing: outcome.existing,
      );
    } on BackupProblemException catch (e) {
      state = RestoreFlowState(stage: RestoreStage.failed, problem: e.problem);
    } finally {
      await progress.cancel();
    }
  }

  void reset() => state = const RestoreFlowState();
}

// ---------------------------------------------------------------- transfers

/// Transfers this device is sending, by id, with the latest progress. The
/// engine reports progress on a broadcast stream and does not replay it, so
/// this lives for the whole app run rather than for one page.
class TransfersState {
  const TransfersState({
    this.outgoing = const {},
    this.starting = false,
    this.error,
  });

  final Map<String, TransferView> outgoing;

  /// Preparing the history: reading and encrypting it before the offer exists.
  final bool starting;
  final String? error;

  TransfersState copyWith({
    Map<String, TransferView>? outgoing,
    bool? starting,
    String? error,
    bool clearError = false,
  }) => TransfersState(
    outgoing: outgoing ?? this.outgoing,
    starting: starting ?? this.starting,
    error: clearError ? null : (error ?? this.error),
  );
}

final transfersProvider = NotifierProvider<TransfersController, TransfersState>(
  TransfersController.new,
);

final class TransfersController extends Notifier<TransfersState> {
  StreamSubscription<TransferView>? _subscription;

  @override
  TransfersState build() {
    _subscription = ref
        .read(backupGatewayProvider)
        .transferProgress
        .listen(_onProgress, onError: (_) {});
    ref.onDispose(() => _subscription?.cancel());
    return const TransfersState();
  }

  void _onProgress(TransferView view) {
    if (view.direction != TransferDirection.sending) return;
    final previous = state.outgoing[view.id];
    state = state.copyWith(
      outgoing: {
        ...state.outgoing,
        view.id: previous == null
            ? view
            : previous.copyWith(
                stage: view.stage,
                done: view.done,
                total: view.total,
                problem: view.problem,
              ),
      },
    );
  }

  /// Sends this device's history to the account's other devices.
  Future<void> send() async {
    if (state.starting) return;
    state = state.copyWith(starting: true, clearError: true);
    try {
      await ref.read(backupGatewayProvider).sendHistory();
      state = state.copyWith(starting: false);
    } on BackupProblemException catch (e) {
      state = state.copyWith(
        starting: false,
        error: e.problem == BackupProblem.cancelled
            ? null
            : backupProblemText(e.problem),
      );
    }
  }

  Future<void> cancel(String id) async {
    try {
      await ref.read(backupGatewayProvider).cancelSend(id);
    } on BackupProblemException {
      // Already finished or gone: the progress stream says so.
    }
    final view = state.outgoing[id];
    if (view != null) {
      state = state.copyWith(
        outgoing: {
          ...state.outgoing,
          id: view.copyWith(stage: TransferStage.cancelled),
        },
      );
    }
  }

  void dismiss(String id) {
    final next = {...state.outgoing}..remove(id);
    state = state.copyWith(outgoing: next);
  }
}

/// Offers of history from this account's other devices, live.
final incomingOffersProvider = StreamProvider<List<TransferView>>(
  (ref) => ref.watch(backupGatewayProvider).watchOffers(),
);

class OfferActionsState {
  const OfferActionsState({this.busy = const {}, this.errors = const {}});

  final Set<String> busy;
  final Map<String, BackupProblem> errors;

  String? errorFor(String id) {
    final problem = errors[id];
    return problem == null ? null : backupProblemText(problem);
  }
}

final offerActionsProvider =
    NotifierProvider<OfferActionsController, OfferActionsState>(
      OfferActionsController.new,
    );

final class OfferActionsController extends Notifier<OfferActionsState> {
  @override
  OfferActionsState build() => const OfferActionsState();

  /// Fetches and imports the offer. Also how a paused or failed one resumes:
  /// what was already fetched is kept.
  Future<void> accept(String id) async {
    if (state.busy.contains(id)) return;
    _set(busy: {...state.busy, id}, clear: id);
    try {
      await ref.read(backupGatewayProvider).acceptOffer(id);
      _set(busy: {...state.busy}..remove(id));
    } on BackupProblemException catch (e) {
      final busy = {...state.busy}..remove(id);
      // A pause is the person's own doing, not an error to show.
      state = OfferActionsState(
        busy: busy,
        errors: e.problem == BackupProblem.cancelled
            ? state.errors
            : {...state.errors, id: e.problem},
      );
    }
  }

  void pause(String id) => ref.read(backupGatewayProvider).pauseOffer(id);

  Future<void> decline(String id) async {
    _set(busy: {...state.busy, id}, clear: id);
    try {
      await ref.read(backupGatewayProvider).declineOffer(id);
    } on BackupProblemException catch (e) {
      state = OfferActionsState(
        busy: state.busy,
        errors: {...state.errors, id: e.problem},
      );
    } finally {
      _set(busy: {...state.busy}..remove(id));
    }
  }

  void _set({required Set<String> busy, String? clear}) {
    final errors = {...state.errors};
    if (clear != null) errors.remove(clear);
    state = OfferActionsState(busy: busy, errors: errors);
  }
}

// ---------------------------------------------------------- recovery backup

/// Random numbers for a generated recovery secret; replaceable in tests.
final secretRandomProvider = Provider<Random>((ref) => Random.secure());

/// Characters with no lookalikes (no 0/O, 1/I/L): a person copies this by
/// hand.
const _secretAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// `XXXX-XXXX-XXXX-XXXX-XXXX-XXXX`: 24 characters of a 31-character alphabet,
/// about 119 bits, well past the engine's 16-character rule.
String generateRecoverySecret(Random random) {
  final groups = <String>[];
  for (var g = 0; g < 6; g++) {
    final buffer = StringBuffer();
    for (var i = 0; i < 4; i++) {
      buffer.write(_secretAlphabet[random.nextInt(_secretAlphabet.length)]);
    }
    groups.add(buffer.toString());
  }
  return groups.join('-');
}

enum RecoveryStage { choose, creating, created, restoring, restored }

class RecoveryBackupState {
  const RecoveryBackupState({
    this.stage = RecoveryStage.choose,
    this.secret = '',
    this.written = false,
    this.error,
    this.created,
    this.restored,
  });

  final RecoveryStage stage;

  /// The secret on screen. Held in memory for as long as the page is open and
  /// nowhere else: not stored, not logged, not sent.
  final String secret;

  /// "I have written it down."
  final bool written;
  final String? error;
  final BackupOutcome? created;
  final RestoreOutcome? restored;

  bool get busy =>
      stage == RecoveryStage.creating || stage == RecoveryStage.restoring;

  RecoveryBackupState copyWith({
    RecoveryStage? stage,
    String? secret,
    bool? written,
    String? error,
    bool clearError = false,
    BackupOutcome? created,
    RestoreOutcome? restored,
  }) => RecoveryBackupState(
    stage: stage ?? this.stage,
    secret: secret ?? this.secret,
    written: written ?? this.written,
    error: clearError ? null : (error ?? this.error),
    created: created ?? this.created,
    restored: restored ?? this.restored,
  );
}

/// The recovery backup: sealed under a secret only the person holds, so it can
/// be opened on a new phone even when no other device is at hand.
final recoveryBackupProvider =
    NotifierProvider.autoDispose<RecoveryBackupController, RecoveryBackupState>(
      RecoveryBackupController.new,
    );

final class RecoveryBackupController extends Notifier<RecoveryBackupState> {
  @override
  RecoveryBackupState build() => RecoveryBackupState(
    secret: generateRecoverySecret(ref.read(secretRandomProvider)),
  );

  void regenerate() => state = RecoveryBackupState(
    secret: generateRecoverySecret(ref.read(secretRandomProvider)),
  );

  /// The person typed their own secret instead.
  void useOwn(String secret) =>
      state = state.copyWith(secret: secret, written: false, clearError: true);

  void setWritten(bool value) => state = state.copyWith(written: value);

  Future<void> create() async {
    if (state.busy) return;
    state = state.copyWith(stage: RecoveryStage.creating, clearError: true);
    try {
      final outcome = await ref
          .read(backupGatewayProvider)
          .createRecoveryBackup(state.secret);
      state = state.copyWith(stage: RecoveryStage.created, created: outcome);
    } on BackupProblemException catch (e) {
      state = state.copyWith(
        stage: RecoveryStage.choose,
        error: backupProblemText(e.problem),
      );
    }
  }

  Future<void> restore(String secret) async {
    if (state.busy) return;
    state = state.copyWith(stage: RecoveryStage.restoring, clearError: true);
    try {
      final outcome = await ref
          .read(backupGatewayProvider)
          .restoreRecoveryBackup(secret.trim());
      state = state.copyWith(stage: RecoveryStage.restored, restored: outcome);
    } on BackupProblemException catch (e) {
      state = state.copyWith(
        stage: RecoveryStage.choose,
        error: backupProblemText(e.problem),
      );
    }
  }

  Future<void> deleteBackup() async {
    try {
      await ref.read(backupGatewayProvider).deleteRecoveryBackup();
      state = state.copyWith(clearError: true);
    } on BackupProblemException catch (e) {
      state = state.copyWith(error: backupProblemText(e.problem));
    }
  }
}
