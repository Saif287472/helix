import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/global_server.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/links/helix_code.dart';
import 'package:helix_remote/core/platform/account_slots.dart';
import 'package:helix_remote/core/platform/saved_accounts.dart';
import 'package:helix_remote/core/push/account_badges.dart';
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

/// The id prefix of a line that stands for an account still signed in on
/// this device: tapping it opens the account, and it has no x (it is
/// removed from the Accounts page, which signs it out).
const signedInLinePrefix = 'open:';

/// Whether [line] opens an account signed in here, rather than asking for a
/// password.
bool opensSignedInAccount(SavedAccountLine line) =>
    line.id.startsWith(signedInLinePrefix);

/// The saved accounts the phone page shows, in its words: kept here so the
/// screen never imports `core/` (the architecture test), and so the filter
/// and the masking are one thing the widget tests can pin.
final signInSavedAccountsProvider = Provider<List<SavedAccountLine>>(
  (ref) => [
    ...signedInAccountLines(
      ref.watch(accountsProvider).signedIn,
      unread: ref.watch(accountUnreadProvider).value ?? const {},
    ),
    ...savedAccountLinesForGlobalPage(
      ref.watch(savedAccountsProvider),
      except: ref.watch(accountsProvider).signedIn,
    ),
  ],
);

/// The accounts signed in on this device, on any server, most recent first:
/// "Rahman / +880 ••••• 0001 · 3 unread · signed in".
///
/// [unread] is what each account's last read mailbox counted: an account that
/// is not on screen is notified of nothing, so the number is how it says it
/// has something waiting. An account with nothing waiting says only that it is
/// signed in.
List<SavedAccountLine> signedInAccountLines(
  List<AccountSlot> slots, {
  Map<String, int> unread = const {},
}) => [
  for (final s in slots)
    (
      id: '$signedInLinePrefix${s.id}',
      title: s.name.isNotEmpty
          ? s.name
          : s.e164.isNotEmpty
          ? _masked(s.e164)
          : 'Account on ${_serverLabel(s.server)}',
      detail: [
        if (s.name.isNotEmpty && s.e164.isNotEmpty) _masked(s.e164),
        if (s.name.isEmpty || s.e164.isEmpty) _serverLabel(s.server),
        if ((unread[s.id] ?? 0) > 0) '${unread[s.id]} unread',
        'signed in',
      ].join(' · '),
    ),
];

/// The saved accounts the Global phone page offers: those on the server the
/// page signs in to, most recent first, less any of [except] (they are
/// listed as signed in). An account with a known name is
/// "Rahman / +880 ••••• 0001"; one without shows the number over the
/// server.
List<SavedAccountLine> savedAccountLinesForGlobalPage(
  List<SavedAccountEntry> entries, {
  List<AccountSlot> except = const [],
}) => [
  for (final e in entries)
    if (e.server == kGlobalServerUrl.toString() &&
        !except.any((s) => s.e164 == e.e164 && s.server == e.server))
      (
        id: e.e164,
        title: e.name.isEmpty ? _masked(e.e164) : e.name,
        detail: e.name.isEmpty ? 'Orbit Global' : _masked(e.e164),
      ),
];

String _serverLabel(String server) => server == kGlobalServerUrl.toString()
    ? 'Orbit Global'
    : (Uri.tryParse(server)?.host ?? server);

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
