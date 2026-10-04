import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The emojis offered by the picker, grouped the way people look for them.
/// A fixed list: it needs no data, no network and no plugin, and it is the
/// same on every device.
const emojiGroups = <(String, List<String>)>[
  (
    'Smileys',
    [
      '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '🙂', '😉', '😊', '😇', //
      '🥰', '😍', '🤩', '😘', '😋', '😛', '😜', '🤪', '🤔', '🤗', '🤭', '🤫',
      '😐', '😑', '😶', '😏', '😒', '🙄', '😬', '😌', '😔', '😪', '😴', '😷',
      '🤒', '🤕', '🤢', '🥵', '🥶', '🥴', '😵', '🤯', '🥳', '😎', '🤓', '😕',
      '😟', '🙁', '😮', '😯', '😲', '😳', '🥺', '😦', '😨', '😰', '😢', '😭',
      '😱', '😖', '😞', '😓', '😩', '😫', '😤', '😡', '😠', '🤬', '😈', '💀',
    ],
  ),
  (
    'Gestures',
    [
      '👍', '👎', '👌', '✌️', '🤞', '🤟', '🤘', '🤙', '👈', '👉', '👆', '👇', //
      '☝️', '✋', '🤚', '🖐️', '🖖', '👋', '🤝', '🙏', '👏', '🙌', '👐', '💪',
      '🤳', '✍️', '🙋', '🤷', '🤦', '🙇', '💁', '🙅', '🙆', '🤲',
    ],
  ),
  (
    'Hearts and symbols',
    [
      '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '💔', '💕', '💞', '💓', //
      '💗', '💖', '💘', '💝', '✨', '⭐', '🌟', '🔥', '💯', '✅', '❌', '❗',
      '❓', '⚡', '🎉', '🎊', '🎁', '🏆', '🔔', '📌',
    ],
  ),
  (
    'Things',
    [
      '☕', '🍕', '🍔', '🍟', '🍎', '🍌', '🍉', '🍰', '🍺', '🥂', '🎂', '🍿', //
      '⚽', '🏀', '🎮', '🎧', '🎵', '📷', '💻', '📱', '🚗', '✈️', '🏠', '🌍',
      '☀️', '🌙', '🌧️', '🌈', '🐶', '🐱', '🐻', '🦁', '🐼', '🐸', '🦄', '🌹',
    ],
  ),
];

/// A grid of emojis; [onPick] gets the one tapped. Used under the composer
/// and in the "more reactions" sheet.
class EmojiPanel extends StatefulWidget {
  const EmojiPanel({super.key, required this.onPick, this.height = 260});

  final ValueChanged<String> onPick;
  final double height;

  @override
  State<EmojiPanel> createState() => _EmojiPanelState();
}

class _EmojiPanelState extends State<EmojiPanel> {
  int _group = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final emojis = emojiGroups[_group].$2;
    return SizedBox(
      height: widget.height,
      child: Column(
        children: [
          SizedBox(
            height: HelixChatMetrics.minTarget,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < emojiGroups.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(emojiGroups[i].$1),
                      selected: i == _group,
                      onSelected: (_) => setState(() => _group = i),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(HelixSpace.xs),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: HelixChatMetrics.minTarget,
              ),
              itemCount: emojis.length,
              itemBuilder: (context, index) {
                final emoji = emojis[index];
                return Semantics(
                  button: true,
                  label: 'Emoji $emoji',
                  onTap: () => widget.onPick(emoji),
                  child: ExcludeSemantics(
                    child: InkResponse(
                      onTap: () => widget.onPick(emoji),
                      radius: 24,
                      child: Center(
                        child: Text(
                          emoji,
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            fontSize: 26,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The "more reactions" sheet: pick one emoji, get it back.
Future<String?> showEmojiSheet(BuildContext context) =>
    showHelixBottomSheet<String>(
      context,
      title: 'React',
      builder: (sheetContext) => EmojiPanel(
        height: 320,
        onPick: (emoji) => Navigator.pop(sheetContext, emoji),
      ),
    );
