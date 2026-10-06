import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/clock.dart';
import 'package:helix_remote/core/engine/failure_copy.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/platform/phone_numbers.dart';
import 'package:helix_remote/features/settings/application/settings_gateway.dart';
import 'package:helix_remote/features/settings/application/settings_models.dart';

/// How this account proves it is the owner when deleting itself.
///
/// Matches the engine's proof selection (and so the server's): an account with
/// a **password** gives the password (it is derived into a key on this phone;
/// only the key is sent); an account without one whose number the server can
/// text gives a **code** sent to that number; any other account gives nothing
/// to type, and this device **signs** a challenge from the server with its own
/// key. A session alone never deletes an account.
enum DeleteProof { device, password, code }

class DeleteAccountState {
  const DeleteAccountState({
    this.proof = DeleteProof.device,
    this.busy = false,
    this.confirmError,
    this.passwordError,
    this.numberError,
    this.codeError,
    this.error,
    this.codeSentTo,
    this.needsNumber = false,
    this.done = false,
  });

  final DeleteProof proof;
  final bool busy;

  /// Under the "type DELETE" field.
  final String? confirmError;

  /// Wrong password, or locked out.
  final String? passwordError;

  /// The number could not be used.
  final String? numberError;

  /// The texted code did not match.
  final String? codeError;

  /// A failure that is not about one field (offline, refused).
  final String? error;

  /// A code was texted to this masked number.
  final String? codeSentTo;

  /// This device does not know the account's number: it has to be typed.
  final bool needsNumber;

  /// The account is deleted and this device is signed out and wiped.
  final bool done;

  DeleteAccountState copyWith({
    DeleteProof? proof,
    bool? busy,
    String? codeSentTo,
    bool? needsNumber,
  }) => DeleteAccountState(
    proof: proof ?? this.proof,
    busy: busy ?? this.busy,
    codeSentTo: codeSentTo ?? this.codeSentTo,
    needsNumber: needsNumber ?? this.needsNumber,
  );
}

final deleteAccountProvider =
    NotifierProvider.autoDispose<DeleteAccountController, DeleteAccountState>(
      DeleteAccountController.new,
    );

/// Deleting the account: the type-DELETE confirmation, then the proof, then
/// the engine's `deleteAccount`, which deletes on the server and wipes this
/// device. Every refusal is a sentence on the field it belongs to.
final class DeleteAccountController extends Notifier<DeleteAccountState> {
  /// The texted code's challenge. In memory for this flow only.
  String? _challengeId;

  @override
  DeleteAccountState build() => const DeleteAccountState();

  SettingsGateway get _gateway => ref.read(settingsGatewayProvider);

  /// What the person typed, validated and sent. [hasPassword] and
  /// [phoneKnown] come from the account overview. The fields not needed for
  /// the current proof are ignored.
  Future<void> submit({
    required String confirmation,
    required bool hasPassword,
    required bool phoneKnown,
    String password = '',
    String phoneNumber = '',
    String code = '',
  }) async {
    if (state.busy || state.done) return;
    if (confirmation.trim() != 'DELETE') {
      state = DeleteAccountState(
        proof: state.proof,
        codeSentTo: state.codeSentTo,
        needsNumber: state.needsNumber,
        confirmError: 'Type DELETE in capital letters to confirm.',
      );
      return;
    }
    final proof = hasPassword ? DeleteProof.password : state.proof;
    switch (proof) {
      case DeleteProof.password:
        await _withPassword(password, phoneKnown, phoneNumber);
      case DeleteProof.device:
        await _withDevice(phoneNumber);
      case DeleteProof.code:
        await _withCode(code);
    }
  }

  // ---------------------------------------------------------- the password

  Future<void> _withPassword(
    String password,
    bool phoneKnown,
    String phoneNumber,
  ) async {
    String? number;
    if (!phoneKnown) {
      number = _normalized(phoneNumber);
      if (number == null) {
        state = const DeleteAccountState(
          proof: DeleteProof.password,
          needsNumber: true,
          numberError: _badNumber,
        );
        return;
      }
    }
    if (password.isEmpty) {
      state = DeleteAccountState(
        proof: DeleteProof.password,
        needsNumber: !phoneKnown,
        passwordError: 'Enter your password.',
      );
      return;
    }
    state = DeleteAccountState(
      proof: DeleteProof.password,
      busy: true,
      needsNumber: !phoneKnown,
    );
    try {
      await _gateway.deleteAccount(password: password, phoneNumber: number);
      await _finish();
    } on Object catch (error) {
      final failure = describeFailure(error, now: ref.read(clockProvider)());
      state = switch (failure.kind) {
        FailureKind.rejected => DeleteAccountState(
          proof: DeleteProof.password,
          needsNumber: !phoneKnown,
          passwordError: 'That is not your password.',
        ),
        FailureKind.locked => DeleteAccountState(
          proof: DeleteProof.password,
          needsNumber: !phoneKnown,
          passwordError: failure.message,
        ),
        _ => DeleteAccountState(
          proof: DeleteProof.password,
          needsNumber: !phoneKnown,
          error: failure.message,
        ),
      };
    }
  }

