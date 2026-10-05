import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/clock.dart';
import 'package:helix_remote/core/engine/failure_copy.dart';
import 'package:helix_remote/core/engine/global_server.dart';
import 'package:helix_remote/core/engine/post_sign_in.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/format/labels.dart';
import 'package:helix_remote/core/platform/qr_encoder.dart';
import 'package:helix_remote/shared/widgets/qr_scanner_view.dart';
import 'package:helix_remote/core/security/device_auth.dart';
import 'package:helix_remote/features/devices/application/devices_gateway.dart';
import 'package:helix_remote/features/devices/application/devices_models.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

// -------------------------------------------------------------- the list

enum DevicePlatformKind { phone, desktop, other }

/// One row of the device list, as sentences.
class DeviceRowView {
  const DeviceRowView({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.isThisDevice,
    required this.kind,
  });

  final String id;
  final String title;
  final String subtitle;
  final bool isThisDevice;
  final DevicePlatformKind kind;
}

final devicesProvider = StreamProvider<List<DeviceRowView>>((ref) async* {
  final now = ref.watch(clockProvider)();
  yield* ref
      .watch(devicesGatewayProvider)
      .watch()
      .map((devices) => [for (final d in devices) _row(d, now)]);
});

DeviceRowView _row(DeviceItem d, DateTime now) {
  final platform = switch (d.platform) {
    'android' => 'Android',
    'ios' => 'iPhone',
    'windows' => 'Windows',
    'macos' => 'Mac',
    'linux' => 'Linux',
    _ => null,
  };
  final seen = d.isThisDevice
      ? 'This device'
      : 'Last active ${formatAgo(d.lastActiveAt ?? d.linkedAt, now).toLowerCase()}';
  return DeviceRowView(
    id: d.id,
    title: d.name.isEmpty ? (platform ?? 'Unnamed device') : d.name,
    subtitle: [?platform, seen].join(' - '),
    isThisDevice: d.isThisDevice,
    kind: switch (d.platform) {
      'android' || 'ios' => DevicePlatformKind.phone,
      'windows' || 'macos' || 'linux' => DevicePlatformKind.desktop,
      _ => DevicePlatformKind.other,
    },
  );
}

class DevicesActionState {
  const DevicesActionState({this.busy = false, this.error, this.notice});

  final bool busy;
  final String? error;

  /// What the last action did ("Signed out 2 devices").
  final String? notice;
}

final devicesActionsProvider =
    NotifierProvider<DevicesActions, DevicesActionState>(DevicesActions.new);

final class DevicesActions extends Notifier<DevicesActionState> {
  @override
  DevicesActionState build() => const DevicesActionState();

  DevicesGateway get _gateway => ref.read(devicesGatewayProvider);

  Future<void> refresh() => _run(() async {
    await _gateway.refresh();
    return null;
  });

  Future<void> rename(String id, String name) => _run(() async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    await _gateway.rename(id, trimmed);
    return 'Renamed.';
  });

  /// Signs another device out of the account. [lost] also tells the server it
  /// was lost or stolen.
  Future<void> revoke(String id, {bool lost = false}) => _run(() async {
    await _gateway.revoke(id, lost: lost);
    return 'Device removed.';
  });

  Future<void> revokeOthers() => _run(() async {
    final count = await _gateway.revokeOthers();
    return switch (count) {
      0 => 'There were no other devices.',
      1 => 'Signed out 1 other device.',
      _ => 'Signed out $count other devices.',
    };
  });

  void clearMessages() => state = const DevicesActionState();

  Future<void> _run(Future<String?> Function() body) async {
    if (state.busy) return;
    state = const DevicesActionState(busy: true);
    try {
      final notice = await body();
      state = DevicesActionState(notice: notice);
    } on Object catch (error) {
      state = DevicesActionState(
        error: describeFailure(error, now: ref.read(clockProvider)()).message,
      );
    }
  }
}

// ------------------------------------------------------- security events

class SecurityEventView {
  const SecurityEventView({
    required this.title,
    required this.when,
    required this.needsAttention,
    this.detail,
  });

  final String title;
  final String when;
  final String? detail;

  /// A key change or a recovery: worth a second look.
  final bool needsAttention;
}

