/// Versioned legal-document text shared by the Global backend and client.
///
/// The operator should review these documents for its jurisdiction and business
/// requirements before publishing them as a production legal notice. The
/// server records the version accepted during registration.
abstract final class HelixLegalDocuments {
  static const termsVersion = '2026-09-25';
  static const privacyVersion = '2026-09-25';
  static const effectiveDate = 'September 25, 2026';
  static const termsTitle = 'Helix Global Terms of Service';
  static const privacyTitle = 'Helix Global Privacy Policy';

  static const termsOfService = '''
Helix Global Terms of Service

Effective date: September 25, 2026
Version: 2026-09-25

1. Agreement and scope
These Terms of Service ("Terms") govern your use of the Helix Global service, the Helix Remote mobile application, and related hosted features that Helix makes available at the Global service address. A self-hosted Helix server is operated by its own administrator; its administrator's terms and policies govern that deployment.

By creating an account or using Helix Global, you agree to these Terms and the Privacy Policy. If you do not agree, do not create an account or use the service. You must be legally able to enter into this agreement. If local law requires parental or guardian consent, you must obtain that consent before using the service.

2. Accounts and phone numbers
You must provide accurate information, keep your account credentials and recovery codes confidential, and use only an account you are authorized to control. Helix Global permits one account per verified phone number. If a number already belongs to an account, you must use the account's authorized recovery process rather than attempting to create a replacement account.

You are responsible for activity performed through your account and devices. Tell us promptly if you believe an account or device has been compromised. Recovery codes and device links are bearer credentials: anyone who obtains one may be able to take over the associated account, so store them securely and do not share them.

3. Acceptable use
You may not use Helix Global to:
- break the law or facilitate violence, abuse, harassment, exploitation, or infringement of another person's rights;
- distribute malware, spam, phishing material, unsolicited advertising, or abusive automated traffic;
- impersonate another person, evade access controls, probe or attack the service without authorization, or interfere with other users or the service's operation;
- upload malicious, illegal, infringing, or excessively large material;
- reverse engineer, bypass security controls, or misuse the service except where applicable law expressly permits such activity despite these restrictions; or
- use the service to build or operate a competing service from Helix Global data without written permission.

We may investigate suspected abuse and may take reasonable steps to protect the service, other users, and the public, including rate limiting or temporarily blocking abusive traffic.

4. Messages, content, and encryption
You retain ownership of content you submit. You give Helix only the limited rights needed to host, transmit, synchronize, back up, and display that content so the service can operate. You are responsible for having the necessary rights and permissions for content you send or receive.

Helix Remote is designed to encrypt end-to-end message and attachment content on supported paths. Keys and decrypted content are not intended to be available to Helix Global. Encryption does not remove obligations under these Terms and does not guarantee that a compromised device, recovery code, or account cannot reveal content.

Do not use Helix Global as the only copy of important data. We may remove content that violates these Terms or applicable law, and we may retain or disclose information where required by law or necessary to protect the service and its users.

5. Attachments, storage, and availability
The Global service currently provides a 100 MB maximum attachment size, a 5 GB account storage quota, and a default 30-day retention period for completed attachments that are no longer referenced. These limits may be changed for security, abuse prevention, or operational reasons. The limits returned by the service control where they differ from this description.

The service is provided on an "as available" basis. We do not promise uninterrupted access, a particular response time, or that every message or call will be delivered. You are responsible for maintaining backups and an alternative way to contact people when the service is unavailable.

6. Suspension, termination, and changes
You may stop using the service at any time and may request account deletion through the application or the support contact below. We may suspend or terminate access for a material breach, security risk, unlawful activity, nonpayment of any applicable fee, or a valid legal requirement. Where appropriate, we will provide notice and an opportunity to resolve the issue.

We may update these Terms to reflect changes in the service or applicable requirements. We will publish an updated version and effective date. The version and acceptance time recorded for an account apply to the registration for which acceptance was made; continued use after an effective update means you accept the updated Terms where permitted by law.

7. Disclaimers and liability
TO THE MAXIMUM EXTENT PERMITTED BY LAW, THE SERVICE IS PROVIDED "AS IS" AND "AS AVAILABLE", WITHOUT WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT. WE DO NOT GUARANTEE THAT THE SERVICE WILL BE ERROR-FREE, SECURE AT ALL TIMES, OR SUITABLE FOR A PARTICULAR PURPOSE.

TO THE MAXIMUM EXTENT PERMITTED BY LAW, HELIX AND ITS OPERATORS, EMPLOYEES, AND CONTRACTORS WILL NOT BE LIABLE FOR INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, EXEMPLARY, OR PUNITIVE DAMAGES, OR FOR LOST PROFITS, DATA, GOODWILL, OR BUSINESS OPPORTUNITY, ARISING FROM OR RELATED TO THE SERVICE. NOTHING IN THESE TERMS EXCLUDES LIABILITY THAT CANNOT BE EXCLUDED BY LAW.

8. Indemnity
You agree to defend and indemnify Helix and its operators from claims, losses, liabilities, and expenses arising from your content, your use of the service in violation of these Terms, or your violation of another person's rights. This obligation applies only to the extent permitted by applicable law.

9. Contact
Questions about these Terms may be sent to support@helix.agiletechbd.com. Include enough information for us to investigate, but never send passwords, private keys, recovery codes, or unnecessary message content.

10. General
If a provision is unenforceable, the remaining provisions remain in effect. A waiver must be written and signed by the party granting it. These Terms are the entire agreement concerning the Global service and replace earlier statements about that service. If local law conflicts with a provision, local mandatory law controls to the extent of the conflict.
''';

