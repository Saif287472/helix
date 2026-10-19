import 'package:helix_remote/core/links/helix_code.dart';

/// What a typed setup code looks like, for the line under the field. The
/// screen shows it while typing; [SignInState.codeType] is only known after
/// the code was checked.
enum SetupCodeLook { none, invite, recovery }

SetupCodeLook setupCodeLook(String code) => isHelixRecoveryCode(code)
    ? SetupCodeLook.recovery
    : isHelixInviteCode(code)
    ? SetupCodeLook.invite
    : SetupCodeLook.none;