final securityEventsProvider =
    FutureProvider.autoDispose<List<SecurityEventView>>((ref) async {
      final now = ref.watch(clockProvider)();
      final events = await ref.watch(devicesGatewayProvider).securityEvents();
      return [
        for (final e in events)
          SecurityEventView(
            title: switch (e.type) {
              SecurityEventType.signedIn => 'Signed in',
              SecurityEventType.deviceAdded => 'A device was added',
              SecurityEventType.deviceRevoked => 'A device was removed',
              SecurityEventType.passwordChanged => 'Password changed',
              SecurityEventType.recoveryUsed => 'Recovery code used',
              SecurityEventType.identityChanged => 'Your account key was reset',
              SecurityEventType.other => 'Account activity',
            },
            detail: e.deviceName,
            when: formatAgo(e.at, now),
            needsAttention:
                e.type == SecurityEventType.recoveryUsed ||
                e.type == SecurityEventType.identityChanged,
          ),
      ];
    });

// -------------------------------------------------- approving a new device

enum ApproveStep { enter, review, approving, done }

class ApproveLinkState {
  const ApproveLinkState({
    this.step = ApproveStep.enter,
    this.code = '',
    this.request,
    this.error,
    this.sendingHistory = false,
    this.historySent = false,
    this.historyError,
  });

  final ApproveStep step;
  final String code;
  final LinkRequest? request;
  final String? error;

  /// After the approval: "Send history to this device" is running, finished,
  /// or failed with a sentence. History is never sent unless asked for.
  final bool sendingHistory;
  final bool historySent;
  final String? historyError;

  ApproveLinkState copyWith({
    bool? sendingHistory,
    bool? historySent,
    String? historyError,
    bool clearHistoryError = false,
  }) => ApproveLinkState(
    step: step,
    code: code,
    request: request,
    error: error,
    sendingHistory: sendingHistory ?? this.sendingHistory,
    historySent: historySent ?? this.historySent,
    historyError: clearHistoryError
        ? null
        : (historyError ?? this.historyError),
  );
}

String linkProblemText(LinkProblem problem) => switch (problem) {
  LinkProblem.notACode =>
    'That is not a Helix link code. Scan the code shown on the new device, '
        'or paste it exactly.',
  LinkProblem.otherServer =>
    'That code is for a different server than the one this phone is signed '
        'in to, so it cannot be approved here.',
  LinkProblem.expired =>
    'That code has expired. Codes last ten minutes. Ask the new device to '
        'show a new one.',
  LinkProblem.declined =>
    'You said that was not your account, so nothing was kept and this '
        'device is not linked. If you did mean to link it, show a new code '
        'and try again.',
  LinkProblem.notLinkedYet =>
    'The new device has not finished joining yet. Wait a moment and try '
        'again.',
  LinkProblem.untrusted =>
    'The approval could not be verified, so nothing was kept. Show a new '
        'code and ask your other device to approve it again.',
  LinkProblem.notConfirmed =>
    'Approval needs your phone\'s own unlock (fingerprint, face or PIN) so '
        'nobody else holding it can add a device.',
  LinkProblem.offline =>
    'You are offline, or Helix cannot be reached. Check your connection and '
        'try again.',
  LinkProblem.notAllowed => 'The server did not accept that. Try again.',
  LinkProblem.unknown => 'That did not work. Try again.',
};

/// Approving a new device, with the safety checks around it:
///
/// 1. the code must be a Helix link code and name **this** server;
/// 2. the person is shown the server and a short number to compare with the
///    new device, and must confirm it is a device they are holding;
/// 3. when the phone has a screen lock, it must be passed before anything is
///    sent. A stranger with an unlocked phone cannot add a device.
final approveLinkProvider =
    NotifierProvider.autoDispose<ApproveLinkController, ApproveLinkState>(
      ApproveLinkController.new,
    );

final class ApproveLinkController extends Notifier<ApproveLinkState> {
  /// The account's devices before the approval, so the one that appears after
  /// it is known (and the history goes to it alone).
  Set<String> _devicesBefore = const {};

  @override
  ApproveLinkState build() => const ApproveLinkState();

  /// A code was scanned or pasted.
  Future<void> submit(String raw) async {
    final code = raw.trim();
    if (code.isEmpty) return;
    if (state.step == ApproveStep.approving) return;
    try {
      final request = await ref.read(devicesGatewayProvider).inspectLink(code);
      state = ApproveLinkState(
        step: ApproveStep.review,
        code: code,
        request: request,
      );
    } on LinkProblemException catch (e) {
      state = ApproveLinkState(error: linkProblemText(e.problem));
    } on Object catch (error) {
      state = ApproveLinkState(error: describeFailure(error).message);
    }
  }

