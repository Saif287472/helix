import 'dart:convert';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/identity/api.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/module.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';
import 'package:shelf/shelf.dart';

/// Data export and account deletion for the signed-in account. Holds no
/// tables: the export asks every [ProvidesAccountExport] module for its
/// section, and deletion is identity's, whose hooks make every module purge
/// its rows in the same transaction.
final class ComplianceModule extends ModuleBase {
  ComplianceModule(
    super.context, {
    required this.identity,
    required this.exporters,
  });

  final IdentityApi identity;

  /// Filled as modules are created; read only when a request arrives.
  final List<ProvidesAccountExport> exporters;

  static final _exportLimit = RateLimitPolicy.per(
    'compliance.export',
    5,
    const Duration(days: 1),
  );
  static final _deleteLimit = RateLimitPolicy.per(
    'compliance.delete',
    5,
    const Duration(hours: 1),
  );

  @override
  String get name => 'compliance';

  @override
  void routes(RouteRegistry r) {
    r
      ..add(
        name,
        Routes.exportData,
        _export,
        rateLimit: _exportLimit,
        allowSuspended: true,
      )
      ..add(
        name,
        Routes.deleteAccount,
        _delete,
        rateLimit: _deleteLimit,
        allowSuspended: true,
      );
  }

  /// One repeatable-read snapshot, so the sections agree with each other.
  Future<Response> _export(HelixRequest q) async {
    final accountId = q.device.accountId;
    final sections = await context.db.tx((tx) async {
      await tx.execute(
        'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY',
      );
      return {
        for (final m in exporters) m.name: await m.exportAccount(tx, accountId),
      };
    });
    log.info('account_exported', {'account_id': accountId});
    return Response.ok(
      jsonEncode(
        AccountExport(
          accountId: accountId,
          exportedAt: context.clock.now(),
          sections: sections,
        ).toJson(),
      ),
      headers: {
        'content-type': 'application/json; charset=utf-8',
        'content-disposition': 'attachment; filename="helix-export.json"',
      },
    );
  }

  Future<Response> _delete(HelixRequest q) async {
    final req = q.json(DeleteAccountRequest.fromJson);
    if (req.confirmation != DeleteAccountRequest.expected) {
      throw const ApiError(
        ErrorCode.invalidField,
        message: 'confirmation must be DELETE',
        details: {'field': 'confirmation'},
      );
    }
    final accountId = q.device.accountId;
    // A session token alone does not delete an account: a password, a fresh
    // phone verification or (for accounts with neither) a device signature.
    await identity.confirmOwnership(
      accountId,
      q.device.deviceId,
      authKey: req.currentAuthKey,
      verificationToken: req.verificationToken,
      deviceProof: req.deviceProof,
    );
    await context.db.tx((tx) => identity.deleteAccount(tx, accountId));
    log.info('account_deleted', {'account_id': accountId});
    return noContent();
  }
}
