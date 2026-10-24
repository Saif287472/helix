# messaging module

Mailbox delivery (ADR-028, REST_V2.md "messaging"). Schema `messaging`.
Facade: `api.dart` (`MessagingApi`). Groups, calls and identity signals all
deliver through it.

## Model

- **One row per recipient device** in `mailbox`, hash-partitioned by
  device (16 partitions). It is deleted when the device acks
  (cumulative). Undelivered rows expire after 30 days (`messaging.expire`,
  every 10 minutes).
- **Restored database** (review batch 9): `device_seq.last_seq` is the
  device's head, the highest `seq` ever given (`MailboxStore.head`). A
  cursor above it (`MessagingApi.resume`, used by `GET /v1/mailbox` and the
  realtime upgrade) is read as 0, and `seq_head` tells the client to reset;
  an ack above it deletes nothing (`MailboxStore.ack`). The log says
  `mailbox_cursor_ahead`.
- **Per-device `seq`** comes from `device_seq` under the row lock of an
  `INSERT … ON CONFLICT DO UPDATE`, taken in device-id order so overlapping
  sends cannot deadlock. Concurrent sends from any node never share a
  number. Gaps are allowed and numbers are never reused.
- **Quota: the newest 10,000 per device.** `device_seq.pending` counts
  undelivered rows. A delivery that takes a device above 10,000 deletes that
  device's oldest rows in the same transaction (`MailboxStore.trim`, counted
  in `helix_mailbox_trimmed_total`), as expiry would. Until 2026-10-09 the
  whole send failed with `quota_exceeded` instead, so one device that never
  collected its mail (an unused PC that was never signed out) blocked every
  send to its account and its groups (review A-01). The price: a sender who
  floods an offline device pushes out its oldest undelivered envelopes,
  including other people's.
- **Only active devices get rows.** `deliver` first reads the devices with
  `IdentityApi.lockActiveDevices` (`FOR SHARE`, in id order) and skips any
  that are not active. A revoke updates the device row, so it waits for a
  delivery holding that lock, and its `onDeviceRevoked` hook then purges
  what the delivery stored. A delivery after a revoke sees it (review A-09:
  before, a revoke between the device-list check and the insert left rows
  for 30 days).
- **Fan-out is two statements** for any number of devices: `unnest` over
  `_uuid` / `_int8` / `_bytea` arrays.
- **Idempotency:** `sends` records each request id for 7 days, per
  (sender account, sender device, id) since migration 3, so another server
  reusing an id cannot suppress someone else's message. A retry answers
  `replayed: true` and stores nothing.

## Sending (`POST /v1/messages`)

Limited per device (`messaging.send`: 200 at once, 5 per second, checked
before the body is read) and per account (`messaging.send_account`: 400 at
once, 10 per second); over either, `rate_limited`.

Stored sends also draw on the account's **stored-envelope budget**
(`messaging.stored_account`: 50,000 units at once, 250 per second), which
group sends share (`MessagingApi.chargeStored`). A unit is one started
16 KiB of payload for one recipient device (`storedUnits`), so a short text
to a few devices costs a few units and a 256 KiB payload to 1,100 devices
costs 17,600. The rate limiter charges a cost above the capacity as the
capacity, so a large send is slow, never impossible. Ephemeral sends store
nothing and are not charged. With a server storage budget set
(`HELIX_STORAGE_BUDGET_BYTES`), a payload over one unit while the server is
over it gets `quota_exceeded` (`reason: server_storage`); shorter ones still
go through (review A-02, A-03). Presence for urgent
pushes and ephemeral delivery is read once per send (`Presence.online`,
one `getAll`), not once per device, and a fan-out writes its push jobs and
its parked envelopes one statement each (`Outbox.enqueueMany`,
`EphemeralStore.putAll`): the cost of a send is bounded by its work, not by
its device count (AUD-3-1). The `helix_mailbox_backlog` gauge counts
undelivered rows at scrape time.

1. **Validate:** ids, payload sizes (256 KiB per device), at most 1,100
   devices, never the sending device itself.
2. **Device lists:** each listed account must be addressed on all its
   active devices (the sender's own: all except the sending one), or
   `device_list_stale` with `StaleDevices` details.
3. **Blocks:** devices of recipients who blocked the sender are dropped
   (`BlockPolicy`, which the people module installs in S4), and the
   response names those accounts in `blocked_by`: the send still succeeds
   for everyone else (the sender's own devices, other recipients).
4. **Ephemeral sends** (`ephemeral: true`) go to online devices only: each
   device's envelope is parked for 60 s under `msg:eph:<ref>:<device>` (one
   `putAll` for the whole fan-out), and `realtime.ephemeral` on the bus
   carries `{r: ref, d: [devices]}` in chunks. A socket takes its own value,
   so an ephemeral envelope is read once and never to two devices.
5. **Stored sends:** charge the stored-envelope budget (before any relay
   to another server), then allocate seqs, insert rows, trim devices over
   their quota and record the send in one transaction. After commit,
   `mailbox.wake` goes out on the bus in chunks of at most
   `MessagingModule.busChunk` devices (a `NOTIFY` payload is capped at
   7,900 bytes). Urgent sends to offline devices enqueue `messaging.push`
   for all of them with one statement (one pending job per device).

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

## Federation

Recipients may be `uuid@domain`. The send is checked locally first, then
each remote server is relayed to through `MessageRelay` (the federation
module), then the local part is stored. Stale device lists from several
servers come back together, accounts qualified. Sends relayed by another
server enter through `MessagingApi.receive` and follow the same path
(`_accept`). Foreign senders are stored qualified: `sender_account` is
`text` since migration 2.
