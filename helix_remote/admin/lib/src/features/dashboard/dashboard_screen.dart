import 'package:flutter/material.dart';
import 'package:helix_admin/src/features/common/format.dart';
import 'package:helix_admin/src/features/dashboard/server_controller.dart';
import 'package:helix_admin/src/widgets/console_kit.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// What the operator sees first: whether the server is up, six live numbers
/// and the health of what the server depends on. Every number is the
/// server's own answer; one it did not give is a dash, never a made-up zero.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.server});

  final ServerController server;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: server,
      builder: (context, _) {
        final config = server.config;
        if (config == null) {
          if (server.loading || server.error == null) {
            return const ConsoleLoading(label: 'Loading the server');
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ConsoleBanner(
                title: 'Something went wrong',
                message: server.error!,
                onRetry: server.refresh,
              ),
            ],
          );
        }
        return RefreshIndicator(
          onRefresh: server.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _Header(server: server),
              const SizedBox(height: 16),
              if (server.healthNote != null) ...[
                ConsoleBanner(
                  tone: ConsoleTone.warn,
                  title: 'The server could not be checked',
                  message: server.healthNote!,
                ),
                const SizedBox(height: 12),
              ],
              if (server.metricsNote != null) ...[
                ConsoleBanner(
                  tone: ConsoleTone.warn,
                  title: 'Metrics are not available',
                  message: server.metricsNote!,
                ),
                const SizedBox(height: 12),
              ],
              _Tiles(server: server),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Connection, request and crash counts are for the node this '
                  'console reached and start again from zero when it '
                  'restarts. Undelivered messages and failed jobs cover the '
                  'whole server.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: HelixConsoleColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const ConsoleHeading('Service health'),
              const SizedBox(height: 12),
              _Health(server: server, config: config),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.server});

  final ServerController server;

  @override
  Widget build(BuildContext context) {
    final ready = server.ready;
    final latency = server.latencyMs;
    final ConsolePill pill;
    if (server.offline) {
      pill = const ConsolePill(
        label: 'Offline',
        tone: ConsoleTone.danger,
        dot: true,
      );
    } else if (ready == null) {
      pill = const ConsolePill(
        label: 'Not checked',
        tone: ConsoleTone.warn,
        dot: true,
      );
    } else if (!ready.ready) {
      pill = const ConsolePill(
        label: 'Not ready',
        tone: ConsoleTone.warn,
        dot: true,
      );
    } else {
      pill = ConsolePill(
        label: latency == null ? 'Online' : 'Online · $latency ms',
        tone: ConsoleTone.ok,
        dot: true,
      );
    }
    return Row(
      children: [
        const Flexible(child: ConsoleTitle('Dashboard')),
        const SizedBox(width: 12),
        pill,
        IconButton(
          tooltip: 'Reload server status',
          icon: const Icon(Icons.refresh, color: HelixConsoleColors.textMuted),
          onPressed: server.loading ? null : server.refresh,
        ),
      ],
    );
  }
}

class _Tiles extends StatelessWidget {
  const _Tiles({required this.server});

  final ServerController server;

  static String _count(int? v) => v == null ? '—' : formatCount(v);

