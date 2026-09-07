import 'package:flutter/material.dart';
import '../theme/nivasa_colors.dart';
import '../theme/nivasa_motion.dart';
import '../theme/nivasa_spacing.dart';

/// Shimmering placeholder "bone" for loading states (doc option "1l", finding ST-1:
/// "twelve screens, one full-screen spinner" — every screen loaded as
/// `Center(child: CircularProgressIndicator())`, with no layout reservation and a hard
/// jump when data landed). A screen's loading state composes these into the same shape
/// its real content will take, so nothing jumps into place once the fetch resolves.
///
/// The gradient's two hex values are lifted directly from the mock's `.skel` CSS class —
/// tokens.css defines `--motion-shimmer`'s duration (see [NivasaMotion.shimmer]) but no
/// dedicated skeleton color pair, so they live here rather than on `NivasaColors`. The
/// sweep freezes on a static mid-tone instead of looping when
/// [NivasaMotion.reduceMotion] is set, mirroring the mock's own
/// `prefers-reduced-motion` override.
class NivasaSkeleton extends StatefulWidget {
  const NivasaSkeleton({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 6,
    this.shape = BoxShape.rectangle,
  });

  /// Convenience for a circular bone (avatars, icon circles) — same shimmer, no corner
  /// radius to reason about.
  const NivasaSkeleton.circle({super.key, required double size})
    : width = size,
      height = size,
      borderRadius = 0,
      shape = BoxShape.circle;

  final double width;
  final double height;
  final double borderRadius;
  final BoxShape shape;

  @override
  State<NivasaSkeleton> createState() => _NivasaSkeletonState();
}

class _NivasaSkeletonState extends State<NivasaSkeleton>
    with SingleTickerProviderStateMixin {
  static const _base = Color(0xFFE4E2DC);
  static const _highlight = Color(0xFFF1EFEA);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: NivasaMotion.shimmer,
  );
  bool? _reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = NivasaMotion.reduceMotion(context);
    if (reduce != _reduceMotion) {
      _reduceMotion = reduce;
      if (reduce) {
        _controller.stop();
      } else {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _reduceMotion == true ? 0.5 : _controller.value;
        final dx = t * 2 - 1;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            shape: widget.shape,
            borderRadius: widget.shape == BoxShape.rectangle
                ? BorderRadius.circular(widget.borderRadius)
                : null,
            gradient: LinearGradient(
              begin: Alignment(-1 + dx, 0),
              end: Alignment(dx, 0),
              colors: const [_base, _highlight, _base],
            ),
          ),
        );
      },
    );
  }
}

/// The "list row" shimmer shape — an icon-sized circle plus two lines — shared across
/// every list screen (Documents, Vehicles, Contacts, Guests, Maintenance, Payments)
/// instead of re-deriving the same three bones on each one.
class NivasaSkeletonListTile extends StatelessWidget {
  const NivasaSkeletonListTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(NivasaSpacing.s16),
      decoration: BoxDecoration(
        color: NivasaColors.white,
        border: Border.all(color: NivasaColors.line),
        borderRadius: BorderRadius.circular(NivasaRadius.card),
      ),
      child: const Row(
        children: [
          NivasaSkeleton.circle(size: 44),
          SizedBox(width: NivasaSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NivasaSkeleton(width: 160, height: 15),
                SizedBox(height: NivasaSpacing.s8),
                NivasaSkeleton(width: 100, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A vertical stack of [count] [NivasaSkeletonListTile]s, padded like the real list body
/// it stands in for.
class NivasaSkeletonList extends StatelessWidget {
  const NivasaSkeletonList({super.key, this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(NivasaSpacing.s24),
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(height: NivasaSpacing.s12),
          const NivasaSkeletonListTile(),
        ],
      ],
    );
  }
}
