import 'package:flutter/widgets.dart';

import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/theme/motion.dart';

/// `<i class="ph ph-spinner-gap spin">`: the regular-weight spinner icon,
/// turning once every 0.9s (`css/pages.css`, `.spin`). With reduce motion it
/// stands still, as the prototype's `animation: none` leaves it.
class OrbitSpinner extends StatefulWidget {
  const OrbitSpinner({super.key, required this.size, this.color});

  final double size;
  final Color? color;

  @override
  State<OrbitSpinner> createState() => _OrbitSpinnerState();
}

class _OrbitSpinnerState extends State<OrbitSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (OrbitMotion.allowed(context)) {
      if (!_turn.isAnimating) _turn.repeat();
    } else {
      _turn
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _turn,
    child: OrbitIcon(
      OrbitIcons.spinnerGap,
      weight: OrbitIconWeight.regular,
      size: widget.size,
      color: widget.color,
    ),
  );
}
