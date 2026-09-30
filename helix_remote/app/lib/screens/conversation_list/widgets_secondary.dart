part of '../conversation_list_screen.dart';

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.size = 48, this.heroTag});

  final String name;
  final double size;
  final Object? heroTag;

  Color _color() =>
      HelixColorTokens.avatarPalette[name.hashCode.abs() %
          HelixColorTokens.avatarPalette.length];

  String _initials() {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return trimmed.substring(0, trimmed.length.clamp(1, 2)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: size / 2,
      backgroundColor: _color(),
      child: Text(
        _initials(),
        style: TextStyle(
          color: HelixScrimColors.onBackdrop,
          fontSize: size * 0.35,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    return heroTag == null ? avatar : Hero(tag: heroTag!, child: avatar);
  }
}
