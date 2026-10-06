part of '../helix_remote_ui.dart';

/// Sweeps a soft highlight across [child] (skeleton shapes) while loading.
///
/// One controller per shimmer, not per placeholder: wrap a whole skeleton
/// list in a single [HelixShimmer]. The sweep stops when the platform asks for
/// reduced motion or [animate] is false, leaving the static skeleton.
class HelixShimmer extends StatefulWidget {
  const HelixShimmer({super.key, required this.child, this.animate = true});

  final Widget child;
  final bool animate;

  @override
  State<HelixShimmer> createState() => _HelixShimmerState();
}

class _HelixShimmerState extends State<HelixShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(HelixShimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final run = widget.animate && !MediaQuery.disableAnimationsOf(context);
    if (run && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!run && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    final band = scheme.surfaceContainerLowest;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          colors: [base, band, base],
          stops: const [0.3, 0.5, 0.7],
          transform: _SlideGradient(_controller.value),
        ).createShader(bounds),
        child: child,
      ),
    );
  }
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.t);
  final double t;
  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final sign = textDirection == TextDirection.rtl ? -1 : 1;
    return Matrix4.translationValues(sign * bounds.width * (t * 2 - 1), 0, 0);
  }
}
