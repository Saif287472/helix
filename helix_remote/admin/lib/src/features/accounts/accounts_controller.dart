import 'package:helix_admin/src/features/common/feature_controller.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The paged, filtered account list. The server answers with the last four
/// phone digits only; nothing here ever holds a full number.
final class AccountsController extends PagedController<AdminAccount> {
  AccountsController(super.ctx, {super.pageSize});

  AccountStatus? _status;
  String _query = '';

  /// The status filter; null shows every account.
  AccountStatus? get status => _status;

  /// A Helix name prefix or the last four digits; empty for no filter.
  String get query => _query;

  @override
  Future<Page<AdminAccount>> fetch(PageRequest page) => ctx.api.admin.accounts(
    status: _status,
    query: _query.isEmpty ? null : _query,
    page: page,
  );

  /// Changes the filters and loads the first page again.
  Future<void> setFilter({AccountStatus? status, String? query}) {
    _status = status;
    _query = (query ?? _query).trim();
    return refresh();
  }

  Future<void> search(String query) => setFilter(status: _status, query: query);

  Future<void> filterByStatus(AccountStatus? status) =>
      setFilter(status: status);
}

/// One account with its devices, and the actions on it.
final class AccountDetailController extends FeatureController {
  AccountDetailController(super.ctx, this.accountId);

  final String accountId;

  AdminAccountDetail? _detail;
  bool _loading = false;
  String? _error;
  bool _removed = false;
  final Set<String> _busy = {};

  AdminAccountDetail? get detail => _detail;
  bool get loading => _loading;
  String? get error => _error;

  /// The account no longer exists (banned or deleted here, or gone).
  bool get removed => _removed;

  /// Whether an action named [key] (`suspension`, `ban`, `delete`,
  /// `recovery`, `device:<id>`) is running.
  bool isBusy(String key) => _busy.contains(key);

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    final problem = await attempt(() async {
      _detail = await ctx.api.admin.account(accountId);
    });
    _error = problem;
    _loading = false;
    notifyListeners();
  }

  Future<String?> _act(String key, Future<void> Function() action) async {
    if (!_busy.add(key)) return null;
    notifyListeners();
    final problem = await attempt(action);
    _busy.remove(key);
    notifyListeners();
    return problem;
  }

  /// Returns a problem to show, or null.
  Future<String?> suspend({String? reason}) => _act('suspension', () async {
    await ctx.api.admin.suspend(accountId, reason: reason);
    _detail = await ctx.api.admin.account(accountId);
  });

  Future<String?> unsuspend() => _act('suspension', () async {
    await ctx.api.admin.unsuspend(accountId);
    _detail = await ctx.api.admin.account(accountId);
  });

  /// Bans the phone number and deletes the account.
  Future<String?> ban({String? reason}) => _act('ban', () async {
    await ctx.api.admin.ban(accountId, reason: reason);
    _removed = true;
  });

  Future<String?> deleteAccount() => _act('delete', () async {
    await ctx.api.admin.deleteAccount(accountId);
    _removed = true;
  });

  Future<String?> revokeDevice(String deviceId) =>
      _act('device:$deviceId', () async {
        await ctx.api.admin.revokeDevice(accountId, deviceId);
        _detail = await ctx.api.admin.account(accountId);
      });

  /// A single-use recovery code. It is returned to the caller to show once;
  /// this controller does not keep it.
  Future<({AdminRecoveryCode? code, String? problem})>
  createRecoveryCode() async {
    AdminRecoveryCode? code;
    final problem = await _act('recovery', () async {
      code = await ctx.api.admin.createRecoveryCode(accountId);
    });
    return (code: code, problem: problem);
  }
}
