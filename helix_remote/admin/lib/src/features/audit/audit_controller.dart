import 'package:helix_admin/src/features/common/feature_controller.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The audit log, newest first. Every action in this console writes a row;
/// codes, tokens and passwords are never in it.
final class AuditController extends PagedController<AuditEntry> {
  AuditController(super.ctx, {super.pageSize});

  @override
  Future<Page<AuditEntry>> fetch(PageRequest page) =>
      ctx.api.admin.audit(page: page);
}
