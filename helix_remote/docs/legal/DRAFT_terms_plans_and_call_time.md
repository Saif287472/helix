# DRAFT: terms for plans, call time and payments

Status: **draft for the operator's legal review. Not live.** Nothing in the app or server serves this text.
Needed before `billing_enabled` is switched on for real users (`docs/product/ORBIT_PREMIUM_PLAN.md`, section 7).
Bracketed items are facts only the operator knows. Written from how the system behaves (ADR-035, ADR-036);
the wording and its fit with Bangladeshi law are for qualified counsel.

## What to change when approved

1. Add the section below to `terms_of_service.md` (between today's sections 4 and 5; renumber).
2. Add a sentence to section 3 or 4 that relayed call media is not stored and its content is end-to-end encrypted.
3. Update both runtime copies and bump the version together:
   `packages/helix_remote_domain/lib/domain/legal_documents.dart` and
   `packages/helix_remote_protocol/lib/src/legal.dart` (and `docs/legal/README.md`). New sign-ups must then name the new
   version (`HELIX_TERMS_VERSION` overrides it; leave that unset). Existing accounts keep the version they accepted;
   tell them in the app or by notice before the change applies to them.
4. Update `PRIVACY_POLICY.md` for the records plans add: subscription periods, payment requests (the TrxID and amount you
   typed), call durations per day (not who was called beyond what the call log already holds).

## Proposed section: Plans, call time and payments

**Plans.** Orbit Home offers a Free plan and a paid plan called Orbit Premium. Messaging, end-to-end encryption,
calls within the call time below, backup and restore, and account export and deletion are available on Free.
Premium raises storage, file-size, retention, device and backup limits, removes the call-time limits, and unlocks
downloadable theme, ringtone and animation packs. The limits that apply to your account are shown in the
application and control where they differ from this description.

**Trial.** A phone number may receive one free Premium trial of 7 days. The trial is not renewed or restarted by
deleting and re-creating an account.

**Call time.** Free accounts receive a daily amount of call time, claimed in the application, for voice calls and for
video calls separately [currently 100 and 30 minutes; the Dhaka calendar day]. Unclaimed time expires after
3 days. The person who starts a call uses their call time, counted by the started minute, for as long as the call
runs through our relay. A call ends when the time reserved for it ends. Premium accounts are not limited, subject to
fair use below.

**Payment.** Premium is paid by mobile wallet transfer [bKash or Nagad, to the number shown in the application] and
confirmed by us after you submit the transaction ID. Access starts when we confirm the payment, usually within
[time], and extends any time you already have. [Price and period.] You are responsible for sending the correct
amount to the number shown. Submitting a transaction ID that is false, or one that belongs to someone else's
payment, is a breach of these Terms and may end your access.

**Refunds.** [Operator's policy: for example, payments are not refundable once confirmed, except where the law
requires or where we confirmed a payment in error.]

**When Premium ends.** You have a grace period of 3 days. After it, Free limits apply again. We do not delete your
messages or files early because a plan ended; files already stored stay until their retention ends, and you may
need to free space before sending new large files.

**Fair use.** We may limit or suspend an account whose use harms the service or other people, including sharing one
paid account among many people or abusing the relay for traffic that is not a call.

**Changes.** We may change plan limits and prices. A change to a price does not affect time you already paid for.
We will show changes in the application before they apply to you.
