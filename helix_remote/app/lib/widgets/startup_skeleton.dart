import 'dart:async';

import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// What the app shows while it opens: the shape of the chats page, so the
/// real one simply fills in.
///
/// Nothing at all for the first [delay] - a start that finishes by then
/// should not flash a placeholder - then the skeleton, with a line saying
/// what is actually being done when [status] is given.
class StartupSkeleton extends StatefulWidget {
  const StartupSkeleton({super.key, this.status});

  final String? status;

  static const delay = Duration(milliseconds: 700);

  @override
  State<StartupSkeleton> createState() => _StartupSkeletonState();
}

class _StartupSkeletonState extends State<StartupSkeleton> {
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(StartupSkeleton.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          child: Semantics(
            label: widget.status ?? 'Opening Helix',
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 18, 16, 12),
                  child: Row(
                    children: [
                      HelixSkeleton(width: 96, height: 22),
                      Spacer(),
                      HelixSkeleton(
                        width: 28,
                        height: 28,
                        radius: Radius.circular(14),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: HelixSkeleton(height: 40, radius: Radius.circular(20)),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 9,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          const HelixSkeleton(
                            width: 48,
                            height: 48,
                            radius: Radius.circular(24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                HelixSkeleton(
                                  width: 120.0 + (index % 3) * 30,
                                  height: 14,
                                ),
                                const SizedBox(height: 8),
                                HelixSkeleton(
                                  width: 180.0 + (index % 2) * 40,
                                  height: 12,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.status != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      widget.status!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
