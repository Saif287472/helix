import 'dart:convert';

import 'package:helix_remote_backend/src/app_error.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

class PrivacyComplianceModule {
  PrivacyComplianceModule(this.db);

  final BackendDatabase db;

  Handler get privacyRouter {
    final router = Router();
    router.get('/export', _exportHandler);
    router.get('/admin/audit', _adminAuditHandler);
    return withAppErrorHandling(router.call);
  }

  Handler get accountRouter {
    final router = Router();
    router.delete('/delete', _deleteAccountHandler);
    return withAppErrorHandling(router.call);
  }

  Future<Response> _exportHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    }

    final accountId = auth['account_id'] as String;
    db.logAudit(
      accountId,
      auth['device_id'] as String?,
      'DATA_EXPORT_REQUESTED',
      request.context['client_ip'] as String?,
      null,
    );

    return Response.ok(
      jsonEncode({'data': db.exportAccountData(accountId)}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _deleteAccountHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    }

    final accountId = auth['account_id'] as String;
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final confirmation = body['confirmation'] as String?;
    if (confirmation != 'DELETE' && confirmation != 'DELETE $accountId') {
      throw AppError.badRequest('Invalid account deletion confirmation');
    }

    db.logAudit(
      accountId,
      auth['device_id'] as String?,
      'ACCOUNT_DELETE_REQUESTED',
      request.context['client_ip'] as String?,
      null,
    );
    await db.deleteAccountData(accountId);

    return Response.ok(
      jsonEncode({'deleted': true, 'account_id': accountId}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> _adminAuditHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    }

    final accountId = auth['account_id'] as String;
    if (auth['is_admin'] != true) {
      db.logAudit(
        accountId,
        auth['device_id'] as String?,
        'ADMIN_ACCESS_DENIED',
        request.context['client_ip'] as String?,
        null,
      );
      throw AppError.forbidden('Admin privileges required');
    }

    db.logAudit(
      accountId,
      auth['device_id'] as String?,
      'ADMIN_AUDIT_READ',
      request.context['client_ip'] as String?,
      null,
    );
    final targetAccountId = request.url.queryParameters['account_id'];
    return Response.ok(
      jsonEncode({'audit': db.getAuditLogs(accountId: targetAccountId)}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
