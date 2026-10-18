import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import 'cheer_live.dart';
import 'runner_view.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Round initials avatar. Hollow ring when the position is estimated.
class RunnerAvatar extends StatelessWidget {
  const RunnerAvatar({super.key, required this.participant, required this.color, this.size = 46, this.ring, this.badge});
  final Participant participant;
  final Color color;
  final double size;

  /// Optional status ring colour.
  final Color? ring;
  final IconData? badge;

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, 0.18)!, color],
        ),
        border: ring == null ? null : Border.all(color: ring!, width: size * 0.06),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: size * 0.25, offset: Offset(0, size * 0.06))],
      ),
      child: Text(
        initials(participant),
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: size * 0.36, letterSpacing: 0.5),
      ),
    );
    if (badge == null) return avatar;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color ?? Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(badge, size: size * 0.3, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Not started / Running / Finished / DNF chip. Running gets a live dot.
class StatusChip extends StatelessWidget {
  const StatusChip(this.state, {super.key});
  final RunnerState state;

  @override
  Widget build(BuildContext context) {
    final c = stateColor(state);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: child)),
      child: Container(
        key: ValueKey(state),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state == RunnerState.running) LiveDot(color: c, size: 7) else Icon(stateIcon(state), size: 12, color: c),
            const SizedBox(width: 5),
            Text(
              stateLabel(state).toUpperCase(),
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: c),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small pulsing dot ("live").
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, this.color = RL.green, this.size = 8});
  final Color color;
  final double size;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 2,
      height: s * 2,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: s + s * _c.value,
              height: s + s * _c.value,
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.45 * (1 - _c.value))),
            ),
            Container(width: s, height: s, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
          ],
        ),
      ),
    );
  }
}

/// Integer that counts up to its new value.
class CountUp extends StatelessWidget {
  const CountUp(this.value, {super.key, this.style, this.prefix = '', this.suffix = '', this.duration = const Duration(milliseconds: 700)});
  final int value;
  final TextStyle? style;
  final String prefix;
  final String suffix;
  final Duration duration;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.toDouble()),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Text(
          '$prefix${fmtInt(v.round())}$suffix',
          maxLines: 1,
          style: (style ?? const TextStyle()).copyWith(fontFeatures: _tabular),
        ),
      );
}

/// Fade + slide in once, staggered by [index]. No timers (test friendly).
class Appear extends StatefulWidget {
  const Appear({super.key, required this.child, this.index = 0, this.dy = 0.12});
  final Widget child;
  final int index;
  final double dy;

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  late final int _delayMs = 70 * widget.index.clamp(0, 8);
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: 420 + _delayMs))..forward();
  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    curve: Interval(_delayMs / (420 + _delayMs), 1, curve: Curves.easeOutCubic),
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
          position: Tween(begin: Offset(0, widget.dy), end: Offset.zero).animate(_a),
          child: widget.child,
        ),
      );
}

/// Course progress: track with checkpoint ticks, filled distance and a knob
/// (hollow when the position is estimated).
class CourseProgressBar extends StatelessWidget {
  const CourseProgressBar({
    super.key,
    required this.fraction,
    required this.checkpointFractions,
    required this.color,
    this.estimated = false,
    this.passedUpTo = -1,
    this.height = 22,
  });
  final double fraction;
  final List<double> checkpointFractions;
  final Color color;
  final bool estimated;

  /// Index of the last checkpoint passed (ticks up to here are filled).
  final int passedUpTo;
  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _ProgressPainter(
          fraction: fraction,
          ticks: checkpointFractions,
          color: color,
          estimated: estimated,
          passedUpTo: passedUpTo,
          track: dark ? const Color(0xFF243044) : const Color(0xFFE8ECF2),
          surface: dark ? const Color(0xFF111827) : Colors.white,
        ),
      ),
    );
  }
}