  // ------------------------------------------------------ this device's key

  /// No password: the device signs. If the server says it wants a texted code
  /// instead, the page moves on to that, and the code is requested.
  Future<void> _withDevice(String phoneNumber) async {
    state = const DeleteAccountState(busy: true);
    try {
      await _gateway.deleteAccount();
      await _finish();
    } on DeletionNeedsCode {
      await _sendCode(phoneNumber);
    } on Object catch (error) {
      state = DeleteAccountState(
        error: describeFailure(error, now: ref.read(clockProvider)()).message,
      );
    }
  }

  // --------------------------------------------------------- a texted code

  /// Texts (or texts again) the code. [phoneNumber] is only used when this
  /// device does not know the account's number.
  Future<void> sendCode({String phoneNumber = ''}) async {
    if (state.busy || state.done) return;
    await _sendCode(phoneNumber);
  }

  Future<void> _sendCode(String phoneNumber) async {
    final typed = phoneNumber.trim().isEmpty ? null : _normalized(phoneNumber);
    if (phoneNumber.trim().isNotEmpty && typed == null) {
      state = const DeleteAccountState(
        proof: DeleteProof.code,
        needsNumber: true,
        numberError: _badNumber,
      );
      return;
    }
    state = DeleteAccountState(
      proof: DeleteProof.code,
      busy: true,
      needsNumber: state.needsNumber,
    );
    try {
      final sent = await _gateway.requestDeletionCode(phoneNumber: typed);
      _challengeId = sent.challengeId;
      state = DeleteAccountState(
        proof: DeleteProof.code,
        codeSentTo: sent.sentTo,
      );
    } on PhoneNumberNeeded {
      state = const DeleteAccountState(
        proof: DeleteProof.code,
        needsNumber: true,
      );
    } on Object catch (error) {
      state = DeleteAccountState(
        proof: DeleteProof.code,
        needsNumber: state.needsNumber,
        error: describeFailure(error, now: ref.read(clockProvider)()).message,
      );
    }
  }

  Future<void> _withCode(String code) async {
    final challenge = _challengeId;
    if (challenge == null) {
      // Nothing was sent yet (the number was needed first).
      state = DeleteAccountState(
        proof: DeleteProof.code,
        needsNumber: state.needsNumber,
        error: 'Ask for a code first.',
      );
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code.trim())) {
      state = DeleteAccountState(
        proof: DeleteProof.code,
        codeSentTo: state.codeSentTo,
        codeError: 'The code is 6 digits.',
      );
      return;
    }
    final sentTo = state.codeSentTo;
    state = DeleteAccountState(
      proof: DeleteProof.code,
      busy: true,
      codeSentTo: sentTo,
    );
    try {
      final token = await _gateway.verifyDeletionCode(
        challengeId: challenge,
        code: code.trim(),
      );
      await _gateway.deleteAccount(verificationToken: token);
      await _finish();
    } on Object catch (error) {
      final failure = describeFailure(error, now: ref.read(clockProvider)());
      state = DeleteAccountState(
        proof: DeleteProof.code,
        codeSentTo: sentTo,
        codeError: failure.kind == FailureKind.rejected
            ? 'That code did not match. Check it, or ask for a new one.'
            : null,
        error: failure.kind == FailureKind.rejected ? null : failure.message,
      );
    }
  }

  // ------------------------------------------------------------ the end

  /// The account is gone and the engine has wiped this device; clear what the
  /// app keeps around it (the remembered server, a parked link) and open a
  /// fresh runtime. The router then shows sign-in.
  Future<void> _finish() async {
    _challengeId = null;
    state = const DeleteAccountState(done: true);
    try {
      await ref.read(signOutProvider)();
    } on Object {
      // Nothing more to do: the router moves to sign-in when the engine
      // reports signed out.
    }
  }

  static const _badNumber =
      'Enter the number with its country code, like +88017XXXXXXXX.';

  /// E.164, or null. A number typed here has to carry its country code: a
  /// guess would text, or derive a key for, somebody else.
  static String? _normalized(String raw) => PhoneNumbers.normalize(raw);
}
