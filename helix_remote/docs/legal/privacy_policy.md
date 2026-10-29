# Orbit Home Privacy Policy

**Effective date:** September 25, 2026  
**Version:** `2026-10-23` (revised to say what the service keeps of your phone
number and why; the terms version is unchanged)

This Privacy Policy explains how Orbit Home handles information when you use
the Helix Remote app and the hosted Orbit Home service. It does not govern a
self-hosted Helix server operated by another person; that operator controls
that deployment's information.

## 1. Information we process

Depending on the features you use, Orbit Home may process:

- account information: a client-generated account identifier, a salted one-way
  phone-number hash, display name, profile details, account status,
  cryptographic public keys, and the phone number you signed up with once your
  app reports it back to us (kept sealed, as described below);
- authentication information: phone verification challenges, hashed
  verification codes, invite and recovery-code hashes, device records, session
  and refresh-token records, account-recovery events, and limited audit events;
- service content: encrypted messages, calls, group data, attachments, and the
  metadata needed to route, synchronize, back up, and delete that content;
- network and security information: IP address, request time, device and
  browser information, rate-limit counters, error records, and server or
  application logs;
- push information: a device push token and the information needed to deliver a
  notification or call alert; and
- optional diagnostics: crash or performance information only when you opt in
  to telemetry or another specifically enabled diagnostic feature.

Your phone number verifies the account, and the account is looked up by a
salted hash of it rather than by the number itself. The number reaches us when
we send you an SMS code and, when configured, goes to the SMS provider for
delivery. It also reaches us once more when your app confirms the number it
signed in with, and we keep that report - sealed with AES-256-GCM under a key
stored outside the database, so a copy of the database or a backup does not
give numbers up.

We keep it for one reason: abuse is reported and acted on by the number it
came from. A report to Orbit Home names an account, and the number is what
lets the operator tell which account it was, take action (suspend the account,
ban the number) and answer the person who reported it. Your number is shown to
that operator in the admin console and to no one else: it is not in your
profile, it is never given to another user, and it is never in our logs. A
server that does not hold the sealing key keeps no number at all, and its
console shows only the last four digits.

The app may store your normalized phone number locally in secure device
storage so it can restore your session.

## 2. How we use information

We use information to provide and secure the service, verify phone ownership,
authenticate and recover accounts, route and synchronize encrypted data, enforce
quotas and rate limits, prevent abuse, investigate incidents, comply with law,
respond to support requests, and improve reliability when diagnostic consent is
enabled.

## 3. Service providers and disclosures

We do not sell personal information. Information may be processed by service
providers that host or operate infrastructure, deliver SMS messages, deliver
push notifications, provide abuse protection or support, or maintain backups.
Those providers receive only the information needed for their function and are
expected to protect it.

We may disclose information when required by law, to protect users and the
service, to respond to valid legal process, or as part of a corporate
transaction. We may also retain or share limited information to prevent fraud,
enforce these Terms, or comply with applicable obligations.

## 4. Encryption and security

Helix Remote is designed to use end-to-end encryption for supported message and
attachment content. The service still processes routing, account, device,
timing, quota, and delivery metadata needed to operate the network. No internet
service can guarantee absolute security; a compromised device, account,
recovery code, or endpoint can expose information.

## 5. Retention

Account and profile information is retained while the account is active and
until deletion or another valid retention requirement ends. Authentication
challenges are short-lived and are removed or made unusable according to their
expiry. Encrypted content is retained according to the service's storage and
deletion operations. Unreferenced completed attachments are currently retained
for up to 30 days by default, subject to the limits shown by the service.
Operational logs, rate-limit records, backups, and security records are retained
for as long as reasonably needed for operations, security, legal compliance, and
dispute handling.

## 6. Your choices and rights

Depending on where you live, you may have rights to access, correct, export,
delete, restrict, or object to processing of your information, and to withdraw
consent where processing relies on consent. You can update profile information
and request account deletion from the app. Some information may be retained
where required for security, fraud prevention, backups, or law.

To make a privacy request, contact `privacy@helix.agiletechbd.com`. We may need
to verify your identity before completing a request. Do not email private keys,
passwords, recovery codes, or unnecessary message content.

## 7. International users and children

Orbit Home may be accessed from different countries. Information may be
processed in countries other than your own, subject to the legal and contractual
protections that apply there. By using the service, you consent to that
processing where required by law.

The service is not directed to children who cannot legally enter into this
agreement or provide the required consent. If you believe a child submitted
information without appropriate authorization, contact us so we can
investigate.

## 8. Changes and contact

We may update this policy as the service or applicable requirements change. We
will publish an updated version and effective date. Material changes will be
announced through the service or another reasonable channel. Questions about
this policy may be sent to `privacy@helix.agiletechbd.com`.
