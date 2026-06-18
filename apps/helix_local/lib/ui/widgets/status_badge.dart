import 'package:flutter/material.dart';
import 'package:helix_domain/domain/models.dart';
import 'package:helix/ui/app_theme.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final ThreadStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (status) {
      ThreadStatus.active => (
        'Active',
        Icons.check_circle_outline,
        HelixTheme.connectedColor,
      ),
      ThreadStatus.connecting => (
        'Connecting',
        Icons.sync,
        HelixTheme.pendingColor,
      ),
      ThreadStatus.disconnected => (
        'Offline',
        Icons.radio_button_unchecked,
        HelixTheme.disconnectedColor,
      ),
    };

    if (status == ThreadStatus.connecting) {
      return _PulsingStatePill(label: label, icon: icon, color: color);
    }
    return _StatePill(label: label, icon: icon, color: color);
  }
}

class _PulsingStatePill extends StatefulWidget {
  const _PulsingStatePill({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  State<_PulsingStatePill> createState() => _PulsingStatePillState();
}

class _PulsingStatePillState extends State<_PulsingStatePill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
    _opacity = Tween<double>(
      begin: 0.62,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return _StatePill(
        label: widget.label,
        icon: widget.icon,
        color: widget.color,
      );
    }
    return FadeTransition(
      opacity: _opacity,
      child: _StatePill(
        label: widget.label,
        icon: widget.icon,
        color: widget.color,
      ),
    );
  }
}

class DiscoverabilityBadge extends StatelessWidget {
  const DiscoverabilityBadge({super.key, required this.state});

  final DiscoverabilityState state;

  @override
  Widget build(BuildContext context) {
    final isDiscoverable = state == DiscoverabilityState.discoverable;
    final color = isDiscoverable
        ? HelixTheme.accentColor
        : HelixTheme.disconnectedColor;
    final label = isDiscoverable ? 'Discoverable' : 'Hidden';
    final icon = isDiscoverable
        ? Icons.wifi_tethering
        : Icons.wifi_tethering_off;

    return _StatePill(label: label, icon: icon, color: color);
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(72)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class DeliveryIcon extends StatelessWidget {
  const DeliveryIcon({super.key, required this.status, this.size = 14});

  final MessageDeliveryStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = HelixTheme.deliveryColor(context, status);
    final (icon, tooltip) = switch (status) {
      MessageDeliveryStatus.sending => (Icons.hourglass_empty, 'Sending'),
      MessageDeliveryStatus.delivered => (Icons.check, 'Delivered'),
      MessageDeliveryStatus.read => (Icons.done_all, 'Read'),
      MessageDeliveryStatus.failed => (Icons.error_outline, 'Failed to send'),
      MessageDeliveryStatus.disconnected => (
        Icons.do_not_disturb_on_outlined,
        'Disconnected',
      ),
    };

    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: tooltip,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, animation) {
            return ScaleTransition(scale: animation, child: child);
          },
          child: Icon(icon, key: ValueKey(status), size: size, color: color),
        ),
      ),
    );
  }
}

class SessionSeparatorChip extends StatelessWidget {
  const SessionSeparatorChip({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.primary.withAlpha(60),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_reset,
                  size: 13,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 5),
                Text(
                  'New secure session',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}
