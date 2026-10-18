import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import 'common.dart';

/// One "place line" row: the ordinal, "of N", a crowd of runners along a
/// track with this runner sliding into position (left = back of the field,
/// right = the winner), and "11,492 finishers behind · Top 1.5%".
class PlaceLine extends StatelessWidget {
  const PlaceLine({super.key, required this.label, required this.info, this.trailing, this.accent = RL.amber, this.seed = 1});
  final String label;
  final PlaceInfo info;
  final Widget? trailing;
  final Color accent;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final frac = info.of <= 1 ? 1.0 : (info.of - info.place) / (info.of - 1);
    final top = info.place == 1 ? tr('Winner') : tr('Top {pct}', {'pct': fmtPct(info.topPct)});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, letterSpacing: 1.1, fontWeight: FontWeight.w800, color: muted(context)),
              ),
            ),
            if (trailing != null) Flexible(child: Align(alignment: Alignment.centerRight, child: trailing)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    CountUp(
                      value: info.place.toDouble(),
                      from: info.of.toDouble(),
                      duration: const Duration(milliseconds: 1500),
                      format: (v) => ordinal(v.round()),
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: ink(context), height: 1.05, fontFeatures: tabular),
                    ),
                    const SizedBox(width: 6),
                    Text(tr('of {n}', {'n': fmtInt(info.of)}), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: muted(context))),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
              child: Text(top, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: accent, fontFeatures: tabular)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        CrowdTrack(fraction: frac, accent: accent, seed: seed),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                tr('{n} finishers behind', {'n': fmtInt(info.behind)}),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ink(context)),
              ),
            ),
            Icon(Icons.emoji_events_rounded, size: 13, color: muted(context)),
            const SizedBox(width: 3),
            Text(tr('Winner'), style: TextStyle(fontSize: 11, color: muted(context))),
          ],
        ),
      ],
    );
  }
}

/// Animated crowd of runner silhouettes on a track; the highlighted runner
/// slides in from the back of the field to [fraction] (1 = winner).
class CrowdTrack extends StatelessWidget {
  const CrowdTrack({super.key, required this.fraction, this.accent = RL.amber, this.height = 50, this.seed = 1});
  final double fraction;
  final Color accent;
  final double height;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 1700),
      curve: Curves.easeOutQuart,
      builder: (_, v, _) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: CrowdPainter(t: v, dark: dark, accent: accent, seed: seed)),
      ),
    );
  }
}

class CrowdPainter extends CustomPainter {
  CrowdPainter({required this.t, required this.dark, required this.accent, this.seed = 1, this.crowdColor});
  final double t;
  final bool dark;
  final Color accent;
  final int seed;

  /// Override for the faded crowd (share card styles).
  final Color? crowdColor;

  double _rnd(int i) {
    final v = math.sin(i * 12.9898 + seed * 78.233) * 43758.5453;
    return v - v.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final trackY = h - 4;
    const left = 8.0;
    final right = w - 8;
    final x = left + (right - left) * t;

    // Track.
    final track = Paint()
      ..color = crowdColor?.withValues(alpha: 0.18) ?? (dark ? Colors.white.withValues(alpha: 0.10) : RL.line)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(left, trackY), Offset(right, trackY), track);
    if (x > left + 1) {
      final done = Paint()
        ..shader = LinearGradient(colors: [accent.withValues(alpha: 0.05), accent.withValues(alpha: 0.75)]).createShader(Rect.fromLTRB(left, trackY - 3, x, trackY + 3))
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(left, trackY), Offset(x, trackY), done);
    }

    // Finish flag at the winner's end.
    final flag = Paint()..color = (crowdColor ?? (dark ? Colors.white : RL.navy)).withValues(alpha: 0.55);
    canvas.drawRect(Rect.fromLTWH(right - 1, trackY - 22, 1.6, 20), flag);
    canvas.drawPath(
      Path()
        ..moveTo(right + 0.6, trackY - 22)
        ..lineTo(right + 8, trackY - 18.5)
        ..lineTo(right + 0.6, trackY - 15)
        ..close(),
      flag,
    );

    // Crowd.
    final n = math.max(12, (w / 11.5).floor());
    final base = crowdColor ?? (dark ? Colors.white : RL.navy);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final head = Paint();
    for (var i = 0; i < n; i++) {
      final fx = (i + 0.5 + (_rnd(i) - 0.5) * 0.8) / n;
      final cx = left + 6 + (right - left - 18) * fx;
      if ((cx - x).abs() < 11) continue;
      final hh = h * (0.42 + _rnd(i + 99) * 0.16);
      final passed = cx < x;
      final c = passed ? accent.withValues(alpha: dark ? 0.5 : 0.32) : base.withValues(alpha: dark ? 0.16 : 0.12);
      p
        ..color = c
        ..strokeWidth = hh * 0.11;
      head.color = c;
      drawRunner(canvas, Offset(cx, trackY - 3 - _rnd(i + 7) * 3), hh, p, head, phase: i.isEven);
    }

    // You.
    final youH = h * 0.86;
    final glow = Paint()
      ..color = accent.withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawCircle(Offset(x, trackY - youH * 0.5), youH * 0.42, glow);
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = youH * 0.11 + 3
      ..color = dark ? const Color(0xFF0B1220) : Colors.white;
    final outlineHead = Paint()..color = outline.color;
    drawRunner(canvas, Offset(x, trackY - 2), youH, outline, outlineHead, phase: true, headGrow: 1.5);
    final you = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = youH * 0.11
      ..color = accent;
    drawRunner(canvas, Offset(x, trackY - 2), youH, you, Paint()..color = accent, phase: true);
  }

  /// Running figure facing right, feet at [foot], [h] tall.
  static void drawRunner(Canvas canvas, Offset foot, double h, Paint stroke, Paint headPaint, {bool phase = true, double headGrow = 0}) {
    Offset pt(double x, double y) => foot + Offset(x * h, y * h);
    final s = phase ? 1.0 : -1.0;
    final shoulder = pt(0.05, -0.72), hip = pt(-0.03, -0.42);
    final body = Path();
    void limb(Offset from, List<Offset> to) {
      body.moveTo(from.dx, from.dy);
      for (final o in to) {
        body.lineTo(o.dx, o.dy);
      }
    }

    limb(shoulder, [hip]);
    limb(shoulder, [pt(0.05 + 0.15 * s, -0.58), pt(0.05 + 0.24 * s, -0.70)]); // front arm
    limb(shoulder, [pt(0.05 - 0.15 * s, -0.56), pt(0.05 - 0.22 * s, -0.46)]); // back arm
    limb(hip, [pt(-0.03 + 0.19 * s, -0.24), pt(-0.03 + 0.13 * s, 0)]); // front leg
    limb(hip, [pt(-0.03 - 0.11 * s, -0.21), pt(-0.03 - 0.29 * s, -0.12)]); // back leg
    canvas.drawPath(body, stroke);
    canvas.drawCircle(pt(0.09, -0.87), h * 0.1 + headGrow, headPaint);
  }

  @override
  bool shouldRepaint(covariant CrowdPainter old) => old.t != t || old.dark != dark || old.accent != accent || old.crowdColor != crowdColor;
}
