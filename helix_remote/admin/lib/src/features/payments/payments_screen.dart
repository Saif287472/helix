import 'package:flutter/material.dart';
import 'package:helix_admin/src/features/common/format.dart';
import 'package:helix_admin/src/features/payments/payments_controller.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/widgets/console_kit.dart';
import 'package:helix_admin/src/widgets/console_sheet.dart';
import 'package:helix_admin/src/widgets/dialogs.dart';
import 'package:helix_admin/src/widgets/paged_list.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The Payments place: requests for Orbit Premium waiting for the operator,
/// and the prices and numbers people pay to.
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key, required this.adminContext, this.pageSize});

  final AdminContext adminContext;
  final int? pageSize;

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  late final PaymentsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PaymentsController(
      widget.adminContext,
      pageSize: widget.pageSize ?? PageRequest.defaultLimit,
    )..refresh();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open(AdminPaymentRequest request) async {
    final outcome = await showConsoleSheet<String>(
      context: context,
      child: _RequestSheet(request: request, controller: _controller),
    );
    if (outcome != null && mounted) showMessage(context, outcome);
  }

  Future<void> _settings() async {
    final current = await _controller.loadSettings(
      (problem) => showMessage(context, problem),
    );
    if (current == null || !mounted) return;
    final next = await showDialog<BillingSettings>(
      context: context,
      builder: (_) => _SettingsDialog(initial: current),
    );
    if (next == null || !mounted) return;
    final problem = await _controller.saveSettings(next);
    if (!mounted) return;
    showMessage(context, problem ?? 'Prices and numbers saved.');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final pending = _controller.status == PaymentRequestStatus.pending;
      return PagedListView<AdminPaymentRequest>(
        controller: _controller,
        emptyIcon: Icons.payments_outlined,
        emptyTitle: pending ? 'No payments waiting' : 'Nothing here',
        emptyMessage: pending
            ? 'When someone sends a transaction ID for Orbit Premium it '
                  'appears here for you to check and approve.'
            : 'Requests with this status appear here.',
        gap: 12,
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ConsoleHeading('Orbit Premium payments'),
            const SizedBox(height: 14),
            ConsoleChipRow(
              children: [
                for (final (label, value) in const [
                  ('Waiting', PaymentRequestStatus.pending),
                  ('Approved', PaymentRequestStatus.approved),
                  ('Rejected', PaymentRequestStatus.rejected),
                  ('Expired', PaymentRequestStatus.expired),
                ])
                  ConsoleChip(
                    label: label,
                    selected: _controller.status == value,
                    onTap: () => _controller.filterByStatus(value),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _settings,
              style: ConsoleButtons.outlined,
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Prices and numbers'),
            ),
          ],
        ),
        itemBuilder: (context, request) =>
            _Tile(request: request, onTap: () => _open(request)),
      );
    },
  );
}

String _methodName(PaymentMethod m) => switch (m) {
  PaymentMethod.bkash => 'bKash',
  PaymentMethod.nagad => 'Nagad',
  PaymentMethod.unknown => 'Unknown method',
};

String _monthsLabel(int months) => months == 1 ? '1 month' : '$months months';

class _Tile extends StatelessWidget {
  const _Tile({required this.request, required this.onTap});

  final AdminPaymentRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = request.request;
    return Semantics(
      button: true,
      child: ConsoleCard(
        radius: 12,
        padding: const EdgeInsets.all(14),
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BDT ${r.amount} · ${_monthsLabel(r.months)} · '
                    '${_methodName(r.method)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: HelixConsoleColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    request.accountName ?? 'Unnamed account',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: HelixConsoleColors.textBody,
                    ),
                  ),
                  if (request.accountPhone != null)
                    Text(
                      request.accountPhone!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontFamily: 'monospace',
                        color: HelixConsoleColors.textMuted,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'ID ${r.trxId} · ${formatTime(r.createdAt)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: HelixConsoleColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (r.status == PaymentRequestStatus.pending)
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: HelixConsoleColors.textFaint,
              )
            else
              ConsolePill(
                label: switch (r.status) {
                  PaymentRequestStatus.approved => 'Approved',
                  PaymentRequestStatus.rejected => 'Rejected',
                  PaymentRequestStatus.expired => 'Expired',
                  _ => 'Unknown',
                },
                tone: r.status == PaymentRequestStatus.approved
                    ? ConsoleTone.ok
                    : ConsoleTone.neutral,
                upper: true,
              ),
          ],
        ),
      ),
    );
  }
}

/// One request in full: what to look for in bKash or Nagad, and the two ways
/// to answer it. It pops with a line for the queue to show.
class _RequestSheet extends StatelessWidget {
  const _RequestSheet({required this.request, required this.controller});

  final AdminPaymentRequest request;
  final PaymentsController controller;

