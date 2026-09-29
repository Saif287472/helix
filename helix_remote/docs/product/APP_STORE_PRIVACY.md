# Helix Remote App Store Privacy Declarations

Status: Phase 18 draft for store review  
Date: 2026-06-19

Use this file as the source checklist for store privacy forms. Final answers
must be reviewed against the exact release build and store form wording.

## Data Linked To The User

- Account ID and hashed phone number (`phone_hash`; there is no username
  field).
  The raw phone number is sent to the server only when requesting an SMS code;
  the server checks it against the hash, passes it to the SMS gateway
  (BulkSMSBD) for delivery, and does not store it from that request.
- Password-derived verifier and password-wrapped identity key: Argon2id
  salt/parameters, a salted hash of a key derived from the password, and the
  account identity private key encrypted under another password-derived key
  (`account_passwords`). The password itself is never collected.
- Encrypted, text-only chat history backup (`history_backups`), which the
  server cannot decrypt.
- Device IDs and device names.
- Contacts/friend state created inside Helix Remote.
- Abuse reports and safety actions.
- Encrypted message/attachment/backup metadata needed for sync and delivery.
- If the user opts into contacts sync: salted hashes of their phone-book
  numbers, sent only to check which are already Helix users on the same
  server (`POST /contacts/match`). Phone-book names and unmatched numbers
  never leave the device.

## Data Not Collected In Current Scope

- Address book contacts are not mandatory (opt-in, deny-and-continue works,
  re-askable later) and raw phone numbers are never uploaded by current code
  - only salted hashes, and only for the contacts-match lookup above.
- Precise location is not collected by current code.
- Advertising ID is not collected by current code.
- Behavioral advertising or sale of personal data is not part of the product.
- Plaintext message contents are not collected by supported backend APIs.
- OTP codes and invite codes are not stored server-side (hashes only). Phone
  numbers are matched only by `phone_hash`.

## Permissions

- Camera/microphone: only for calls and user-initiated media capture flows when
  implemented by platform UI.
- Contacts (read-only): only if the user opts into contacts sync from the
  Contacts tab; used solely to compute phone-hash matches, never to read or
  transmit raw contact data. Degrades gracefully if denied.
- Notifications: for generic message/call alerts without plaintext content,
  and for "new sign-in on your account" alerts. OTP codes arrive by SMS, not
  by notification.
- Files/storage picker: for user-selected encrypted attachment import/export.

## Required Manual Review Before Submission

- Verify the built app manifests and permission prompts.
- Verify push provider payloads in the deployed environment.
- Verify no optional analytics or crash SDK was added after this checklist.
- Verify all blocked security-review items are excluded from store marketing.
