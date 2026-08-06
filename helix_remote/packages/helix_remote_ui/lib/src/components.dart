part of '../helix_remote_ui.dart';

class HelixEmptyState extends StatelessWidget {
  const HelixEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(HelixSpace.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: HelixSpace.md),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (message != null) ...[
            const SizedBox(height: HelixSpace.xs),
            Text(message!, textAlign: TextAlign.center),
          ],
          if (action != null) ...[
            const SizedBox(height: HelixSpace.md),
            action!,
          ],
        ],
      ),
    ),
  );
}

class HelixErrorState extends StatelessWidget {
  const HelixErrorState({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => HelixEmptyState(
    icon: Icons.error_outline,
    title: 'Something went wrong',
    message: message,
    action: onRetry == null
        ? null
        : FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
  );
}

class HelixSkeleton extends StatelessWidget {
  const HelixSkeleton({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.radius = HelixRadius.small,
  });
  final double width;
  final double height;
  final Radius radius;
  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.all(radius),
    ),
  );
}

class HelixAsyncPanel extends StatelessWidget {
  const HelixAsyncPanel({
    super.key,
    required this.loading,
    required this.child,
    this.error,
    this.onRetry,
    this.skeleton,
  });
  final bool loading;
  final Widget child;
  final String? error;
  final VoidCallback? onRetry;
  final Widget? skeleton;
  @override
  Widget build(BuildContext context) => loading
      ? (skeleton ?? const Center(child: HelixSkeleton(width: 180, height: 24)))
      : error != null
      ? HelixErrorState(message: error!, onRetry: onRetry)
      : child;
}

class HelixStatusBadge extends StatelessWidget {
  const HelixStatusBadge({super.key, required this.label, this.color});
  final String label;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final value = color ?? Theme.of(context).colorScheme.primary;
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: HelixSpace.xs,
          vertical: HelixSpace.xxs,
        ),
        decoration: BoxDecoration(
          color: value.withValues(alpha: .12),
          borderRadius: const BorderRadius.all(HelixRadius.small),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: value,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

Future<bool> showHelixDestructiveDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