  Future<void> _approve(BuildContext context) async {
    final id = request.request.requestId;
    final problem = await controller.approve(id);
    if (!context.mounted) return;
    if (problem != null) return showMessage(context, problem);
    Navigator.of(
      context,
    ).pop('Approved: ${_monthsLabel(request.request.months)} added.');
  }

  Future<void> _reject(BuildContext context) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RejectDialog(),
    );
    if (reason == null || !context.mounted) return;
    final problem = await controller.reject(request.request.requestId, reason);
    if (!context.mounted) return;
    if (problem != null) return showMessage(context, problem);
    Navigator.of(context).pop('Rejected. The person will see why.');
  }

  @override
  Widget build(BuildContext context) {
    final r = request.request;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final busy = controller.isDeciding(r.requestId);
        final pending = r.status == PaymentRequestStatus.pending;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          children: [
            ConsoleCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ConsoleCardLabel('Look for this payment'),
                  const SizedBox(height: 12),
                  ConsoleProperty(label: 'Amount', value: 'BDT ${r.amount}'),
                  ConsoleProperty(
                    label: 'Method',
                    value: _methodName(r.method),
                    mono: false,
                  ),
                  ConsoleProperty(label: 'Transaction ID', value: r.trxId),
                  ConsoleProperty(
                    label: 'Time bought',
                    value: _monthsLabel(r.months),
                    mono: false,
                  ),
                  ConsoleProperty(
                    label: 'Sent',
                    value: formatTime(r.createdAt),
                    mono: false,
                  ),
                  const SizedBox(height: 10),
                  const ConsoleCardLabel('From this account'),
                  const SizedBox(height: 8),
                  ConsoleProperty(
                    label: 'Name',
                    value: request.accountName ?? 'Not set',
                    mono: false,
                  ),
                  ConsoleProperty(
                    label: 'Number',
                    value: request.accountPhone ?? 'Not reported',
                  ),
                  if (r.reason != null)
                    ConsoleProperty(
                      label: 'Reason given',
                      value: r.reason!,
                      mono: false,
                    ),
                ],
              ),
            ),
            if (pending) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: busy ? null : () => _approve(context),
                      style: ConsoleButtons.filled,
                      child: const Text('Approve'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : () => _reject(context),
                      style: ConsoleButtons.outlined,
                      child: const Text('Reject'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Reject this payment'),
    content: TextField(
      controller: _reason,
      autofocus: true,
      maxLength: RejectPaymentRequest.maxReasonLength,
      decoration: const InputDecoration(
        labelText: 'Why (the person reads this)',
      ),
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _reason.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _reason.text.trim()),
        child: const Text('Reject'),
      ),
    ],
  );
}

/// The three prices (taka) and the two numbers people pay to. A blank number
/// switches that method off.
class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.initial});

  final BillingSettings initial;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final _one = TextEditingController(
    text: '${widget.initial.priceOneMonth}',
  );
  late final _six = TextEditingController(
    text: '${widget.initial.priceSixMonths}',
  );
  late final _twelve = TextEditingController(
    text: '${widget.initial.priceTwelveMonths}',
  );
  late final _bkash = TextEditingController(
    text: widget.initial.bkashNumber ?? '',
  );
  late final _nagad = TextEditingController(
    text: widget.initial.nagadNumber ?? '',
  );

  @override
  void dispose() {
    for (final c in [_one, _six, _twelve, _bkash, _nagad]) {
      c.dispose();
    }
    super.dispose();
  }

  BillingSettings? _read() {
    final one = int.tryParse(_one.text.trim());
    final six = int.tryParse(_six.text.trim());
    final twelve = int.tryParse(_twelve.text.trim());
    bool ok(int? v) => v != null && v > 0 && v <= BillingSettings.maxPrice;
    if (!ok(one) || !ok(six) || !ok(twelve)) return null;
    String? number(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    return BillingSettings(
      priceOneMonth: one!,
      priceSixMonths: six!,
      priceTwelveMonths: twelve!,
      bkashNumber: number(_bkash),
      nagadNumber: number(_nagad),
    );
  }

  Widget _field(TextEditingController c, String label, {bool number = true}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          maxLength: number ? BillingSettings.maxNumberLength : 6,
          decoration: InputDecoration(labelText: label, counterText: ''),
          onChanged: (_) => setState(() {}),
        ),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Prices and numbers'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(_one, 'Price for 1 month (BDT)', number: false),
          _field(_six, 'Price for 6 months (BDT)', number: false),
          _field(_twelve, 'Price for 12 months (BDT)', number: false),
          _field(_bkash, 'bKash number (blank: not offered)'),
          _field(_nagad, 'Nagad number (blank: not offered)'),
          const Text(
            'The crossed-out price people see is 6 or 12 times the monthly '
            'price. Plans only open when Plans and payments is switched on '
            'in Configuration.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _read() == null
            ? null
            : () => Navigator.pop(context, _read()),
        child: const Text('Save'),
      ),
    ],
  );
}
