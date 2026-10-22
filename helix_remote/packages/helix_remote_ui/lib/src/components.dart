part of '../helix_remote_ui.dart';

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
  // Purely decorative. A skeleton stands in for content that is not there
  // yet, and a screen full of them would otherwise announce one meaningless
  // node per placeholder.
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.all(radius),
      ),
    ),
  );
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
