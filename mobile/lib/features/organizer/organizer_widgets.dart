import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../home/widgets/motion.dart';

/// Standard scroll body for an organizer tab (keeps the bottom clear).
class OrgTabList extends StatelessWidget {
  const OrgTabList({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (_, i) => FadeSlideIn(index: i, child: children[i]),
      );
}

/// A big animated count with a coloured caption.
class OrgCountTile extends StatelessWidget {
  const OrgCountTile({super.key, required this.value, required this.label, required this.color, required this.icon});
  final int value;
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color))),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: CountUpText(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: ink(context))),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bars with a soft area line on top: finishers per minute.
class SparkBars extends StatelessWidget {
  const SparkBars({super.key, required this.values, this.color = RL.green, this.height = 72});
  final List<int> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (_, k, _) => CustomPaint(painter: _SparkPainter(values, color, k, Theme.of(context).dividerColor)),
        ),
      );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color, this.k, this.grid);
  final List<int> values;
  final Color color;
  final double k;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), Paint()..color = grid);
    if (values.isEmpty) return;
    final maxV = math.max(1, values.reduce(math.max));
    final w = size.width / values.length;
    final bar = Paint()..color = color.withValues(alpha: 0.28);
    final line = Path();
    for (var i = 0; i < values.length; i++) {
      final h = (values[i] / maxV) * (size.height - 6) * k;
      final r = RRect.fromRectAndCorners(
        Rect.fromLTWH(i * w + w * 0.15, size.height - h, w * 0.7, h),
        topLeft: const Radius.circular(2),
        topRight: const Radius.circular(2),
      );
      canvas.drawRRect(r, bar);
      final p = Offset(i * w + w / 2, size.height - h);
      i == 0 ? line.moveTo(p.dx, p.dy) : line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round,
    );
    final lastH = (values.last / maxV) * (size.height - 6) * k;
    canvas.drawCircle(Offset(size.width - w / 2, size.height - lastH), 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values || old.k != k || old.color != color;
}

/// Ask before something big happens (gun, close race, publish).
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
  Color color = RL.amber,
  IconData icon = Icons.flag_rounded,
  Key? confirmKey,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(icon, color: color, size: 32),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(body, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
        FilledButton(
          key: confirmKey,
          style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Colour for a density ratio 0..1: green → amber → red.
Color densityColor(double v) {
  final x = v.clamp(0.0, 1.0);
  return x < 0.5 ? Color.lerp(RL.green, RL.amber, x * 2)! : Color.lerp(RL.amber, RL.red, (x - 0.5) * 2)!;
}

/// Monospace block for CSV previews.
class CsvBlock extends StatelessWidget {
  const CsvBlock(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: dark ? const Color(0xFF0B1220) : RL.bg, borderRadius: BorderRadius.circular(10)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(text, style: TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.45, color: ink(context))),
      ),
    );
  }
}
