import 'package:helix_admin/src/features/common/feature_controller.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Invite codes for servers that register people by invite. The server keeps
/// only a hash of each code: the code is shown once, when it is created.
final class InvitesController extends PagedController<AdminInvite> {
  InvitesController(super.ctx, {super.pageSize});

  bool _creating = false;
  final Set<String> _cancelling = {};

  bool get creating => _creating;
  bool isCancelling(String inviteId) => _cancelling.contains(inviteId);

  @override
  Future<Page<AdminInvite>> fetch(PageRequest page) =>
      ctx.api.admin.invites(page: page);

  /// A new invite. The code is returned for the caller to show once; this
  /// controller does not keep it.
  Future<({CreatedInvite? invite, String? problem})> create() async {
    if (_creating) return (invite: null, problem: null);
    _creating = true;
    notifyListeners();
    CreatedInvite? invite;
    final problem = await attempt(() async {
      invite = await ctx.api.admin.createInvite();
    });
    _creating = false;
    notifyListeners();
    if (problem == null) await refresh();
    return (invite: invite, problem: problem);
  }

  Future<String?> cancel(String inviteId) async {
    if (!_cancelling.add(inviteId)) return null;
    notifyListeners();
    final problem = await attempt(() => ctx.api.admin.cancelInvite(inviteId));
    _cancelling.remove(inviteId);
    notifyListeners();
    if (problem == null) await refresh();
    return problem;
  }
}
