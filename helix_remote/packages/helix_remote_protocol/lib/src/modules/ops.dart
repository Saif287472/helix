import 'package:helix_remote_protocol/src/json.dart';

/// `GET /v1/health/live`.
final class LiveResponse {
  const LiveResponse({required this.time});

  final DateTime time;

  JsonMap toJson() => {'status': 'ok', 'time': toWireTime(time)};

  factory LiveResponse.fromJson(JsonReader json) =>
      LiveResponse(time: json.time('time'));
}

/// `GET /v1/health/ready`: 200 when every check passes, else 503. Check
/// names only; no versions, paths or counts (those are admin metrics).
final class ReadyResponse {
  const ReadyResponse({required this.ready, required this.checks});

  final bool ready;

  /// e.g. `{"database": true, "event_bus": true, "storage": true}`.
  final Map<String, bool> checks;

  JsonMap toJson() => {'ready': ready, 'checks': checks};

  factory ReadyResponse.fromJson(JsonReader json) {
    final checks = json.object('checks');
    return ReadyResponse(
      ready: json.boolean('ready'),
      checks: {for (final k in checks.json.keys) k: checks.boolean(k)},
    );
  }
}

enum RegistrationMode implements WireEnum {
  /// Helix Global: phone number verification.
  phone('phone'),

  /// Personal servers: an invite code from the operator.
  invite('invite'),
  closed('closed'),
  unknown('unknown');

  const RegistrationMode(this.wire);

  @override
  final String wire;
}

/// `GET /v1/server`: what a client needs before signing in.
final class ServerInfo {
  const ServerInfo({
    required this.name,
    required this.version,
    required this.registration,
    required this.maxAttachmentBytes,
    required this.termsVersion,
    required this.privacyVersion,
    this.federationDomain,
    this.features = const {},
  });

  final String name;

  /// Server software version.
  final String version;
  final RegistrationMode registration;
  final int maxAttachmentBytes;
  final String termsVersion;
  final String privacyVersion;
  final String? federationDomain;

  /// Feature flags clients act on (allow-listed by the server).
  final Map<String, bool> features;

  JsonMap toJson() => compact({
    'name': name,
    'version': version,
    'registration': registration.wire,
    'max_attachment_bytes': maxAttachmentBytes,
    'terms_version': termsVersion,
    'privacy_version': privacyVersion,
    'federation_domain': federationDomain,
    if (features.isNotEmpty) 'features': features,
  });

  factory ServerInfo.fromJson(JsonReader json) {
    final features = json.optObject('features');
    return ServerInfo(
      name: json.string('name'),
      version: json.string('version'),
      registration: json.enumValue(
        'registration',
        RegistrationMode.values,
        orElse: RegistrationMode.unknown,
      ),
      maxAttachmentBytes: json.integer('max_attachment_bytes'),
      termsVersion: json.string('terms_version'),
      privacyVersion: json.string('privacy_version'),
      federationDomain: json.optString('federation_domain'),
      features: {
        if (features != null)
          for (final k in features.json.keys) k: features.boolean(k),
      },
    );
  }
}

/// `GET /v1/server/legal`.
final class LegalDocuments {
  const LegalDocuments({
    required this.termsVersion,
    required this.termsTitle,
    required this.terms,
    required this.privacyVersion,
    required this.privacyTitle,
    required this.privacy,
  });

  final String termsVersion;
  final String termsTitle;
  final String terms;
  final String privacyVersion;
  final String privacyTitle;
  final String privacy;

  JsonMap toJson() => {
    'terms_version': termsVersion,
    'terms_title': termsTitle,
    'terms': terms,
    'privacy_version': privacyVersion,
    'privacy_title': privacyTitle,
    'privacy': privacy,
  };

  factory LegalDocuments.fromJson(JsonReader json) => LegalDocuments(
    termsVersion: json.string('terms_version'),
    termsTitle: json.string('terms_title'),
    terms: json.string('terms'),
    privacyVersion: json.string('privacy_version'),
    privacyTitle: json.string('privacy_title'),
    privacy: json.string('privacy'),
  );
}

/// `POST /v1/telemetry/crash`: only when the user opted in. Field values are
/// redacted on the device first and capped by the server.
final class CrashReport {
  const CrashReport({required this.name, this.fields = const {}});

  static const maxFields = 32;
  static const maxValueLength = 2000;

  final String name;
  final Map<String, String> fields;

  JsonMap toJson() => {'name': name, 'fields': fields};

  factory CrashReport.fromJson(JsonReader json) {
    final fields = json.optObject('fields');
    return CrashReport(
      name: json.nonEmpty('name'),
      fields: {
        if (fields != null)
          for (final k in fields.json.keys) k: fields.string(k),
      },
    );
  }
}

/// `GET /v1/account/export`: everything the server holds about the
/// account, one section per module (module-defined JSON; no message
/// content exists server-side beyond undelivered sealed envelopes, which
/// are counted, not exported).
final class AccountExport {
  const AccountExport({
    required this.accountId,
    required this.exportedAt,
    required this.sections,
  });

  final String accountId;
  final DateTime exportedAt;
  final Map<String, Object?> sections;

  JsonMap toJson() => {
    'account_id': accountId,
    'exported_at': toWireTime(exportedAt),
    'sections': sections,
  };

  factory AccountExport.fromJson(JsonReader json) => AccountExport(
    accountId: json.nonEmpty('account_id'),
    exportedAt: json.time('exported_at'),
    sections: json.object('sections').json,
  );
}

/// `DELETE /v1/account`: [confirmation] must be exactly `DELETE`.
final class DeleteAccountRequest {
  const DeleteAccountRequest({this.confirmation = expected});

  static const expected = 'DELETE';

  final String confirmation;

  JsonMap toJson() => {'confirmation': confirmation};

  factory DeleteAccountRequest.fromJson(JsonReader json) =>
      DeleteAccountRequest(confirmation: json.string('confirmation'));
}

/// `GET /.well-known/helix-server`: federation identity.
final class ServerIdentityDocument {
  const ServerIdentityDocument({
    required this.serverId,
    required this.publicKey,
    required this.apiBase,
  });

  final String serverId;

  /// Ed25519 key that signs this server's S2S requests (base64url).
  final String publicKey;
  final String apiBase;

  JsonMap toJson() => {
    'server_id': serverId,
    'public_key': publicKey,
    'api_base': apiBase,
  };

  factory ServerIdentityDocument.fromJson(JsonReader json) =>
      ServerIdentityDocument(
        serverId: json.nonEmpty('server_id'),
        publicKey: json.nonEmpty('public_key'),
        apiBase: json.nonEmpty('api_base'),
      );
}