  Future<void> approve() async {
    if (state.step != ApproveStep.review) return;
    final code = state.code;
    final request = state.request;
    state = ApproveLinkState(
      step: ApproveStep.approving,
      code: code,
      request: request,
    );
    try {
      final auth = ref.read(deviceAuthenticatorProvider);
      if (await auth.isAvailable() &&
          !await auth.confirm('Approve a new device for your Helix account')) {
        throw const LinkProblemException(LinkProblem.notConfirmed);
      }
      final gateway = ref.read(devicesGatewayProvider);
      try {
        _devicesBefore = await gateway.deviceIds();
      } on Object {
        // Offline for the list only; the approval below says so if it matters.
        _devicesBefore = const {};
      }
      await gateway.approveLink(code);
      state = const ApproveLinkState(step: ApproveStep.done);
    } on LinkProblemException catch (e) {
      state = ApproveLinkState(
        step: ApproveStep.review,
        code: code,
        request: request,
        error: linkProblemText(e.problem),
      );
    } on Object catch (error) {
      state = ApproveLinkState(
        step: ApproveStep.review,
        code: code,
        request: request,
        error: describeFailure(error).message,
      );
    }
  }

  /// "Send history to this device", on the approving side after the link.
  /// The engine's history transfer is off by default: this is the person
  /// choosing it, and the other device must still accept it.
  Future<void> sendHistory() async {
    if (state.step != ApproveStep.done ||
        state.sendingHistory ||
        state.historySent) {
      return;
    }
    state = state.copyWith(sendingHistory: true, clearHistoryError: true);
    try {
      await ref
          .read(devicesGatewayProvider)
          .sendHistoryToNewDevice(_devicesBefore);
      state = state.copyWith(sendingHistory: false, historySent: true);
    } on LinkProblemException catch (e) {
      state = state.copyWith(
        sendingHistory: false,
        historyError: linkProblemText(e.problem),
      );
    } on Object catch (error) {
      state = state.copyWith(
        sendingHistory: false,
        historyError: describeFailure(error).message,
      );
    }
  }

  void reset() => state = const ApproveLinkState();
}

// ------------------------------------------------------ linking this device

enum LinkThisStep { starting, waiting, confirming, finishing, failed }

class LinkThisDeviceState {
  const LinkThisDeviceState({
    this.step = LinkThisStep.starting,
    this.qr,
    this.check,
    this.expiresAt,
    this.error,
    this.expired = false,
    this.proposal,
  });

  final LinkThisStep step;
  final HelixQrMatrix? qr;
  final String? check;
  final DateTime? expiresAt;
  final String? error;

  /// The code ran out; offer a new one.
  final bool expired;

  /// While [step] is `confirming`: the account the approval offers, for "Is
  /// this your account?". Nothing is kept until the person confirms.
  final LinkProposalView? proposal;
}

/// How long "Is this your account?" waits for an answer before it counts as
/// no. The approval's token does not stay valid for long, and a question left
/// open on an unattended phone should not keep a way into an account open.
/// Overridden in tests.
final linkConfirmTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(minutes: 5),
);

/// The new device's side of linking: shows a QR code, waits for a signed-in
/// device to approve it, and then signs this device in. After that it asks for
/// the restore step, exactly as a password sign-in does.
final linkThisDeviceProvider =
    NotifierProvider.autoDispose<LinkThisDeviceController, LinkThisDeviceState>(
      LinkThisDeviceController.new,
    );

final class LinkThisDeviceController extends Notifier<LinkThisDeviceState> {
  LinkSession? _session;
  var _generation = 0;
  var _disposed = false;
  var _linked = false;
  var _signedIn = false;

  /// The pending "Is this your account?" answer, while one is on screen.
  Completer<bool>? _answer;
  Timer? _answerTimer;
  var _timedOut = false;

  @override
  LinkThisDeviceState build() {
    final postSignIn = ref.read(postSignInProvider.notifier);
    ref.listen(authStateProvider, (_, next) {
      _signedIn = next.value == AppAuthState.ready;
    });
    ref.onDispose(() {
      _disposed = true;
      // Leaving the page is a no: nothing is kept.
      _settleAnswer(false);
      _session?.cancel();
      // The restore step was asked for while waiting; if the person left
      // without linking, take the request back (after this provider is gone,
      // so no provider is changed while another is being disposed).
      if (!_linked && !_signedIn) Future.microtask(postSignIn.done);
    });
    return const LinkThisDeviceState();
  }

  bool get _stale => _disposed;

  /// The person's answer to "Is this your account?".
  void confirmAccount() {
    if (_answer == null) return;
    state = const LinkThisDeviceState(step: LinkThisStep.finishing);
    _settleAnswer(true);
  }

  /// "No, this is not my account" (or "Cancel"): the approval is discarded.
  void rejectAccount() => _settleAnswer(false);

  void _settleAnswer(bool yes) {
    _answerTimer?.cancel();
    _answerTimer = null;
    final answer = _answer;
    _answer = null;
    if (answer != null && !answer.isCompleted) answer.complete(yes);
  }