class _ProgressPainter extends CustomPainter {
  _ProgressPainter({
    required this.fraction,
    required this.ticks,
    required this.color,
    required this.estimated,
    required this.passedUpTo,
    required this.track,
    required this.surface,
  });
  final double fraction;
  final List<double> ticks;
  final Color color;
  final bool estimated;
  final int passedUpTo;
  final Color track;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    const barH = 8.0;
    const r = 8.0; // knob radius
    final cy = size.height / 2;
    final left = r, right = size.width - r;
    final w = right - left;
    final bar = RRect.fromLTRBR(left, cy - barH / 2, right, cy + barH / 2, const Radius.circular(barH));
    canvas.drawRRect(bar, Paint()..color = track);
    final fx = left + w * fraction.clamp(0.0, 1.0);
    if (fx > left) {
      final fill = RRect.fromLTRBR(left, cy - barH / 2, fx, cy + barH / 2, const Radius.circular(barH));
      canvas.drawRRect(
        fill,
        Paint()
          ..shader = LinearGradient(colors: [color.withValues(alpha: 0.55), color]).createShader(Rect.fromLTRB(left, 0, math.max(fx, left + 1), 1)),
      );
    }
    for (var k = 0; k < ticks.length; k++) {
      final x = left + w * ticks[k];
      final passed = k <= passedUpTo;
      canvas.drawCircle(Offset(x, cy), passed ? 3.2 : 2.6, Paint()..color = passed ? Colors.white : surface);
      if (!passed) canvas.drawCircle(Offset(x, cy), 2.6, Paint()..color = track.withValues(alpha: 1)..style = PaintingStyle.stroke..strokeWidth = 1.4);
    }
    // Knob with a soft glow.
    canvas.drawCircle(Offset(fx, cy), r + 3, Paint()..color = color.withValues(alpha: 0.18));
    if (estimated) {
      canvas.drawCircle(Offset(fx, cy), r - 1, Paint()..color = surface);
      canvas.drawCircle(Offset(fx, cy), r - 1.5, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 3);
    } else {
      canvas.drawCircle(Offset(fx, cy), r, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(fx, cy), r - 2.5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.fraction != fraction || old.color != color || old.estimated != estimated || old.passedUpTo != passedUpTo || old.track != track;
}

/// A runner on the map: initials disc (hollow ring when estimated), name
/// pill above, pulse while running.
class RunnerPin extends StatefulWidget {
  const RunnerPin({super.key, required this.participant, required this.color, this.label, this.estimated = false, this.pulse = false, this.dim = false, this.size = 26, this.onTap});
  final Participant participant;
  final Color color;
  final String? label;
  final bool estimated;
  final bool pulse;
  final bool dim;
  final double size;
  final VoidCallback? onTap;

  static double boxWidth(String? label, double size) => label == null ? size + 18 : 130;
  static double boxHeight(String? label, double size) => size + 18 + (label == null ? 0 : 44);

  @override
  State<RunnerPin> createState() => _RunnerPinState();
}

class _RunnerPinState extends State<RunnerPin> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant RunnerPin old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_c.isAnimating) _c.repeat();
    if (!widget.pulse && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final s = w.size;
    final color = w.dim ? RL.slate : w.color;
    final disc = SizedBox(
      width: s + 18,
      height: s + 18,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (w.pulse)
            AnimatedBuilder(
              animation: _c,
              builder: (_, _) => Container(
                width: s + 18 * _c.value,
                height: s + 18 * _c.value,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.4 * (1 - _c.value))),
              ),
            ),
          Container(
            width: s,
            height: s,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: w.estimated ? Colors.white : color,
              border: Border.all(color: w.estimated ? color : Colors.white, width: w.estimated ? 3 : 2.5),
              boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 5, offset: Offset(0, 1))],
            ),
            child: Text(
              initials(w.participant),
              maxLines: 1,
              style: TextStyle(fontSize: s * 0.36, fontWeight: FontWeight.w900, color: w.estimated ? color : Colors.white),
            ),
          ),
        ],
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: w.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (w.label != null) ...[
            Container(
              height: 22,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(9),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1))],
              ),
              child: Text(w.label!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 0),
          ],
          disc,
          // Same height below as the label above keeps the disc centred on its point.
          if (w.label != null) const SizedBox(height: 22),
        ],
      ),
    );
  }
}

/// Map layer with followed runners, moving every frame from [clock].
/// GPS runners use the live position; runners without GPS are drawn as a
/// hollow ring at the position estimated from checkpoint passes.
class RunnersLayer extends StatelessWidget {
  const RunnersLayer({super.key, required this.clock, required this.ids, this.onTap, this.labels = true, this.size = 26, this.highlight});
  final ValueListenable<double> clock;
  final List<int> ids;
  final void Function(int id)? onTap;
  final bool labels;
  final double size;
  final int? highlight;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final follows = context.watch<FollowsController>().ids;
    return ValueListenableBuilder<double>(
      valueListenable: clock,
      builder: (context, t, _) {
        final snap = context.read<InsightsController>().snapshot;
        final views = [for (final id in ids) RunnerNow.of(sim, snap, id, t)];
        // Draw the highlighted runner last so it sits on top.
        if (highlight != null) {
          final i = ids.indexOf(highlight!);
          if (i >= 0) views.add(views.removeAt(i));
        }
        return MarkerLayer(
          markers: [
            for (final v in views)
              () {
                final id = v.participant.id;
                final label = !labels ? null : (id == sim.youId ? tr('You') : shortName(v.participant));
                final big = highlight == id ? size + 6 : size;
                return Marker(
                  key: ValueKey(id),
                  point: v.position,
                  width: RunnerPin.boxWidth(label, big),
                  height: RunnerPin.boxHeight(label, big),
                  child: RunnerPin(
                    participant: v.participant,
                    color: runnerColor(sim, follows, id),
                    label: label,
                    size: big,
                    estimated: v.estimated,
                    pulse: v.state == RunnerState.running && (id == sim.youId || highlight == id),
                    dim: v.state == RunnerState.dnf,
                    onTap: onTap == null ? null : () => onTap!(id),
                  ),
                );
              }(),
          ],
        );
      },
    );
  }
}