  @override
  Widget build(BuildContext context) {
    final m = server.metrics;
    final database = server.ready?.checks['database'];
    final dead = m?.deadJobs;
    final share = m?.serverErrorShare;
    final tiles = <Widget>[
      ConsoleMetricTile(
        title: 'Active device connections',
        value: _count(m?.websocketsOpen),
        subtitle: 'Open sockets on this node',
        icon: Icons.phone_android_outlined,
        accent: HelixConsoleColors.ok,
      ),
      ConsoleMetricTile(
        title: 'Requests served',
        value: _count(m?.requests),
        subtitle: share == null
            ? 'Since this node started'
            : '${(share * 100).toStringAsFixed(share < 0.1 ? 1 : 0)}% server errors',
        subtitleColor: (share ?? 0) > 0.05
            ? HelixConsoleColors.onWarn
            : HelixConsoleColors.onOk,
        icon: Icons.swap_vert,
        accent: HelixConsoleColors.accent,
      ),
      ConsoleMetricTile(
        title: 'Undelivered messages',
        value: _count(m?.mailboxBacklog),
        subtitle: 'Waiting in mailboxes',
        icon: Icons.mail_outline,
        accent: HelixConsoleColors.violet,
      ),
      ConsoleMetricTile(
        title: 'Failed background jobs',
        value: _count(dead),
        subtitle: 'Ran out of retries',
        subtitleColor: (dead ?? 0) > 0
            ? HelixConsoleColors.onWarn
            : HelixConsoleColors.onOk,
        valueColor: (dead ?? 0) > 0
            ? HelixConsoleColors.danger
            : HelixConsoleColors.text,
        icon: Icons.send_outlined,
        accent: HelixConsoleColors.warn,
      ),
      ConsoleMetricTile(
        title: 'Crash reports',
        value: _count(m?.crashReports),
        subtitle: 'Accepted from apps',
        icon: Icons.shield_outlined,
        accent: HelixConsoleColors.danger,
      ),
      ConsoleMetricTile(
        title: 'Database status',
        value: database == null ? '—' : (database ? 'HEALTHY' : 'UNHEALTHY'),
        subtitle: database == null ? 'Not checked' : 'Readiness check',
        subtitleColor: database == false
            ? HelixConsoleColors.danger
            : HelixConsoleColors.onOk,
        valueColor: database == null
            ? HelixConsoleColors.text
            : (database ? HelixConsoleColors.onOk : HelixConsoleColors.danger),
        icon: Icons.dns_outlined,
        accent: database == false
            ? HelixConsoleColors.danger
            : HelixConsoleColors.ok,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width > 800 ? 3 : 2;
        // Rows sized by their tallest tile, so a bigger system font or a
        // longer title never overflows a fixed-ratio cell.
        return Column(
          children: [
            for (var i = 0; i < tiles.length; i += columns) ...[
              if (i > 0) const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < columns; j++) ...[
                      if (j > 0) const SizedBox(width: 12),
                      Expanded(
                        child: i + j < tiles.length
                            ? tiles[i + j]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Health extends StatelessWidget {
  const _Health({required this.server, required this.config});

  final ServerController server;
  final AdminConfig config;

  /// What each readiness check the server runs means in plain words.
  static const _names = {
    'database': ('Database', 'PostgreSQL'),
    'storage': ('Object storage', 'Attachments and backups'),
  };

  @override
  Widget build(BuildContext context) {
    final ready = server.ready;
    final rows = <Widget>[];
    if (ready == null) {
      rows.add(
        const ConsoleHealthRow(
          title: 'Readiness',
          subtitle: 'Not checked',
          note: 'The server has not answered its readiness check yet.',
          dot: HelixConsoleColors.warn,
        ),
      );
    } else {
      for (final entry in ready.checks.entries) {
        final (name, what) =
            _names[entry.key] ?? (_title(entry.key), 'Server check');
        rows.add(
          ConsoleHealthRow(
            title: name,
            subtitle: '$what • ${entry.value ? 'Working' : 'Not working'}',
            note: entry.value
                ? 'The server checked this a moment ago and it answered.'
                : 'The server could not use this. Check its log.',
            dot: entry.value
                ? HelixConsoleColors.ok
                : HelixConsoleColors.danger,
          ),
        );
      }
    }
    final services = config.integrations;
    if (services != null) {
      rows
        ..add(_push(services.push))
        ..add(_sms(services.sms))
        ..add(_turn(services.turn));
    }
    rows
      ..add(
        ConsoleHealthRow(
          title: 'Sign-up',
          subtitle: switch (config.registration) {
            RegistrationMode.phone => 'Phone number (Helix Global)',
            RegistrationMode.invite => 'Invite code',
            RegistrationMode.closed => 'Closed',
            RegistrationMode.unknown => 'Unknown',
          },
          note: config.registration == RegistrationMode.closed
              ? 'Nobody new can create an account on this server.'
              : 'How a new person creates an account here.',
          dot: config.registration == RegistrationMode.closed
              ? HelixConsoleColors.warn
              : HelixConsoleColors.ok,
        ),
      )
      ..add(
        ConsoleHealthRow(
          title: 'Federation',
          subtitle: config.federationEnabled
              ? 'On${config.federationDomain == null ? '' : ' • ${config.federationDomain}'}'
              : 'Off',
          note: config.federationEnabled
              ? 'This server talks to other Helix servers.'
              : 'This server only serves its own accounts.',
          dot: config.federationEnabled
              ? HelixConsoleColors.ok
              : HelixConsoleColors.off,
        ),
      );
    if (config.maintenance) {
      rows.add(
        const ConsoleHealthRow(
          title: 'Maintenance mode',
          subtitle: 'On',
          note:
              'Apps get 503 until it is turned off in Ops & Logs > Config. '
              'This console keeps working.',
          dot: HelixConsoleColors.warn,
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          rows[i],
        ],
      ],
    );
  }

  /// Push: set up or not. The server cannot know whether Google accepts the
  /// key until a wake-up is sent, so the words say "set up", never "working".
  static Widget _push(AdminIntegrationStatus push) => push.configured
      ? const ConsoleHealthRow(
          title: 'FCM push notification service',
          subtitle: 'Firebase Cloud Messaging • Set up',
          note:
              'Phones whose app is closed are woken for new messages and '
              'calls. The server only learns whether Google accepts the key '
              'when it sends one.',
          dot: HelixConsoleColors.ok,
        )
      : const ConsoleHealthRow(
          title: 'FCM push notification service',
          subtitle: 'Firebase Cloud Messaging • Not set up',
          note:
              'A phone whose app is closed or asleep is not told about new '
              'messages or calls. An app still running in the background '
              'gets them while it stays connected. To turn push on, set '
              'HELIX_PUSH_PROVIDER=fcm, HELIX_FCM_PROJECT_ID and '
              'HELIX_FCM_SERVICE_ACCOUNT in server/.env and restart.',
          dot: HelixConsoleColors.off,
        );

  /// SMS: a gateway is wired up or not. A gateway can answer "sent" for a
  /// key it will not honour, so the first real signal is a failed sign-up.
  static Widget _sms(AdminIntegrationStatus sms) => sms.configured
      ? ConsoleHealthRow(
          title: 'SMS gateway',
          subtitle: '${_smsName(sms.provider)} • Set up',
          note:
              'Sign-in codes are sent through it. The server cannot tell '
              'whether the gateway accepts the key until a code is sent, so '
              'a failed sign-up is the first real signal.',
          dot: HelixConsoleColors.ok,
        )
      : const ConsoleHealthRow(
          title: 'SMS gateway',
          subtitle: 'Not set up',
          note:
              'Nobody can receive a sign-in code on this server. Set '
              'HELIX_SMS_PROVIDER, HELIX_SMS_API_KEY and HELIX_SMS_SENDER_ID '
              'in server/.env and restart.',
          dot: HelixConsoleColors.off,
        );

  static String _smsName(String? provider) => switch (provider) {
    'bulksmsbd' => 'BulkSMSBD',
    final other? when other.isNotEmpty => other,
    _ => 'Gateway',
  };

  /// TURN: set up or not. The relay itself is not probed from here, and
  /// router port forwarding for outside devices is not checked.
  static Widget _turn(AdminIntegrationStatus turn) {
    if (!turn.configured) {
      return const ConsoleHealthRow(
        title: 'TURN relay server',
        subtitle: 'STUN/TURN peer connection • Not set up',
        note:
            'Calls can start, but devices behind strict routers or on mobile '
            'data cannot pass media to each other. Set HELIX_TURN_URLS and '
            'HELIX_TURN_SECRET in server/.env and restart.',
        dot: HelixConsoleColors.off,
      );
    }
    final count = turn.count;
    final addresses = count == null
        ? ''
        : ' • $count address${count == 1 ? '' : 'es'}';
    return ConsoleHealthRow(
      title: 'TURN relay server',
      subtitle: 'STUN/TURN peer connection • Set up$addresses',
      note:
          'Calls can relay media through it. The server does not test the '
          'relay, and router port forwarding for outside devices is not '
          'checked.',
      dot: HelixConsoleColors.ok,
    );
  }

  static String _title(String key) {
    final words = key.replaceAll('_', ' ');
    return words.isEmpty ? key : words[0].toUpperCase() + words.substring(1);
  }
}
