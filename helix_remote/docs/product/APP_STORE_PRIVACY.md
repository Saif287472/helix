# Helix Remote App Store Privacy Declarations

Status: Phase 18 draft for store review  
Date: 2026-06-19

Use this file as the source checklist for store privacy forms. Final answers
must be reviewed against the exact release build and store form wording.

## Data Linked To The User

- Account ID and username.
- Device IDs and device names.
- Contacts/friend state created inside Helix Remote.
- Abuse reports and safety actions.
- Encrypted message/attachment/backup metadata needed for sync and delivery.

## Data Not Collected In Current Scope

- Address book contacts are not mandatory and are not uploaded by current code.
- Precise location is not collected by current code.
- Advertising ID is not collected by current code.
- Behavioral advertising or sale of personal data is not part of the product.
- Plaintext message contents are not collected by supported backend APIs.

## Permissions

- Camera/microphone: only for calls and user-initiated media capture flows when
  implemented by platform UI.
- Notifications: for generic message/call alerts without plaintext content.
- Files/storage picker: for user-selected encrypted attachment import/export.

## Required Manual Review Before Submission

- Verify the built app manifests and permission prompts.
- Verify push provider payloads in the deployed environment.
- Verify no optional analytics or crash SDK was added after this checklist.
- Verify all blocked security-review items are excluded from store marketing.
