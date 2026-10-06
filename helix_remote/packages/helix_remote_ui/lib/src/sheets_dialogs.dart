part of '../helix_remote_ui.dart';

/// Shows a modal bottom sheet with Helix's drag handle, safe-area padding and
/// scroll-when-tall behaviour. Returns what the sheet pops with.
Future<T?> showHelixBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  bool isDismissible = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  isDismissible: isDismissible,
  showDragHandle: false,
  useSafeArea: true,
  builder: (sheetContext) => HelixBottomSheetScaffold(
    title: title,
    child: Builder(builder: builder),
  ),
);

/// The chrome of a bottom sheet: handle, optional title, scrollable body.
class HelixBottomSheetScaffold extends StatelessWidget {
  const HelixBottomSheetScaffold({super.key, required this.child, this.title});

  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: HelixSpace.xs),
              child: Container(
                width: 36,
                height: 4,
                decoration: const BoxDecoration(
                  color: HelixNeutralColors.divider,
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                ),
              ),
            ),
          ),
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                HelixSpace.md,
                HelixSpace.xs,
                HelixSpace.md,
                HelixSpace.sm,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  title!,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: HelixSpace.sm),
            child: child,
          ),
        ],
      ),
    ),
  );
}

/// A confirm / cancel dialog for actions that are not destructive. For
/// destructive ones use [showHelixDestructiveDialog].
Future<bool> showHelixConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'OK',
  String cancelLabel = 'Cancel',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ) ??
    false;

/// A single-line text prompt (rename, nickname). Returns the trimmed text, or
/// null when cancelled. The dialog owns and disposes its controller.
Future<String?> showHelixTextInputDialog(
  BuildContext context, {
  required String title,
  String? label,
  String initialValue = '',
  String confirmLabel = 'Save',
  int? maxLength,
}) => showDialog<String>(
  context: context,
  builder: (context) => _TextInputDialog(
    title: title,
    label: label,
    initialValue: initialValue,
    confirmLabel: confirmLabel,
    maxLength: maxLength,
  ),
);

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    required this.confirmLabel,
    required this.maxLength,
  });
  final String title;
  final String? label;
  final String initialValue;
  final String confirmLabel;
  final int? maxLength;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: widget.maxLength,
      decoration: InputDecoration(labelText: widget.label),
      onSubmitted: (value) => Navigator.pop(context, value.trim()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}

/// Shows a floating snackbar, replacing any that is showing. Never put
/// message content or phone numbers in [message]: snackbars are announced and
/// can linger on screenshots.
void showHelixSnackBar(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        behavior: SnackBarBehavior.floating,
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction),
      ),
    );
}
