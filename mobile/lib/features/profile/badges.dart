import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../data/achievements.dart';
import 'profile_widgets.dart';

/// Icon + colour for each badge.
(IconData, Color) badgeLook(BadgeId id) => switch (id) {
      BadgeId.halfFinisher => (Icons.flag_circle_rounded, RL.teal),
      BadgeId.sub140 => (Icons.timer_rounded, RL.amber),
      BadgeId.top2 => (Icons.military_tech_rounded, const Color(0xFFCA8A04)),
      BadgeId.categoryTop100 => (Icons.workspace_premium_rounded, const Color(0xFF8B5CF6)),
      BadgeId.overtaker => (Icons.fast_forward_rounded, const Color(0xFFEC4899)),
      BadgeId.negativeSplit => (Icons.speed_rounded, RL.green),
      BadgeId.dawnPatrol => (Icons.wb_twilight_rounded, const Color(0xFFF97316)),
      BadgeId.cheeredOn => (Icons.campaign_rounded, const Color(0xFFE11D48)),
      BadgeId.firstRunLah => (Icons.rocket_launch_rounded, const Color(0xFF3B82F6)),
      BadgeId.pbBreaker => (Icons.bolt_rounded, const Color(0xFFF59E0B)),
      BadgeId.targetSmashed => (Icons.track_changes_rounded, RL.red),
      BadgeId.fiveHalves => (Icons.filter_5_rounded, const Color(0xFF14B8A6)),
      BadgeId.firstFreeRun => (Icons.directions_run_rounded, const Color(0xFF10B981)),
      BadgeId.fiftyKmClub => (Icons.route_rounded, const Color(0xFF6366F1)),
    };

/// Round medal: gradient + icon when unlocked, grey with a lock when not.
class BadgeMedal extends StatelessWidget {
  const BadgeMedal({super.key, required this.badge, this.size = 58, this.forceUnlocked = false});
  final BadgeState badge;
  final double size;
  final bool forceUnlocked;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = badgeLook(badge.id);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final on = badge.unlocked || forceUnlocked;
    final hsl = HSLColor.fromColor(color);
    final light = hsl.withLightness((hsl.lightness + 0.18).clamp(0.0, 0.9)).toColor();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: on
                    ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [light, color])
                    : null,
                color: on ? null : (dark ? const Color(0xFF1F2937) : const Color(0xFFE9ECF2)),
                boxShadow: on ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: size * 0.22, offset: Offset(0, size * 0.06))] : null,
                border: Border.all(color: on ? Colors.white.withValues(alpha: 0.65) : (dark ? Colors.white10 : RL.line), width: size * 0.045),
              ),
              child: Icon(icon, size: size * 0.46, color: on ? Colors.white : (dark ? Colors.white24 : const Color(0xFFB4BCCB))),
            ),
          ),
          if (!on)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: size * 0.36,
                height: size * 0.36,
                decoration: BoxDecoration(color: dark ? const Color(0xFF374151) : RL.slate, shape: BoxShape.circle, border: Border.all(color: Theme.of(context).cardTheme.color ?? Colors.white, width: 2)),
                child: Icon(Icons.lock_rounded, size: size * 0.19, color: Colors.white),
              ),
            ),
          if (badge.isNew && !forceUnlocked)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(color: RL.red, borderRadius: BorderRadius.circular(99)),
                child: Text(tr('NEW'), style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w900)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Grid of every badge (3 per row on phones).
