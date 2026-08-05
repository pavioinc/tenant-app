import 'package:flutter/material.dart';
import '../theme/nivasa_colors.dart';

/// "NivasaOS mark is a rounded green square (#0F5C4A, radius 11) containing a gold
/// (#E8A33D) chevron/roof form rotated 45°." Same path (M4 20 12 4l8 16) as the web
/// dashboard's inline SVG mark, redrawn here since Flutter has no SVG-in-a-string story
/// as lightweight as JSX — see owner-dashboard/components/layout/Sidebar.tsx for the
/// original.
class NivasaLogoMark extends StatelessWidget {
  const NivasaLogoMark({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: NivasaColors.primary700, borderRadius: BorderRadius.circular(size * 0.25)),
      padding: EdgeInsets.all(size * 0.28),
      child: Transform.rotate(angle: 0.7854, child: CustomPaint(painter: _ChevronPainter())),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = NivasaColors.gold500
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.22
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width * 0.5, 0)
      ..lineTo(size.width, size.height);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
