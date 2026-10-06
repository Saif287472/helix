import 'package:flutter/material.dart';
import 'package:helix_admin/src/features/common/format.dart';
import 'package:helix_admin/src/features/dashboard/metrics_summary.dart';
import 'package:helix_admin/src/features/dashboard/server_controller.dart';
import 'package:helix_admin/src/widgets/dialogs.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// What the operator sees first: the server, its health, the switches that
/// change how it behaves, and live numbers.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.server});

  final ServerController server;

  /// Plain names for the flags the server allow-lists.
  static const flagLabels = {
    'crash_reporting_upload': 'Accept crash reports from apps',
    'minimal_analytics': 'Minimal analytics',
    'group_calls': 'Group calls',
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: server,
      builder: (context, _) {
        final config = server.config;
        if (config == null) {
          return HelixAsyncPanel(
            loading: server.loading || server.error == null,
            error: server.error,
            onRetry: server.refresh,
            child: const SizedBox.shrink(),
          );
        }
        return RefreshIndicator(
          onRefresh: server.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(HelixSpace.md),
            children: [
              _ServerCard(server: server, config: config),
              const SizedBox(height: HelixSpace.md),
              _SwitchesCard(server: server, config: config),
              const SizedBox(height: HelixSpace.md),
              _FlagsCard(server: server),
              const SizedBox(height: HelixSpace.md),
              _MetricsCard(server: server),
            ],
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.trailing});

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(HelixSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: HelixSpace.xs),
          ...children,
        ],
      ),
    ),
  );
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({required this.server, required this.config});

  final ServerController server;
  final AdminConfig config;

  @override
  Widget build(BuildContext context) {
    final ready = server.ready;
    final failing = ready == null
        ? const <String>[]
        : [
            for (final e in ready.checks.entries)
              if (!e.value) e.key,
          ];
    return _Section(
      title: config.serverName.isEmpty ? 'Server' : config.serverName,
      trailing: ready == null
          ? null
          : HelixStatusBadge(
              label: ready.ready ? 'Ready' : 'Not ready',
              color: ready.ready
                  ? HelixStatusColors.positive
                  : HelixStatusColors.danger,
            ),
      children: [
        _Fact('Version', config.version),
        _Fact('Registration', _registration(config.registration)),
        _Fact('Node', config.nodeId),
        if (config.federationDomain != null)
          _Fact('Federation domain', config.federationDomain!),
        _Fact('Attachment limit', formatBytes(config.maxAttachmentBytes)),
        if (failing.isNotEmpty)
          _Note('Failing checks: ${failing.join(', ')}.', error: true),
        if (server.healthNote != null) _Note(server.healthNote!, error: true),
      ],
    );
  }

  static String _registration(RegistrationMode mode) => switch (mode) {
    RegistrationMode.phone => 'Phone number (Helix Global)',
    RegistrationMode.invite => 'Invite code',
    RegistrationMode.closed => 'Closed',
    RegistrationMode.unknown => 'Unknown',
  };
}

class _SwitchesCard extends StatelessWidget {
  const _SwitchesCard({required this.server, required this.config});

  final ServerController server;
  final AdminConfig config;

  Future<void> _maintenance(BuildContext context, bool on) async {
    if (on) {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Turn on maintenance mode?',
        message:
            'The server will answer 503 to every app until you turn it off. '
            'This console keeps working.',
        action: 'Turn on',
      );
      if (!confirmed || !context.mounted) return;
    }
    final problem = await server.setMaintenance(on);
    if (!context.mounted) return;
    showMessage(
      context,
      problem ?? (on ? 'Maintenance mode is on.' : 'Maintenance mode is off.'),
    );
  }

  Future<void> _federation(BuildContext context, bool on) async {
    final problem = await server.setFederation(on);
    if (!context.mounted) return;
    showMessage(
      context,
      problem ?? (on ? 'Federation is on.' : 'Federation is off.'),
    );
  }

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Behaviour',
    children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Maintenance mode'),
        subtitle: const Text('Apps get 503 while it is on.'),
        value: config.maintenance,
        onChanged: server.isBusy('maintenance')
            ? null
            : (on) => _maintenance(context, on),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Federation'),
        subtitle: const Text('Talk to other Helix servers.'),
        value: config.federationEnabled,
        onChanged: server.isBusy('federation')
            ? null
            : (on) => _federation(context, on),
      ),
    ],
  );
}

class _FlagsCard extends StatelessWidget {
  const _FlagsCard({required this.server});

  final ServerController server;

  @override
  Widget build(BuildContext context) {
    final flags = server.flags;
    return _Section(
      title: 'Feature flags',
      children: [
        if (server.flagsNote != null) _Note(server.flagsNote!, error: true),
        if (flags.isEmpty && server.flagsNote == null)
          const _Note('This server has no feature flags.'),
        for (final entry in flags.entries)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(DashboardScreen.flagLabels[entry.key] ?? entry.key),
            subtitle: DashboardScreen.flagLabels.containsKey(entry.key)
                ? Text(entry.key)
                : null,
            value: entry.value,
            onChanged: server.isBusy('flag:${entry.key}')
                ? null
                : (on) async {
                    final problem = await server.setFlag(entry.key, on);
                    if (context.mounted && problem != null) {
                      showMessage(context, problem);
                    }
                  },
          ),
      ],
    );
  }
}

class _MetricsCard extends StatelessWidget {
  const _MetricsCard({required this.server});

  final ServerController server;

  @override
  Widget build(BuildContext context) {
    final m = server.metrics;
    return _Section(
      title: 'Activity',
      children: [
        if (server.metricsNote != null)
          _Note(
            'Metrics are not available. ${server.metricsNote!}',
            error: true,
          )
        else if (m == null)
          const _Note('No metrics yet.')
        else ...[
          Wrap(
            spacing: HelixSpace.sm,
            runSpacing: HelixSpace.sm,
            children: [
              _Stat('Open sockets', _count(m.websocketsOpen)),
              _Stat('Requests served', _count(m.requests)),
              _Stat('Server errors', _share(m)),
              _Stat(
                'Dead jobs',
                _count(m.deadJobs),
                warn: (m.deadJobs ?? 0) > 0,
              ),
              _Stat('Undelivered messages', _count(m.mailboxBacklog)),
              _Stat('Crash reports', _count(m.crashReports)),
            ],
          ),
          const SizedBox(height: HelixSpace.xs),
          const _Note(
            'Request, socket and crash counts are for the node this console '
            'reached and start again from zero when it restarts. Dead jobs '
            'and undelivered messages cover the whole server.',
          ),
        ],
      ],
    );
  }

  static String _count(int? v) => v == null ? '—' : formatCount(v);

  static String _share(MetricsSummary m) {
    final share = m.serverErrorShare;
    if (share == null) return '—';
    return '${(share * 100).toStringAsFixed(share < 0.1 ? 1 : 0)}%';
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: error
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.outline,
      ),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.warn = false});

  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(HelixSpace.sm),
        decoration: BoxDecoration(
          color: warn
              ? HelixStatusColors.cautionContainer
              : scheme.surfaceContainerHighest,
          borderRadius: HelixRadius.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: warn ? HelixStatusColors.onCautionContainer : null,
              ),
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