  static const privacyPolicy = '''
Helix Global Privacy Policy

Effective date: September 25, 2026
Version: 2026-09-25

1. Who this policy covers
This Privacy Policy explains how Helix Global handles information when you use the Helix Remote app and the hosted Helix Global service. It does not govern a self-hosted Helix server operated by another person; that operator controls that deployment's information.

2. Information we process
Depending on the features you use, Helix Global may process:
- account information: a client-generated account identifier, a salted one-way phone-number hash, an optional last-four-digit display hint, display name, profile details, account status, and cryptographic public keys;
- authentication information: phone verification challenges, hashed verification codes, invite and recovery-code hashes, device records, session and refresh-token records, account-recovery events, and limited audit events;
- service content: encrypted messages, calls, group data, attachments, and the metadata needed to route, synchronize, back up, and delete that content;
- network and security information: IP address, request time, device and browser information, rate-limit counters, error records, and server or application logs;
- push information: a device push token and the information needed to deliver a notification or call alert; and
- optional diagnostics: crash or performance information only when you opt in to telemetry or another specifically enabled diagnostic feature.

The raw phone number is used transiently to request an SMS verification message and, when configured, is sent to the SMS provider. Helix Global's registration database identifies accounts by a salted phone-number hash rather than storing the full number as the account lookup key. The app may store your normalized phone number locally in secure device storage so it can restore your session.

3. How we use information
We use information to provide and secure the service, verify phone ownership, authenticate and recover accounts, route and synchronize encrypted data, enforce quotas and rate limits, prevent abuse, investigate incidents, comply with law, respond to support requests, and improve reliability when diagnostic consent is enabled.

4. Service providers and disclosures
We do not sell personal information. Information may be processed by service providers that host or operate infrastructure, deliver SMS messages, deliver push notifications, provide abuse protection or support, or maintain backups. Those providers receive only the information needed for their function and are expected to protect it.

We may disclose information when required by law, to protect users and the service, to respond to valid legal process, or as part of a corporate transaction. We may also retain or share limited information to prevent fraud, enforce these Terms, or comply with applicable obligations.

5. Encryption and security
Helix Remote is designed to use end-to-end encryption for supported message and attachment content. The service still processes routing, account, device, timing, quota, and delivery metadata needed to operate the network. No internet service can guarantee absolute security; a compromised device, account, recovery code, or endpoint can expose information.

6. Retention
Account and profile information is retained while the account is active and until deletion or another valid retention requirement ends. Authentication challenges are short-lived and are removed or made unusable according to their expiry. Encrypted content is retained according to the service's storage and deletion operations. Unreferenced completed attachments are currently retained for up to 30 days by default, subject to the limits shown by the service. Operational logs, rate-limit records, backups, and security records are retained for as long as reasonably needed for operations, security, legal compliance, and dispute handling.

7. Your choices and rights
Depending on where you live, you may have rights to access, correct, export, delete, restrict, or object to processing of your information, and to withdraw consent where processing relies on consent. You can update profile information and request account deletion from the app. Some information may be retained where required for security, fraud prevention, backups, or law.

To make a privacy request, contact privacy@helix.agiletechbd.com. We may need to verify your identity before completing a request. Do not email private keys, passwords, recovery codes, or unnecessary message content.

8. International users
Helix Global may be accessed from different countries. Information may be processed in countries other than your own, subject to the legal and contractual protections that apply there. By using the service, you consent to that processing where required by law.

9. Children
The service is not directed to children who cannot legally enter into this agreement or provide the required consent. If you believe a child submitted information without appropriate authorization, contact us so we can investigate.

10. Changes and contact
We may update this policy as the service or applicable requirements change. We will publish an updated version and effective date. Material changes will be announced through the service or another reasonable channel. Questions about this policy may be sent to privacy@helix.agiletechbd.com.
''';
}