class BadgeGrid extends StatelessWidget {
  const BadgeGrid({super.key, required this.badges});
  final List<BadgeState> badges;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth > 520 ? 5 : (c.maxWidth > 400 ? 4 : 3);
        const gap = 8.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: 14,
          children: [
            for (var i = 0; i < badges.length; i++)
              SizedBox(
                width: w,
                child: Reveal(index: i % 9, child: _BadgeTile(badge: badges[i])),
              ),
          ],
        );
      },
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge});
  final BadgeState badge;

  @override
  Widget build(BuildContext context) {
    final (_, color) = badgeLook(badge.id);
    return Semantics(
      button: true,
      label: '${badge.title}. ${badge.unlocked ? tr('Unlocked') : tr('Locked')}',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showBadgeDetail(context, badge),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BadgeMedal(badge: badge),
              const SizedBox(height: 8),
              Text(
                badge.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: badge.unlocked ? ink(context) : muted(context),
                ),
              ),
              if (!badge.unlocked && badge.progress > 0) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: SlimProgress(value: badge.progress, color: color, height: 4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showBadgeDetail(BuildContext context, BadgeState badge) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final (_, color) = badgeLook(badge.id);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BadgeMedal(badge: badge, size: 96),
                const SizedBox(height: 16),
                Text(badge.title, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: ink(context))),
                const SizedBox(height: 6),
                Text(badge.description, textAlign: TextAlign.center, style: TextStyle(color: muted(context), height: 1.35)),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(badge.unlocked ? Icons.check_circle_rounded : Icons.lock_outline_rounded, size: 18, color: badge.unlocked ? RL.green : muted(context)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              badge.unlocked ? tr('Unlocked') : tr('Locked'),
                              style: TextStyle(fontWeight: FontWeight.w800, color: ink(context)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(badge.hint, style: TextStyle(color: ink(context), height: 1.3)),
                      if (!badge.unlocked) ...[
                        const SizedBox(height: 10),
                        SlimProgress(value: badge.progress, color: color, height: 6),
                      ],
                      if (badge.freeRun && !badge.unlocked) ...[
                        const SizedBox(height: 10),
                        Text(tr('Free runs you save on the Run tab count towards this badge.'), style: TextStyle(fontSize: 12.5, color: muted(context))),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

// ------------------------------------------------------------ celebration

/// Full-screen "Badge unlocked!" moment with confetti. Shown once per badge.
Future<void> showBadgeCelebration(BuildContext context, List<BadgeState> badges) => showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: tr('Close'),
      barrierColor: Colors.black.withValues(alpha: 0.62),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => _Celebration(badges: badges),
      transitionBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    );

class _Celebration extends StatefulWidget {
  const _Celebration({required this.badges});
  final List<BadgeState> badges;

  @override
  State<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<_Celebration> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..forward();
  late final List<_Confetto> _bits = _Confetto.burst(70, 7);
  int _shown = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _next() {
    if (_shown < widget.badges.length - 1) {
      setState(() => _shown++);
      _c.forward(from: 0.15);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final badge = widget.badges[_shown];
    final (_, color) = badgeLook(badge.id);
    final n = widget.badges.length;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(animation: _c, builder: (_, _) => CustomPaint(painter: _ConfettiPainter(_bits, _c.value))),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
                    decoration: BoxDecoration(
                      color: dark ? const Color(0xFF111827) : Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 40, spreadRadius: 2)],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          n == 1 ? tr('Badge unlocked!') : tr('{n} badges unlocked!', {'n': n}),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: RL.amber, fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 13),
                        ),
                        const SizedBox(height: 18),
                        AnimatedBuilder(
                          animation: _c,
                          builder: (_, child) {
                            final t = Curves.elasticOut.transform((_c.value / 0.55).clamp(0.0, 1.0));
                            return Transform.rotate(
                              angle: (1 - t) * -0.6,
                              child: Transform.scale(scale: 0.3 + 0.7 * t, child: child),
                            );
                          },
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              AnimatedBuilder(
                                animation: _c,
                                builder: (_, _) => CustomPaint(size: const Size(170, 170), painter: _RaysPainter(color, _c.value)),
                              ),
                              KeyedSubtree(key: ValueKey(badge.id), child: BadgeMedal(badge: badge, size: 110, forceUnlocked: true)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Column(
                            key: ValueKey(badge.id),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(badge.title, textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: ink(context))),
                              const SizedBox(height: 6),
                              Text(badge.hint, textAlign: TextAlign.center, style: TextStyle(color: muted(context), height: 1.3)),
                            ],
                          ),
                        ),
                        if (n > 1) ...[
                          const SizedBox(height: 14),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (var i = 0; i < n; i++)
                                AnimatedOpacity(
                                  duration: const Duration(milliseconds: 200),
                                  opacity: i == _shown ? 1 : 0.45,
                                  child: BadgeMedal(badge: widget.badges[i], size: 30, forceUnlocked: true),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _next,
                            child: Text(_shown < n - 1 ? tr('Next badge') : tr('Nice!')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Confetto {
  _Confetto(this.x, this.vx, this.vy, this.spin, this.color, this.size, this.round);
  final double x, vx, vy, spin, size;
  final Color color;
  final bool round;

  static List<_Confetto> burst(int n, int seed) {
    final r = math.Random(seed);
    const colors = [RL.amber, Color(0xFFEC4899), RL.teal, Color(0xFF8B5CF6), RL.green, Colors.white];
    return [
      for (var i = 0; i < n; i++)
        _Confetto(
          0.5 + (r.nextDouble() - 0.5) * 0.2,
          (r.nextDouble() - 0.5) * 1.4,
          -0.9 - r.nextDouble() * 0.9,
          (r.nextDouble() - 0.5) * 18,
          colors[r.nextInt(colors.length)],
          5 + r.nextDouble() * 6,
          r.nextBool(),
        ),
    ];
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.bits, this.t);
  final List<_Confetto> bits;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final fade = t < 0.8 ? 1.0 : (1 - t) / 0.2;
    for (final b in bits) {
      // Simple ballistic arc from the middle of the screen.
      final x = (b.x + b.vx * t) * size.width;
      final y = size.height * 0.42 + (b.vy * t + 1.6 * t * t) * size.height * 0.5;
      final paint = Paint()..color = b.color.withValues(alpha: fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(b.spin * t);
      if (b.round) {
        canvas.drawCircle(Offset.zero, b.size / 2.2, paint);
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: b.size, height: b.size * 0.45), const Radius.circular(1.5)), paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

/// Soft rotating light rays behind the medal.
class _RaysPainter extends CustomPainter {
  _RaysPainter(this.color, this.t);
  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final glow = Paint()
      ..shader = RadialGradient(colors: [color.withValues(alpha: 0.32), color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, glow);
    final ray = Paint()..color = color.withValues(alpha: 0.13 * math.min(1, t * 3));
    const n = 12;
    for (var i = 0; i < n; i++) {
      final a = i * 2 * math.pi / n + t * 1.2;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + r * math.cos(a - 0.09), c.dy + r * math.sin(a - 0.09))
        ..lineTo(c.dx + r * math.cos(a + 0.09), c.dy + r * math.sin(a + 0.09))
        ..close();
      canvas.drawPath(path, ray);
    }
  }

  @override
  bool shouldRepaint(_RaysPainter old) => old.t != t || old.color != color;
}