/// Translucent crowd dots (every 12th runner on course), refreshed ≤ 1 Hz.
class FieldLayer extends StatelessWidget {
  const FieldLayer({super.key, required this.live});
  final CheerLive live;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: live,
        builder: (_, _) => CircleLayer(
          circles: [
            for (final f in live.field)
              CircleMarker(
                point: f.point,
                radius: 3,
                color: (f.gender == Gender.f ? RL.female : RL.male).withValues(alpha: 0.5),
              ),
          ],
        ),
      );
}

/// Trail from the start to a runner's current distance.
class TrailLayer extends StatefulWidget {
  const TrailLayer({super.key, required this.clock, required this.id, required this.color});
  final ValueListenable<double> clock;
  final int id;
  final Color color;

  @override
  State<TrailLayer> createState() => _TrailLayerState();
}

class _TrailLayerState extends State<TrailLayer> {
  double _d = -1;
  List<LatLng> _points = const [];

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    return ValueListenableBuilder<double>(
      valueListenable: widget.clock,
      builder: (context, t, _) {
        final v = RunnerNow.of(sim, context.read<InsightsController>().snapshot, widget.id, t);
        if (v.distanceM <= 0) return const SizedBox.shrink();
        // Re-slice the route only every 25 m.
        final d = (v.distanceM / 25).floor() * 25.0;
        if (d != _d) {
          _d = d;
          _points = sim.race.route.slice(0, math.max(d, 1));
        }
        return PolylineLayer(
          polylines: [
            Polyline(points: [..._points, v.position], strokeWidth: 6, color: widget.color.withValues(alpha: 0.9)),
          ],
        );
      },
    );
  }
}

/// Static pin (cheer spot, meeting point).
class PlacePin extends StatelessWidget {
  const PlacePin({super.key, required this.icon, required this.color, this.label});
  final IconData icon;
  final Color color;
  final String? label;

  static Marker marker(LatLng point, {required IconData icon, required Color color, String? label}) => Marker(
        point: point,
        width: 150,
        height: label == null ? 46 : 92,
        alignment: Alignment.center,
        child: PlacePin(icon: icon, color: color, label: label),
      );

  @override
  Widget build(BuildContext context) {
    final pin = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Icon(icon, color: Colors.white, size: 19),
    );
    if (label == null) return Center(child: pin);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 24,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: RL.navy, borderRadius: BorderRadius.circular(9)),
          child: Text(label!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 2),
        pin,
        const SizedBox(height: 30),
      ],
    );
  }
}

/// Big tabular number with a small caption, left aligned, ellipsised.
class MiniStat extends StatelessWidget {
  const MiniStat({super.key, required this.label, required this.value, this.sub, this.color, this.size = 18});
  final String label;
  final String value;
  final String? sub;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: muted(context), letterSpacing: 0.3)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, maxLines: 1, style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: color ?? ink(context), fontFeatures: _tabular, height: 1.1)),
          ),
          if (sub != null)
            Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: muted(context))),
        ],
      );
}

/// Rebuilds only when a runner's [RunnerState] changes (not every tick).
class RunnerStateBuilder extends StatefulWidget {
  const RunnerStateBuilder({super.key, required this.id, required this.builder});
  final int id;
  final Widget Function(BuildContext context, RunnerState state) builder;

  @override
  State<RunnerStateBuilder> createState() => _RunnerStateBuilderState();
}

class _RunnerStateBuilderState extends State<RunnerStateBuilder> {
  late final RaceSim _sim = context.read<RaceSim>();
  late RunnerState _state = _sim.stateAt(widget.id, _sim.raceTime);

  @override
  void initState() {
    super.initState();
    _sim.clock.addListener(_check);
    _sim.addListener(_check);
  }

  @override
  void dispose() {
    _sim.clock.removeListener(_check);
    _sim.removeListener(_check);
    super.dispose();
  }

  void _check() {
    final s = _sim.stateAt(widget.id, _sim.raceTime);
    if (s != _state && mounted) setState(() => _state = s);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _state);
}