  Future<bool> _ask(LinkProposalView proposal, int generation) {
    if (_stale || generation != _generation) return Future.value(false);
    _timedOut = false;
    final answer = _answer = Completer<bool>();
    state = LinkThisDeviceState(
      step: LinkThisStep.confirming,
      proposal: proposal,
    );
    _answerTimer = Timer(ref.read(linkConfirmTimeoutProvider), () {
      _timedOut = true;
      _settleAnswer(false);
    });
    return answer.future;
  }

  /// Makes a code and waits. Called when the page opens and for "New code".
  Future<void> start() async {
    final generation = ++_generation;
    _session?.cancel();
    state = const LinkThisDeviceState();
    try {
      // Sign-in opens on Helix Global: a device that has not chosen another
      // server links to that one.
      if (ref.read(serverUrlProvider) == null) {
        ref.read(serverUrlProvider.notifier).use(kGlobalServerUrl);
      }
      final config = await ref.read(engineConfigProvider.future);
      final session = await ref
          .read(devicesGatewayProvider)
          .beginLink(deviceName: config.deviceName);
      if (_stale || generation != _generation) {
        session.cancel();
        return;
      }
      _session = session;
      state = LinkThisDeviceState(
        step: LinkThisStep.waiting,
        qr: encodeQr(session.code),
        check: session.check,
        expiresAt: session.expiresAt,
      );
      await _wait(session, generation);
    } on LinkProblemException catch (e) {
      if (!_stale && generation == _generation) _fail(e.problem);
    } on Object catch (error) {
      if (!_stale && generation == _generation) {
        state = LinkThisDeviceState(
          step: LinkThisStep.failed,
          error: describeFailure(error).message,
        );
      }
    }
  }

  Future<void> _wait(LinkSession session, int generation) async {
    // The account may already have a history, so the restore step is asked for
    // before the engine signs in: the router acts on it the moment the session
    // exists, with no flash of the home tabs in between.
    ref.read(postSignInProvider.notifier).offerRestore();
    try {
      await session.complete(confirm: (proposal) => _ask(proposal, generation));
    } on LinkProblemException catch (e) {
      if (!_stale && generation == _generation) {
        ref.read(postSignInProvider.notifier).done();
        if (e.problem == LinkProblem.declined && _timedOut) {
          state = const LinkThisDeviceState(
            step: LinkThisStep.failed,
            error:
                'Nobody answered, so nothing was kept and this device is not '
                'linked. Show a new code to try again.',
            expired: true,
          );
        } else {
          _fail(e.problem);
        }
      }
      return;
    } on Object catch (error) {
      if (!_stale && generation == _generation) {
        ref.read(postSignInProvider.notifier).done();
        state = LinkThisDeviceState(
          step: LinkThisStep.failed,
          error: describeFailure(error).message,
        );
      }
      return;
    }
    _linked = true;
    if (_stale) return;
    state = const LinkThisDeviceState(step: LinkThisStep.finishing);
    final url = ref.read(serverUrlProvider);
    if (url != null) {
      await ref.read(serverUrlStoreProvider).save(url.toString());
    }
  }

  void _fail(LinkProblem problem) {
    state = LinkThisDeviceState(
      step: LinkThisStep.failed,
      error: linkProblemText(problem),
      expired:
          problem == LinkProblem.expired ||
          problem == LinkProblem.declined ||
          problem == LinkProblem.untrusted,
    );
  }
}

/// "9:41" until the code on screen stops working, once a second.
///
/// Lives here because a widget has no clock; the page just draws the string.
final linkCountdownProvider = StreamProvider.autoDispose<String>((ref) async* {
  final expiresAt = ref.watch(
    linkThisDeviceProvider.select((s) => s.expiresAt),
  );
  if (expiresAt == null) return;
  final clock = ref.read(clockProvider);
  String label() {
    final left = expiresAt.difference(clock());
    if (left <= Duration.zero) return 'Expired';
    final seconds = (left.inSeconds % 60).toString().padLeft(2, '0');
    return '${left.inMinutes}:$seconds';
  }

  yield label();
  // A periodic stream is cancelled with the provider, so no timer outlives
  // the page.
  await for (final _ in Stream<void>.periodic(const Duration(seconds: 1))) {
    yield label();
  }
});

/// The camera scanner, or null where the platform has none (Windows): the
/// approve page then offers only the paste field. Re-exposed here so the page
/// can reach it without importing `core/`.
final linkScannerProvider = Provider(
  (ref) => ref.watch(qrScannerBuilderProvider),
);
