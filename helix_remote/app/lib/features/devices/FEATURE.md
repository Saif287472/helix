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
