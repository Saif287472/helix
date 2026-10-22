# The sign-in feature

`features/sign_in/` is the way into Helix Remote. It exists because sign-in has
more rules than any other screen, and those rules have to live in one place
rather than in a widget.

## What it is for

A person either signs in to **Helix Global** (the default, and the only server
the app ever advertises) or joins a **personal server** behind a hidden corner
or a shared link. After a v2 change to the protocol's `PhoneVerifyResponse` the
flow learned something v1 could not know up front: whether the number already
has an account, and whether that account has a password. So a number with a
password goes straight to the password page ("Use a code instead" shows the
number for confirmation first, then asks for a texted code). A new number gets
the code and name pages; an existing account on a server that does not text
goes to the name page.

The sign-in page also lists the accounts signed in here (a tap opens one) and
the numbers this phone remembers (`SavedAccountLine` from
`core/platform/saved_accounts.dart`), with "Remember me on this device" on by
default: a remembered number's tap fills it and opens the password step, and
the x forgets it. Only numbers are stored; passwords never are.

## The rule that is easiest to get wrong

**Sign-in opens on the plain Global page.** No server chooser, no host-your-own
guide, no explanation of personal servers. Someone who wants one already knows,
and they find it through three taps in the bottom-right corner or a link
somebody sent them.

Everything else follows from that: the Global page has no back button, because
there is nothing before it, and its `Terms & Privacy` link is the only legal
text on it.

## The files

| File | What it holds |
|---|---|
| `application/sign_in_state.dart` | The immutable state: mode, page, the fields, and the derived things (`e164`, `isNewAccount`, `requiresTerms`, `phoneLabel`). |
| `application/sign_in_controller.dart` | The page machine. Every transition, every call into the engine, the server switch. |
| `application/sign_in_copy.dart` | Every string a screen can show, and the mapping from a server error to one of them. |
| `presentation/sign_in_screen.dart` | The connector: the page machine's state and the saved numbers go into `orbit_ui`'s `SignInScreen`, and its taps come back as controller calls. It holds no rules. |
| `presentation/widgets/sign_in_frame.dart` | The page layout, and `AdvancedModeCorner` (the hidden entry). |
| `presentation/widgets/sign_in_fields.dart` | The fields, with the widget keys the tests drive. |
| `presentation/widgets/legal_documents_sheet.dart` | The versioned Terms and Privacy Policy. |

## Why the copy lives in its own file

An exception's `toString()` must never reach a person: it can name a server, a
path or a challenge id. So every failure becomes one of a fixed set of
sentences, chosen by the server's `ErrorCode` in `sign_in_copy.dart`. Adding a
server error means adding a sentence there, and a test can then assert the exact
wording.

## Why the state is one object

Every page reads the same `SignInState`, so there is no way for the phone page
to show a different phone page than the SMS page's subtitle. The phone number
is stored as a country code and a national part separately, because it is shown
the way it is dialled (`+880 170 000-0000`) and sent as E.164
(`+8801700000000`).

## What a test may rely on

`sign_in_flow_test.dart` runs the whole page machine headlessly, overriding
`runtimeFactoryProvider` with a factory that throws. That means:

- anything decided **before** an engine call is testable without a server: the
  corner, the back rules, the number format, the code prefixes, the Terms.
- anything decided **by** the server is not: which page follows a verified
  code, whether a password is right. Those are the engine's tests and
  `server/test/client/`, and this feature calls them rather than re-deciding.

The widget keys (`advanced-mode-corner`, `advanced-mode-button`, `phone-field`,
`code-field`, `password-sign-in-field`, `otp-field`, `name-field`,
`terms-checkbox`) and `AdvancedModeCorner.tapWindow` / `.tapsToReveal` are part
of the contract: the rules are checked by driving them, so renaming one has to
break a test on purpose.