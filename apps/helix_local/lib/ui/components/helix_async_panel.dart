import 'package:flutter/material.dart';
import 'package:helix/ui/app_theme.dart';

/// Standard async state enum used across both apps.
///
/// Use this instead of ad-hoc boolean flags when a screen or section
/// progresses through the loading lifecycle:
///
///   initial → loading → data | empty | error | offline
///                  ↑ refreshing (already has data but is re-fetching)
///               stale (data shown but known to be outdated)
enum HelixAsyncState {
  initial,
  loading,
  refreshing,
  data,
  empty,
  stale,
  error,
  offline,
}

/// A panel that renders the correct UI for the current [HelixAsyncState].
///
/// For [HelixAsyncState.data] the [child] is shown directly. All other states
/// produce a centred column with an icon, heading, optional body text, and an
/// optional [action] button.
class HelixAsyncPanel extends StatelessWidget {
  const HelixAsyncPanel({
    super.key,
    required this.state,
    this.child,
    this.errorMessage,
    this.onRetry,
    this.emptyIcon,
    this.emptyTitle,
    this.emptyBody,
    this.action,
  });

  final HelixAsyncState state;

  /// Shown when [state] is [HelixAsyncState.data] or [HelixAsyncState.refreshing].
  final Widget? child;

  /// Error detail text (shown when [state] is [HelixAsyncState.error]).
  final String? errorMessage;

  /// Called when the user taps the automatic Retry button on error/offline states.
  /// If null, no retry button is shown.
  final VoidCallback? onRetry;

  /// Override the icon for the empty state.
  final IconData? emptyIcon;

  /// Override the title for the empty state.
  final String? emptyTitle;

  /// Override the body text for the empty state.
  final String? emptyBody;

  /// Extra action widget shown below the state panel (e.g. a button).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case HelixAsyncState.initial:
      case HelixAsyncState.loading:
        return const Center(child: CircularProgressIndicator());

      case HelixAsyncState.data:
        return child ?? const SizedBox.shrink();

      case HelixAsyncState.refreshing:
        return Stack(
          children: [
            child ?? const SizedBox.expand(),
            const Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
          ],
        );

      case HelixAsyncState.empty:
        return _StatePanel(
          icon: emptyIcon ?? Icons.inbox_outlined,
          iconColor: HelixTokens.colorOffline,
          title: emptyTitle ?? 'Nothing here yet',
          body: emptyBody,
          action: action,
        );

      case HelixAsyncState.stale:
        return _StatePanel(
          icon: Icons.sync_problem_outlined,
          iconColor: HelixTokens.colorWarning,
          title: 'Content may be outdated',
          body: 'Pull to refresh or check your connection.',
          action: action,
        );

      case HelixAsyncState.error:
        return _StatePanel(
          icon: Icons.error_outline,
          iconColor: HelixTokens.colorError,
          title: 'Something went wrong',
          body: errorMessage,
          action: onRetry != null
              ? FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                )
              : action,
        );

      case HelixAsyncState.offline:
        return _StatePanel(
          icon: Icons.cloud_off_outlined,
          iconColor: HelixTokens.colorOffline,
          title: 'No connection',
          body: 'Check your network and try again.',
          action: onRetry != null
              ? FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                )
              : action,
        );
    }
  }
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.body,
    this.action,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(HelixTokens.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: iconColor),
            const SizedBox(height: HelixTokens.space16),
            Text(
              title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            if (body != null) ...[
              const SizedBox(height: HelixTokens.space8),
              Text(
                body!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(160),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: HelixTokens.space24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
