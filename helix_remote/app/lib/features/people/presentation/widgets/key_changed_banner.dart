import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The warning shown when a person's safety number changed: their identity key
/// is not the one this device pinned.
///
/// It is a warning, never a block. The chat keeps working (a new phone or a
/// reinstall changes the key all the time), but the person is told, in plain
/// words, and given the one thing that settles it: comparing safety numbers.
class KeyChangedBanner extends StatelessWidget {
  const KeyChangedBanner({super.key, required this.name, this.onReview});

  final String name;

  /// Opens the safety number; omit on the safety number screen itself.
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label:
          'Warning. Your safety number with $name changed. Compare safety '
          'numbers to be sure it is still them.',
      child: Padding(
        padding: const EdgeInsets.all(HelixSpace.md),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: HelixStatusColors.cautionContainer,
            borderRadius: HelixRadius.card,
          ),
          child: Padding(
            padding: const EdgeInsets.all(HelixSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: HelixStatusColors.onCautionContainer,
                      ),
                    ),
                    SizedBox(width: HelixSpace.xs),
                    Expanded(
                      child: Text(
                        'Safety number changed',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: HelixStatusColors.onCautionContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: HelixSpace.xxs),
                Text(
                  'Your safety number with $name changed. That usually means '
                  'they got a new phone or reinstalled Helix. It can also mean '
                  'someone is interfering. Compare safety numbers with them '
                  'to be sure.',
                  style: const TextStyle(
                    color: HelixStatusColors.onCautionContainer,
                  ),
                ),
                if (onReview != null)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      onPressed: onReview,
                      child: const Text('Review'),
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
