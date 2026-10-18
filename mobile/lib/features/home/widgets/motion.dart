import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/format.dart';

/// Fades and slides its child in once, the first time it is built.
/// [index] staggers a list of these (60 ms apart). Uses a single
/// controller with an [Interval] for the delay, so no timers are left behind.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0, this.offset = const Offset(0, 0.08), this.duration = const Duration(milliseconds: 420)});
  final Widget child;
  final int index;
  final Offset offset;
  final Duration duration;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final int _delayMs = (widget.index.clamp(0, 10)) * 60;
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration + Duration(milliseconds: _delayMs))..forward();
  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    curve: Interval(_delayMs / (widget.duration.inMilliseconds + _delayMs), 1, curve: Curves.easeOutCubic),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _a,
        child: SlideTransition(
          position: Tween(begin: widget.offset, end: Offset.zero).animate(_a),
          child: widget.child,
        ),
      );
}

/// An integer that counts up (or down) to [value] whenever it changes.
class CountUpText extends StatelessWidget {
  const CountUpText(this.value, {super.key, this.style, this.format, this.duration = const Duration(milliseconds: 750), this.textAlign});
  final num value;
  final TextStyle? style;
  final String Function(num v)? format;
  final Duration duration;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text(
        format == null ? fmtInt(v.round()) : format!(v),
        textAlign: textAlign,
        maxLines: 1,
        style: (style ?? const TextStyle()).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}

/// A small "live" dot that beats once a second while [listenable] ticks.
/// No ticker of its own: it only animates when the race clock moves, so it
/// stops (and tests settle) when the clock is paused.
class LiveBeat extends StatelessWidget {
  const LiveBeat({super.key, required this.listenable, this.color = const Color(0xFFFF4D4D), this.size = 8});
  final ValueListenable<double> listenable;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: listenable,
      builder: (_, _, _) {
        final on = DateTime.now().second.isEven;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOut,
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: on ? color : color.withValues(alpha: 0.45),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withValues(alpha: on ? 0.7 : 0), blurRadius: on ? 9 : 0, spreadRadius: on ? 2 : 0)],
          ),
        );
      },
    );
  }
}

/// Animated check mark drawn as a stroke (success states).
class DrawnCheck extends StatefulWidget {
  const DrawnCheck({super.key, this.size = 72, this.color = const Color(0xFF2FA866)});
  final double size;
  final Color color;

  @override
  State<DrawnCheck> createState() => _DrawnCheckState();
}

class _DrawnCheckState extends State<DrawnCheck> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final ring = Curves.easeOutBack.transform((_c.value / 0.55).clamp(0, 1));
        final tick = Curves.easeOutCubic.transform(((_c.value - 0.4) / 0.6).clamp(0, 1));
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Transform.scale(
            scale: 0.6 + 0.4 * ring,
            child: CustomPaint(painter: _CheckPainter(widget.color, ring.clamp(0, 1), tick)),
          ),
        );
      },
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.color, this.ring, this.tick);
  final Color color;
  final double ring;
  final double tick;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r * ring, Paint()..color = color.withValues(alpha: 0.14));
    canvas.drawCircle(c, r * 0.78 * ring, Paint()..color = color);
    if (tick <= 0) return;
    final path = Path()
      ..moveTo(c.dx - r * 0.34, c.dy + r * 0.02)
      ..lineTo(c.dx - r * 0.09, c.dy + r * 0.26)
      ..lineTo(c.dx + r * 0.36, c.dy - r * 0.22);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * tick),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.13
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.ring != ring || old.tick != tick || old.color != color;
}

/// Shakes its child horizontally each time [trigger] changes (error states).
class Shake extends StatefulWidget {
  const Shake({super.key, required this.trigger, required this.child});
  final int trigger;
  final Widget child;

  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void didUpdateWidget(covariant Shake old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final t = _c.value;
          final dx = (1 - t) * 10 * math.sin(t * 6 * math.pi);
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
        child: widget.child,
      );
}
