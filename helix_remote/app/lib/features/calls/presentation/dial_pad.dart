import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The keypad sheet: type a number, press the green button. Returns what was
/// typed (digits, `+`, `*`, `#`), or null when the sheet is dismissed.
///
/// The number is only text here. The Calls tab hands it to the people search,
/// which checks that it is on Helix (and sends only a scrambled version of it)
/// before anything is called.
Future<String?> showDialPad(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _DialPad(),
    );

class _DialPad extends StatefulWidget {
  const _DialPad();

  @override
  State<_DialPad> createState() => _DialPadState();
}

class _DialPadState extends State<_DialPad> {
  /// A number needs at least this many digits before it can be searched.
  static const _minDigits = 6;

  static const _keys = [
    ('1', ''),
    ('2', 'ABC'),
    ('3', 'DEF'),
    ('4', 'GHI'),
    ('5', 'JKL'),
    ('6', 'MNO'),
    ('7', 'PQRS'),
    ('8', 'TUV'),
    ('9', 'WXYZ'),
    ('*', ''),
    ('0', '+'),
    ('#', ''),
  ];

  String _number = '';

  void _press(String digit) {
    HapticFeedback.selectionClick();
    setState(() => _number += digit);
  }

  void _backspace() {
    if (_number.isEmpty) return;
    setState(() => _number = _number.substring(0, _number.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ready = _number.replaceAll(RegExp(r'[^\d]'), '').length >= _minDigits;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  const SizedBox(width: 48),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _number.isEmpty ? 'Enter a number' : _number,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: _number.isEmpty
                                ? scheme.onSurfaceVariant
                                : scheme.onSurface,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: _number.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Delete digit',
                            icon: const Icon(Icons.backspace_outlined),
                            onPressed: _backspace,
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: HelixSpace.sm),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              childAspectRatio: 1.6,
              children: [
                for (final (digit, letters) in _keys)
                  Semantics(
                    button: true,
                    label: digit == '0' ? '0, hold for plus' : digit,
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(40),
                      onTap: () => _press(digit),
                      onLongPress: digit == '0' ? () => _press('+') : null,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(digit, style: theme.textTheme.headlineSmall),
                          if (letters.isNotEmpty)
                            Text(
                              letters,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: HelixSpace.sm),
            SizedBox.square(
              dimension: 64,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  backgroundColor: HelixCallColors.answerCall,
                  padding: EdgeInsets.zero,
                ),
                onPressed: ready
                    ? () => Navigator.of(context).pop(_number)
                    : null,
                child: const Icon(
                  Icons.call,
                  size: 28,
                  semanticLabel: 'Find on Helix',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
