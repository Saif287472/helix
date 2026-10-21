import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/global_server.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/links/helix_code.dart';
import 'package:helix_remote/core/platform/saved_accounts.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_countries.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_state.dart';

/// What a typed setup code looks like, for the line under the field. The
/// screen shows it while typing; [SignInState.codeType] is only known after
/// the code was checked.
enum SetupCodeLook { none, invite, recovery }

SetupCodeLook setupCodeLook(String code) => isHelixRecoveryCode(code)
    ? SetupCodeLook.recovery
    : isHelixInviteCode(code)
    ? SetupCodeLook.invite
    : SetupCodeLook.none;

/// A saved account as the sign-in screen shows it.
typedef SavedAccountLine = ({String id, String title, String detail});

/// The saved accounts the phone page shows, in its words: kept here so the
/// screen never imports `core/` (the architecture test), and so the filter
/// and the masking are one thing the widget tests can pin.
final signInSavedAccountsProvider = Provider<List<SavedAccountLine>>(
  (ref) => savedAccountLinesForGlobalPage(ref.watch(savedAccountsProvider)),
);

/// The saved accounts the Global phone page offers: those on the server the
/// page signs in to, most recent first. An account with a known name is
/// "Rahman / +880 ••••• 0001"; one without shows the number over the
/// server.
List<SavedAccountLine> savedAccountLinesForGlobalPage(
  List<SavedAccountEntry> entries,
) => [
  for (final e in entries)
    if (e.server == kGlobalServerUrl.toString())
      (
        id: e.e164,
        title: e.name.isEmpty ? _masked(e.e164) : e.name,
        detail: e.name.isEmpty ? 'Helix Global' : _masked(e.e164),
      ),
];

String _masked(String e164) =>
    maskNumber(e164, countryCode: _countryCodeOf(e164));

/// The dialling code [e164] starts with, longest match among the known
/// ones; what is left is the national number.
String _countryCodeOf(String e164) {
  var code = SignInState.defaultCountryCode;
  var best = 0;
  for (final c in signInCountries) {
    if (e164.startsWith(c.code) && c.code.length > best) {
      best = c.code.length;
      code = c.code;
    }
  }
  return code;
}
