# messaging module

Mailbox delivery (ADR-028, REST_V2.md "messaging"). Schema `messaging`.
Facade: `api.dart` (`MessagingApi`). Groups, calls and identity signals all
deliver through it.

## Model

- **One row per recipient device** in `mailbox`, hash-partitioned by
  device (16 partitions). It is deleted when the device acks
  (cumulative). Undelivered rows expire after 30 days (`messaging.expire`,
  every 10 minutes).
- **Per-device `seq`** comes from `device_seq` under the row lock of an
  `INSERT … ON CONFLICT DO UPDATE`. Concurrent sends from any node never
  share a number. Gaps are allowed and numbers are never reused.
  `device_seq.pending` counts undelivered rows. Above 10,000 the send fails
  with `quota_exceeded`.
- **Fan-out is two statements** for any number of devices: `unnest` over
  `_uuid` / `_int8` / `_bytea` arrays.
- **Idempotency:** `sends` records each request id for 7 days. A retry
  answers `replayed: true` and stores nothing.

## Sending (`POST /v1/messages`)

1. **Validate:** ids, payload sizes (256 KiB per device), at most 1,100
   devices, never the sending device itself.
2. **Device lists:** each listed account must be addressed on all its
   active devices (the sender's own: all except the sending one), or
   `device_list_stale` with `StaleDevices` details.
3. **Blocks:** devices of recipients who blocked the sender are dropped
   silently (`BlockPolicy`, which the people module installs in S4).
4. **Ephemeral sends** (`ephemeral: true`) go to online devices only: the
   envelope is parked in the ephemeral store for 60 s, and
   `realtime.ephemeral` on the bus tells the socket's node.
5. **Stored sends:** allocate seqs, insert rows, and record the send in
   one transaction. After commit, `mailbox.wake` goes out on the bus (in
   chunks of 150 devices). Urgent sends to offline devices enqueue
   `messaging.push` (one pending per device).

## Push (`messaging.push` job)

A data-only wake-up through `PushProvider`: `{t: message|call|call_ended}`
and nothing else. It is skipped if the device came online meanwhile. A
token the provider no longer knows is dropped through identity.

## Server-generated envelopes

| Kind | To | From |
|---|---|---|
| `account_signal` | the account's own devices (except the subject) | identity `onAccountSignal`; new sign-ins are urgent |
| `device_list_change` | the account's own devices (except the new one) | identity `onDeviceListChanged` |
| `prekeys_low` | that device | keys `onPrekeysLow` |

The server keeps no record of who talks to whom, so it cannot tell peers
about new devices or identity keys. Peers learn from `device_list_stale` on
their next send, and from the AIK in the next bundle or prekey message
(CRYPTO_V2.md §2).

## Hooks

`onDeviceRevoked` deletes the device's mailbox and sequence row.
