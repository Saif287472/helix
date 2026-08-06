# Module: privacy_compliance

Status: current. Follows the template in `messaging.module.md`.

## Purpose

The user-facing data-protection surface: export everything the server holds
about an account, delete the account, and let an admin read the audit log.

## Owned files

- `privacy_compliance.dart` - `PrivacyComplianceModule` and two routers.

## Route table

Two routers, mounted at different prefixes because the delete endpoint
belongs to the account rather than to a privacy namespace.

### `privacyRouter` - `/api/v1/privacy`

| Method | Path | Handler | Notes |
|---|---|---|---|
| GET | `/export` | `_exportHandler` | Everything stored for the calling account. |
| GET | `/admin/audit` | `_adminAuditHandler` | Admin only. `?account_id=` narrows it. |

### `accountRouter` - `/api/v1/account`

| Method | Path | Handler | Notes |
|---|---|---|---|
| DELETE | `/delete` | `_deleteAccountHandler` | Requires `confirmation` of `DELETE` or `DELETE <account_id>`. |

## Error codes this module throws

The [`AppError`](../app_error.dart) shape: `.forbidden` for a missing
session or a non-admin hitting the audit route, and `.badRequest` for a
missing or wrong deletion confirmation.

## Dependencies

- `BackendDatabase` (`../database.dart`) - `exportAccountData`,
  `deleteAccountData`, `getAuditLogs`.
- The `is_admin` claim injected by `_authMiddleware`. It comes from one of two
  places: the static admin API token (which carries the capability directly,
  since no account row backs it), or the account's stored `accounts.is_admin`
  column. It is deliberately **not** derived from the account id — that check
  used to be `adminAccountIds.contains(account_id)` over `{'admin'}`, and
  because `account_id` is client-chosen at registration, whoever registered
  that id first became the operator.

## Gotchas

- **A denied admin-audit attempt is itself audited** (`ADMIN_ACCESS_DENIED`)
  before the 403 is thrown. Failed privilege escalation is exactly what an
  audit log is for.
- **Every route here writes an audit row**, including the successful export
  and the delete request - the record has to outlive the account.
- **The typed confirmation is the only guard on deletion.** There is no
  soft-delete or grace period; `deleteAccountData` is immediate.
