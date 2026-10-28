import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/plans/application/plan_models.dart';
import 'package:helix_remote/features/plans/application/plans_providers.dart';
import 'package:helix_remote/shared/format.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// You > Orbit Premium: what the plan adds, what it costs, and how to pay.
///
/// A payment is made outside the app (bKash or Nagad) and only its
/// transaction ID is sent; the operator approves it by hand. Built from the
/// kit's ordinary rows, notices and fields (no prototype screen exists for it;
/// recorded in `orbit/DEVIATIONS.md`).
class PremiumPage extends ConsumerStatefulWidget {
  const PremiumPage({super.key});

  @override
  ConsumerState<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends ConsumerState<PremiumPage> {
  final _trx = TextEditingController();
  int _months = 6;
  PayMethod? _method;

  @override
  void dispose() {
    _trx.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(billingPlanProvider);
    final plan = async.value;
    if (plan == null) {
      return orbit.OrbitYouPage(
        title: 'Orbit Premium',
        children: [
          if (async.hasError)
            orbit.OrbitLoadFailed(
              title: 'Premium could not be loaded.',
              onRetry: () => ref.invalidate(billingPlanProvider),
            )
          else
            const orbit.OrbitPageLoading(),
        ],
      );
    }
    if (!plan.enabled) {
      return const orbit.OrbitYouPage(
        title: 'Orbit Premium',
        children: [
          orbit.OrbitEmptyState(
            icon: orbit.OrbitIcons.crownSimple,
            title: 'Plans are not open yet',
            text: 'Everything works the same for everyone for now.',
          ),
        ],
      );
    }
    final purchase = ref.watch(planPurchaseProvider);
    final targets = plan.targets;
    final method = _method ?? plan.firstMethod;
    final open = plan.open;
    final last = plan.last;

    return orbit.OrbitYouPage(
      title: 'Orbit Premium',
      children: [
        _hero(plan),
        if (open != null)
          orbit.OrbitInlineNotice(
            kind: orbit.OrbitNoticeKind.info,
            text:
                'Your ${_monthsLabel(open.months)} payment (${open.trxId}) is '
                'waiting for approval. It is usually done within a day.',
          )
        else if (last != null && last.state == RequestState.rejected)
          orbit.OrbitInlineNotice(
            kind: orbit.OrbitNoticeKind.error,
            text:
                'Your last request (${last.trxId}) was not accepted'
                '${last.reason == null ? '' : ': ${last.reason}'}. '
                'Check the transaction ID and send it again.',
          )
        else if (last != null && last.state == RequestState.expired)
          orbit.OrbitInlineNotice(
            kind: orbit.OrbitNoticeKind.warning,
            text:
                'Your last request (${last.trxId}) was not answered in time. '
                'Send it again.',
          ),
        orbit.OrbitSection(title: 'What Premium adds', rows: _perks(plan)),
        if (open == null) ..._buy(plan, targets, method, purchase),
      ],
    );
  }

  Widget _hero(PlanView plan) {
    final end = plan.periodEnd;
    if (plan.isPremium && end != null) {
      return orbit.OrbitHeroCard(
        icon: orbit.OrbitIcons.crownSimple,
        tone: plan.inGrace ? orbit.OrbitHeroTone.warn : orbit.OrbitHeroTone.ok,
        title: 'You have Orbit Premium',
        sub: plan.inGrace
            ? 'It ended on ${planDate(end)}. It keeps working for a few more '
                  'days; add time to keep it.'
            : 'Until ${planDate(end)}.',
      );
    }
    return const orbit.OrbitHeroCard(
      icon: orbit.OrbitIcons.crownSimple,
      title: 'You are on the Free plan',
      sub:
          'Chats are unlimited on every plan. Premium adds room for more '
          'devices, bigger files and longer storage.',
    );
  }

  List<Widget> _perks(PlanView plan) {
    final free = plan.limits;
    final pro = plan.premiumLimits;
    orbit.OrbitListRow perk(
      orbit.OrbitGlyph icon,
      int colour,
      String title,
      String premium, {
      String? now,
    }) => orbit.OrbitListRow(
      icon: icon,
      iconColor: colour,
      title: title,
      sub: plan.isPremium || now == null ? '' : 'Now: $now',
      value: premium,
    );
    return [
      perk(
        orbit.OrbitIcons.devices,
        2,
        'Linked devices',
        '${pro.maxDevices}',
        now: '${free.maxDevices}',
      ),
      perk(
        orbit.OrbitIcons.database,
        6,
        'Attachment storage',
        formatBytes(pro.attachmentQuotaBytes),
        now: formatBytes(free.attachmentQuotaBytes),
      ),
      perk(
        orbit.OrbitIcons.paperclip,
        1,
        'Largest file',
        formatBytes(pro.maxAttachmentBytes),
        now: formatBytes(free.maxAttachmentBytes),
      ),
      perk(
        orbit.OrbitIcons.clock,
        4,
        'Files kept for',
        '${pro.attachmentRetentionDays} days',
        now: '${free.attachmentRetentionDays} days',
      ),
      perk(
        orbit.OrbitIcons.cloudArrowUp,
        0,
        'Backup room',
        formatBytes(pro.backupQuotaBytes),
        now: formatBytes(free.backupQuotaBytes),
      ),
    ];
  }

  List<Widget> _buy(
    PlanView plan,
    List<PayTarget> targets,
    PayMethod? method,
    PlanPurchaseState purchase,
  ) {
    if (targets.isEmpty) {
      return const [
        orbit.OrbitInlineNotice(
          kind: orbit.OrbitNoticeKind.info,
          text: 'Paying for Premium is not open yet.',
        ),
      ];
    }
    final price = plan.prices.where((p) => p.months == _months).firstOrNull;
    final target = targets.where((t) => t.method == method).firstOrNull;
    return [
      orbit.OrbitSection(
        title: plan.isPremium ? 'Add time' : 'Choose how long',
        rows: [for (final p in plan.prices) _priceRow(p)],
      ),
      orbit.OrbitSection(
        title: 'Step 1: pay',
        footer: price == null
            ? ''
            : 'Send BDT ${price.price} to the number below, then come back '
                  'here with the transaction ID from the message you get.',
        rows: [
          for (final t in targets)
            orbit.OrbitListRow(
              icon: orbit.OrbitIcons.tag,
              iconColor: 3,
              title: t.method.label,
              value: t.number,
              sub: t.method == method ? 'Tap to copy the number' : '',
              trailing: t.method == method
                  ? const orbit.OrbitIcon(orbit.OrbitIcons.checkCircle)
                  : null,
              onTap: () {
                setState(() => _method = t.method);
                Clipboard.setData(ClipboardData(text: t.number));
                orbit.showOrbitToast(context, 'Number copied');
              },
            ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          orbit.OrbitSpace.gutter,
          18,
          orbit.OrbitSpace.gutter,
          0,
        ),
        child: orbit.OrbitTextField(
          label: 'Step 2: transaction ID',
          controller: _trx,
          hint: 'For example 8N7A6D5EE7',
          helper: target == null
              ? ''
              : 'From the ${target.method.label} message.',
          error: purchase.error ?? '',
          mono: true,
          maxLength: 20,
          enabled: !purchase.busy,
          autofillHints: const [],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          orbit.OrbitSpace.gutter,
          4,
          orbit.OrbitSpace.gutter,
          0,
        ),
        child: orbit.OrbitButton(
          label: 'Send for approval',
          block: true,
          busy: purchase.busy,
          onPressed: purchase.busy || method == null
              ? null
              : () async {
                  final sent = await ref
                      .read(planPurchaseProvider.notifier)
                      .submit(
                        months: _months,
                        method: method,
                        trxId: _trx.text,
                      );
                  if (sent && mounted) {
                    _trx.clear();
                    orbit.showOrbitToast(context, 'Sent. We will check it.');
                  }
                },
        ),
      ),
    ];
  }

  Widget _priceRow(PriceView p) {
    final selected = p.months == _months;
    return orbit.OrbitListRow(
      icon: selected ? orbit.OrbitIcons.checkCircle : orbit.OrbitIcons.circle,
      iconColor: selected ? 1 : 5,
      title: _monthsLabel(p.months),
      subWidget: p.savePercent > 0
          ? Row(
              children: [
                Text(
                  'BDT ${p.listPrice}',
                  style: const TextStyle(
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(width: 8),
                Text('Save ${p.savePercent}%'),
              ],
            )
          : null,
      value: 'BDT ${p.price}',
      onTap: () => setState(() => _months = p.months),
    );
  }

  static String _monthsLabel(int months) =>
      months == 1 ? '1 month' : '$months months';
}
