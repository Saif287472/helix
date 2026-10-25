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
        // Everything is listed: show the new state in place, with the two
        // people still named and numbered on it.
        // The list may have been refreshed while the answer was on the wire;
        // a report that is no longer in it shows the server's state at the
        // next refresh (AUD-17b-1).
        final shown = items.where((r) => r.reportId == reportId).firstOrNull;
        if (shown != null) {
          replaceWhere(
            (r) => r.reportId == reportId,
            shown.copyWith(status: outcome),
          );
        }
      } else {
        removeWhere((r) => r.reportId == reportId);
      }
    } else {
      notifyListeners();
    }
    return problem;
  }
}
