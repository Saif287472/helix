# ADR 036: Free call time is metered where the relay can enforce it

Status: accepted (2026-10-28). Phase 3 of `docs/product/ORBIT_PREMIUM_PLAN.md`;
builds on ADR-035 (plans) and ADR-034 (group calls).

Plan of record: `docs/architecture/ARCHITECTURE_V2_PLAN.md` (§12 change log).

## Context

The owner wants Free to carry call time: 100 voice and 30 video minutes a
day, claimed by tapping a button, kept three days (so at most 300 and 90 are
held), spent by the person who starts the call; Orbit Premium is unlimited.
The limit should be as strict as possible. Calls are end-to-end encrypted and
relay-only (every byte goes through the owner's coturn), so the server never
sees media; it sees only the signalling it already routes.

A client-side meter can be bypassed by a modified app. What a client cannot
bypass is the relay: it carries a call only while the credential in the call's
TURN allocation is valid.

## Decision

1. **Credentials are per call and need a reservation.** `POST /v1/calls/turn`
   (replacing `GET`) takes `call_id`, `role` (`caller` or `callee`), `media`
   (`voice` or `video`) and, for a group call, `room_id`. For a metered caller
   the `billing` module sets minutes aside from the right pool (oldest claim
   first) and the credential's expiry is the end of that reserved time.
   When the call ends (the server sees the `end` signal) unused whole minutes
   go back to the claims they came from. Charging is per started minute.
2. **The caller pays.** The callee's credential is issued only for a call that
   was offered to them (`calls.call_legs`, kept 12 hours) and ends with the
   caller's reservation. A group call's legs share the starter's reservation
   (`room_id`), charged once per clock minute.
3. **Free means metered.** An account is metered when plans are on
   (`billing_enabled`) and it is not Premium (nor trial or grace). Otherwise the
   credential is unmetered and lasts eight hours (a long call is no longer cut
   at an hour). With plans off nothing is recorded.
4. **A claim is once a day**, the day running midnight to midnight in Dhaka
   (UTC+6), and expires at the end of its third day. Claims are rows
   (`billing.call_claims`); reservations are rows (`billing.call_reservations`,
   `call_reservation_calls`).
5. **Two coturn relays.** The server cannot tell voice from video, and a
   modified app could call video "voice". The voice relay has a hard
   per-session bandwidth cap (coturn `max-bps`), its own port (3479) and its
   own secret (`HELIX_TURN_VOICE_SECRET`, which must differ from the main
   secret). A voice credential is signed with the voice secret, so it works only
   on the capped relay; mislabelled video is starved. Video (and screen
   sharing, which counts as video) uses the main relay. The relay port range is
   widened to 49160-49800 (main 49160-49600, voice 49601-49800).
6. **coturn must re-check expiry quickly.** Tested against coturn 4.6:
   a credential's expiry is checked at allocation time and again only when the
   client's nonce goes stale, so the cut-off lands within `stale-nonce`
   seconds. The config sets `stale-nonce=30`. A call that outlives its
   credential loses its relay at that point and ends.
7. **The apps warn and end by the same clock.** The credential's `expires_at`
   is the end of the reserved time and `metered: true` tells the app so. The
   engine warns two minutes before it and ends the call at it
   (`CallEnd.callTimeOver`); the relay is the backstop. A caller with an
   empty pool is refused before anything rings (`quota_exceeded`,
   `details.reason: call_time`).
8. **Calls with another server: the caller's own server meters.** A Helix Global
   account answering a call from a personal server is not metered.
9. **Privacy.** The server now keeps who called whom for a call (12 hours), and
   for a Free caller how long the call's time was (claims and reservations,
   kept 7 days after they end). No content, no media. The records are in the
   account export and are deleted with the account.

## Known limits (stated, not hidden)

- The cut-off is coarse: up to about `stale-nonce` seconds late, plus the
  charge is rounded up to started minutes.
- A call that starts as voice and turns into video mid-call stays on the voice
  relay and is starved; the app does not support the switch today.
- With no voice relay configured, voice calls still spend voice minutes but are
  not bandwidth-capped.
- Group-call metering assumes the starter's device asks for credentials first;
  a late leg under an expired room reservation fails to relay.
- Not tested on real phones against a real coturn with WebRTC; the server,
  engine and app are covered by tests, and coturn's behaviour was tested with
  its own client tools.

## Consequences

- New `.env` lines (`HELIX_TURN_VOICE_URLS`, `HELIX_TURN_VOICE_SECRET`), a new
  coturn instance, new ports to forward and open, and migrations (billing 3,
  calls 4).
- The wire contract changes (`POST /v1/calls/turn`, `TurnCredentials.metered`,
  two billing routes); fixtures and docs follow.
- Old apps still call `GET /v1/calls/turn`, which no longer exists. There are no
  real users yet, so there is no compatibility shim.
