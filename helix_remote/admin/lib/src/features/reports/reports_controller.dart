import 'package:helix_admin/src/features/common/feature_controller.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Reports people filed about accounts. They carry a category and an
/// optional note, never message content.
final class ReportsController extends PagedController<AdminReport> {
  ReportsController(super.ctx, {super.pageSize});

  ReportStatus? _status = ReportStatus.open;
  final Set<String> _resolving = {};

  /// The status filter; null shows every report.
  ReportStatus? get status => _status;

  bool isResolving(String reportId) => _resolving.contains(reportId);

  @override
  Future<Page<AdminReport>> fetch(PageRequest page) =>
      ctx.api.admin.reports(status: _status, page: page);

  Future<void> filterByStatus(ReportStatus? status) {
    _status = status;
    return refresh();
  }

  /// Marks an open report `resolved` or `dismissed`. Returns a problem to
  /// show, or null; a failure leaves the report as it was.
  Future<String?> resolve(String reportId, ReportStatus outcome) async {
    assert(
      outcome == ReportStatus.resolved || outcome == ReportStatus.dismissed,
      'a report is resolved or dismissed',
    );
    if (!_resolving.add(reportId)) return null;
    notifyListeners();
    final problem = await attempt(
      () => ctx.api.admin.resolveReport(reportId, outcome),
    );
    _resolving.remove(reportId);
    if (problem == null) {
      if (_status == null) {
        // Everything is listed: show the new state in place.
        final old = items.firstWhere((r) => r.reportId == reportId);
        replaceWhere(
          (r) => r.reportId == reportId,
          AdminReport(
            reportId: old.reportId,
            reporter: old.reporter,
            subject: old.subject,
            category: old.category,
            status: outcome,
            createdAt: old.createdAt,
            note: old.note,
          ),
        );
      } else {
        removeWhere((r) => r.reportId == reportId);
      }
    } else {
      notifyListeners();
    }
    return problem;
  }
}
