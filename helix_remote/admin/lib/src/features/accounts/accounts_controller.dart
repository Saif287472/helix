import 'package:helix_admin/src/features/common/feature_controller.dart';
import 'package:helix_remote_api/v2.dart' show ApiException;
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The paged, filtered account list. The server answers with the last four
/// phone digits only; nothing here ever holds a full number.
final class AccountsController extends PagedController<AdminAccount> {
  AccountsController(super.ctx, {super.pageSize});

  AccountStatus? _status;
  String _query = '';

  /// The status filter; null shows every account.
  AccountStatus? get status => _status;

  /// An Orbit name prefix or the last four digits; empty for no filter.
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
  AdminAccountPlan? _plan;
  CallTime? _callTime;
  bool _loading = false;
  String? _error;
  bool _removed = false;
  final Set<String> _busy = {};

  AdminAccountDetail? get detail => _detail;

  /// The account's Orbit Premium state and overrides; null until read, or
  /// when this server has no plans to show.
  AdminAccountPlan? get plan => _plan;

  /// The account's call minutes (ADR-036); null until read or when unknown.
  CallTime? get callTime => _callTime;
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
    if (problem == null) await _loadPlan();
  }

  /// Best effort: a failure leaves the plan card out, it is not an error of
  /// the page.
  Future<void> _loadPlan() async {
    try {
      _plan = await ctx.api.admin.accountPlan(accountId);
    } on Object {
      _plan = null;
    }
    try {
      _callTime = await ctx.api.admin.accountCallTime(accountId);
    } on Object {
      _callTime = null;
    }
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

  /// Gives Orbit Premium time without a payment (ADR-035).
  Future<String?> grantPlan(int months) => _act('plan', () async {
    await ctx.api.admin.grantPlan(accountId, months);
    await _loadPlan();
  });

  /// Gives free call minutes (three days, outside the daily caps).
  Future<String?> grantCallTime({
    required int voice,
    required int video,
    required String reason,
  }) => _act('plan', () async {
    await ctx.api.admin.grantCallTime(
      accountId,
      voiceMinutes: voice,
      videoMinutes: video,
      reason: reason,
    );
    await _loadPlan();
  });

  /// Changes one limit for this account (a support case).
  Future<String?> setOverride(
    PlanLimitKey key, {
    required int value,
    required String reason,
    int? days,
  }) => _act('plan', () async {
    await ctx.api.admin.setPlanOverride(
      accountId,
      key,
      value: value,
      reason: reason,
      days: days,
    );
    await _loadPlan();
  });

  Future<String?> clearOverride(PlanLimitKey key) => _act('plan', () async {
    await ctx.api.admin.clearPlanOverride(accountId, key);
    await _loadPlan();
  });

  /// Ends Orbit Premium now. A problem when the account had none.
  Future<String?> revokePlan() async {
    var hadNone = false;
    final problem = await _act('plan', () async {
      try {
        await ctx.api.admin.revokePlan(accountId);
      } on ApiException catch (e) {
        if (e.code != ErrorCode.notFound) rethrow;
        hadNone = true;
      }
      await _loadPlan();
    });
    return hadNone ? 'This account has no Premium to end.' : problem;
  }

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
