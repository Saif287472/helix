# devices

Linked devices (Phase A3b): `/devices` (list, rename, remove, lost or stolen,
sign out all others), `/devices/link` (approve a new device), `/devices/activity`
(the account's security log) and `/link-device` (this device shows a QR code
to be linked).

## Approving a device (safety checks)

1. The code must be a Helix link code naming **this** server
   (`DevicesGateway.inspectLink`), else a sentence says why.
2. The person is shown the server and a short **check number** derived from the
   code (`linkCheckNumber`), which the new device shows too, and is told not to
   approve a device that is not in their hands.
3. When the phone has a screen lock it must be passed (`DeviceAuthenticator`)
   before anything is sent.
4. Only then does the engine seal the account key to the new device
   (`DeviceService.approveLink`).

A QR scanner exists on Android/iOS (`qrScannerBuilderProvider`); Windows gets
the paste field only.

## Linking this device

`LinkThisDeviceController` asks for the restore step (`postSignInProvider`)
*before* the engine signs in, so the router shows "restore or skip" with no
flash of the tabs. Reachable while signed out (the router allows
`/link-device`); sign-in opens it from "Link from another device instead" on
the password page and on the take-over confirmation.

## Not here

Renaming and removal use the server list; a revoked device finds out through
the engine's revocation path (wipe), not this feature.

## Is this your account? (new device)

After the other device approves, the engine hands over a `LinkProposal` before
it keeps anything. `LinkThisDeviceController` turns it into the
`LinkThisStep.confirming` step: masked phone, `~name` and the key code, with
"Yes, this is my account" and "No, cancel". Yes registers the device; No, the
close button, leaving the page and 5 minutes without an answer
(`linkConfirmTimeoutProvider`) discard the approval (the engine's
`SignInException(linkDeclined)`), take back the restore step and offer a new
code. An approval that does not verify (`untrusted`), an expired code and an
offline sign-in each have a sentence. `LinkRequest.accountKeyCode` is what the
approving device shows so the two codes can be compared.

## Sending history after a link

History transfers are never automatic. When the approval is done the approve
page offers "Send history to this device": the controller remembers the account's
device ids before approving and sends only to the device that has appeared since
(`sendHistoryToNewDevice`); if it has not finished joining the sentence says to
wait and the button can be pressed again. The new device accepts or declines
under the restore step or Settings > Backup.
