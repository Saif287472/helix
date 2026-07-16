# Group Election & Membership

## Intended Behavior

LAN groups use deterministic host election with epoch/version checks. The host
is a normal member that forwards messages and enforces admin decisions.

## Invariants

- Host election uses stable identity fingerprints plus epoch.
- Stale host announcements are ignored.
- Membership/admin updates carry versions.
- Duplicate group message IDs are rejected.
- Session bans are enforced until the group session ends.

## Failure Handling

- Graceful handover advertises the next host and incremented epoch.
- Crash election converges to the same host for all remaining members.

## Verification

- `test/phase4_test.dart`
- Manual three-device failover check before release.
