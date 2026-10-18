import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import 'run_widgets.dart';

/// Full-screen "You finished!" moment: confetti, medal, net time counting
/// up, provisional place, and the two next steps (Insights, Share).
class FinishCelebration extends StatefulWidget {
  const FinishCelebration({super.key, required this.onClose});
  final VoidCallback onClose;

  @override
  State<FinishCelebration> createState() => _FinishCelebrationState();
}

class _FinishCelebrationState extends State<FinishCelebration> with TickerProviderStateMixin {
  late final AnimationController _confetti = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200))..forward();
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
  late final List<_Particle> _particles = _Particle.burst(150, math.Random(34144));

  @override
  void dispose() {
    _confetti.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final you = sim.youId;
    final netS = sim.plan(you).netS;
    final row = context.select<InsightsController, ResultRow>((c) => c.snapshot.result(you));
    final official = context.select<RaceSim, bool>((s) => s.official);
    final medal = CurvedAnimation(parent: _enter, curve: Curves.elasticOut);
    final fade = CurvedAnimation(parent: _enter, curve: const Interval(0, 0.5));
    return FadeTransition(
      opacity: fade,
      child: Material(
        color: const Color(0xF20B1220),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(child: CustomPaint(painter: _ConfettiPainter(_confetti, _particles))),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 90),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(
                        scale: medal,
                        child: Container(
                          width: 104,
                          height: 104,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const RadialGradient(colors: [Color(0xFFFFD27A), RL.amber]),
                            border: Border.all(color: Colors.white, width: 4),
                            boxShadow: [BoxShadow(color: RL.amber.withValues(alpha: 0.6), blurRadius: 30)],
                          ),
                          child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 56),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        tr('FINISHER'),
                        style: const TextStyle(color: RL.amber, fontWeight: FontWeight.w900, letterSpacing: 4, fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tr('You did it, {name}!', {'name': sim.you.firstName}),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24),
                      ),
                      const SizedBox(height: 16),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: CountUpText(
                          netS,
                          duration: const Duration(milliseconds: 1800),
                          format: (v) => fmtDuration(v, forceHours: true),
                          style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.w900, height: 1, letterSpacing: -1),
                        ),
                      ),
                      Text(tr('net time'), style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 18),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: row.overall == null
                            ? Text(tr('Working out your place…'), key: const ValueKey('wait'), style: const TextStyle(color: Colors.white70))
                            : Wrap(
                                key: ValueKey(row.overall!.place),
                                alignment: WrapAlignment.center,
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _Chip(
                                    top: ordinal(row.overall!.place),
                                    bottom: tr('of {n}', {'n': fmtInt(row.overall!.of)}),
                                  ),
                                  _Chip(top: tr('Top {pct}', {'pct': fmtPct(row.overall!.topPct)}), bottom: tr('overall')),
                                  if (row.category != null) _Chip(top: ordinal(row.category!.place), bottom: sim.race.categoryById(sim.you.categoryId).name),
                                ],
                              ),
                      ),
                      const SizedBox(height: 10),
                      Pill(official ? tr('Official') : tr('Provisional'), color: official ? RL.green : RL.amber),
                      const SizedBox(height: 26),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            widget.onClose();
                            openInsights(context, you);
                          },
                          icon: const Icon(Icons.insights_rounded),
                          label: Text(tr('See Race Insights')),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38, width: 1.5)),
                          onPressed: () {
                            widget.onClose();
                            openShareCard(context, you);
                          },
                          icon: const Icon(Icons.ios_share_rounded),
                          label: Text(tr('Share')),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: widget.onClose,
                        child: Text(tr('Close'), style: const TextStyle(color: Colors.white70)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.top, required this.bottom});
  final String top;
  final String bottom;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 92),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(top, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, fontFeatures: [FontFeature.tabularFigures()])),
            const SizedBox(height: 2),
            Text(bottom, style: const TextStyle(color: Colors.white60, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

class _Particle {
  _Particle(this.x, this.delay, this.speed, this.drift, this.spin, this.size, this.color, this.shape);
  final double x, delay, speed, drift, spin, size;
  final Color color;
  final int shape;

  static const _colors = [RL.amber, Color(0xFFFFD27A), Colors.white, RL.green, Color(0xFF3B82F6), Color(0xFFEC4899), RL.teal];

  static List<_Particle> burst(int n, math.Random r) => [
        for (var i = 0; i < n; i++)
          _Particle(
            r.nextDouble(),
            r.nextDouble() * 0.35,
            0.55 + r.nextDouble() * 0.6,
            (r.nextDouble() - 0.5) * 0.25,
            (r.nextDouble() - 0.5) * 14,
            5 + r.nextDouble() * 7,
            _colors[r.nextInt(_colors.length)],
            r.nextInt(3),
          ),
      ];
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.anim, this.particles) : super(repaint: anim);
  final Animation<double> anim;
  final List<_Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value;
    if (t >= 1) return;
    final paint = Paint();
    for (final p in particles) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final y = -20 + (size.height + 40) * local * p.speed * 1.4;
      if (y > size.height + 20) continue;
      final x = size.width * (p.x + p.drift * local) + math.sin(local * 10 + p.x * 20) * 14;
      final fadeOut = local > 0.8 ? (1 - local) / 0.2 : 1.0;
      paint.color = p.color.withValues(alpha: fadeOut.clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * local);
      switch (p.shape) {
        case 0:
          canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5), paint);
        case 1:
          canvas.drawCircle(Offset.zero, p.size * 0.35, paint);
        default:
          final path = Path()
            ..moveTo(0, -p.size * 0.5)
            ..lineTo(p.size * 0.45, p.size * 0.4)
            ..lineTo(-p.size * 0.45, p.size * 0.4)
            ..close();
          canvas.drawPath(path, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => false;
}
