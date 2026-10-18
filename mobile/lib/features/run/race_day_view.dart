import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../core/widgets/course_map.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import '../three/race3d_mode.dart';
import 'glance_mode.dart';
import 'pre_race_check.dart';
import 'race_run_controller.dart';
import 'run_widgets.dart';
import 'sos_button.dart';

const _tab = [FontFeature.tabularFigures()];

/// The "Race day" half of the Run tab, for your claimed bib.
class RaceDayView extends StatelessWidget {
  const RaceDayView({super.key, required this.controller});
  final RaceRunController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RunPhase>(
      valueListenable: controller.phase,
      builder: (context, phase, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(a), child: child),
        ),
        layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous.map((w) => Positioned(left: 0, right: 0, top: 0, child: w)), ?current]),
        child: switch (phase) {
          RunPhase.preRace => _PreRaceView(key: const ValueKey('pre'), controller: controller),
          RunPhase.waitingStart || RunPhase.running => _LiveView(key: const ValueKey('live'), controller: controller),
          RunPhase.finished => _FinishedView(key: const ValueKey('fin'), controller: controller),
          RunPhase.dnf => const _DnfView(key: ValueKey('dnf')),
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- pre-race

class _PreRaceView extends StatelessWidget {
  const _PreRaceView({super.key, required this.controller});
  final RaceRunController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        FadeSlideIn(index: 0, child: _BibCard()),
        SizedBox(height: 14),
        FadeSlideIn(index: 1, child: _CorralCard()),
        SizedBox(height: 14),
        FadeSlideIn(index: 2, child: PreRaceCheckCard()),
        SizedBox(height: 14),
        FadeSlideIn(index: 3, child: RunSettingsCard()),
      ],
    );
  }
}

/// Your race bib, as printed (claimed with bib + verification code, F06).
class _BibCard extends StatelessWidget {
  const _BibCard();

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final you = sim.you;
    final race = sim.race;
    return Hero(
      tag: 'run-bib',
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(RL.radius + 2),
          boxShadow: [BoxShadow(color: RL.navy.withValues(alpha: 0.16), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: RL.navy,
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              child: Row(
                children: [
                  const Icon(Icons.directions_run_rounded, color: RL.amber, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sim.event.name.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5, letterSpacing: 1),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Pill(tr('Claimed'), color: RL.green, filled: true, icon: Icons.verified_rounded),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
              child: Column(
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      you.bib,
                      style: const TextStyle(fontSize: 76, fontWeight: FontWeight.w900, color: RL.navy, letterSpacing: 6, height: 1.05, fontFeatures: _tab),
                    ),
                  ),
                  Text(
                    you.name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900, color: RL.navy, letterSpacing: 2),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _BibFact(Icons.person_rounded, race.categoryById(you.categoryId).name),
                      _BibFact(Icons.straighten_rounded, tr('Half marathon · 21.1 km')),
                      _BibFact(Icons.flag_rounded, tr('Gun {time}', {'time': fmtClock(race.scheduledStart)})),
                    ],
                  ),
                ],
              ),
            ),
            Container(height: 7, decoration: const BoxDecoration(gradient: LinearGradient(colors: [RL.amber, Color(0xFFF5B342), RL.amber]))),
          ],
        ),
      ),
    );
  }
}

class _BibFact extends StatelessWidget {
  const _BibFact(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: RL.bg, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: RL.slate),
            const SizedBox(width: 4),
            Flexible(child: Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: RL.slate))),
          ],
        ),
      );
}

/// "Waiting in corral" with a live countdown to the gun.
class _CorralCard extends StatelessWidget {
  const _CorralCard();

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final playing = context.select<RaceSim, bool>((s) => s.playing);
    return HeroPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ValueListenableBuilder<double>(
                valueListenable: sim.clock,
                builder: (_, t, _) {
                  final left = math.max(0.0, -t);
                  return SizedBox(
                    width: 104,
                    height: 104,
                    child: CustomPaint(
                      painter: _CountdownRing(progress: (left / 300).clamp(0.0, 1.0)),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                child: Text(
                                  fmtDuration(left),
                                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, fontFeatures: _tab),
                                ),
                              ),
                            ),
                            Text(tr('to gun'), style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Pill(tr('Waiting in corral'), color: RL.amber, filled: true, icon: Icons.hourglass_top_rounded),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr('Gun at {time}', {'time': fmtClock(sim.race.scheduledStart)}),
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr('Net time starts when you cross the start mat, not at the gun.'),
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Icon(Icons.touch_app_rounded, color: RL.amber, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    playing
                        ? tr('The organizer fires the gun. In this demo, tap the race clock at the bottom right, then Fire the gun.')
                        : tr('Countdown paused. In this demo, tap the race clock at the bottom right, then Fire the gun.'),
                    style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CountdownRing extends CustomPainter {
  _CountdownRing({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 5;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7,
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..shader = const SweepGradient(colors: [Color(0xFFF5B342), RL.amber, Color(0xFFF5B342)]).createShader(Rect.fromCircle(center: c, radius: r))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CountdownRing old) => old.progress != progress;
}

// -------------------------------------------------------------------- live

class _LiveView extends StatelessWidget {
  const _LiveView({super.key, required this.controller});
  final RaceRunController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FadeSlideIn(index: 0, child: _LiveHero(controller: controller)),
        const SizedBox(height: 12),
        FadeSlideIn(index: 1, child: _TargetBanner(controller: controller)),
        FadeSlideIn(index: 2, child: _OvertakeCard(controller: controller)),
        const SizedBox(height: 12),
        FadeSlideIn(index: 3, child: _NextCheckpointCard(controller: controller)),
        const SizedBox(height: 12),
        FadeSlideIn(index: 4, child: _LiveMapCard(controller: controller)),
        const SizedBox(height: 12),
        FadeSlideIn(index: 5, child: _SplitsCard(controller: controller)),
        const SizedBox(height: 12),
        FadeSlideIn(index: 6, child: _CheersCard(controller: controller)),
        const SizedBox(height: 12),
        const FadeSlideIn(index: 7, child: SosCard()),
      ],
    );
  }
}

void _openGlance(BuildContext context, RaceRunController c) {
  final sim = c.sim;
  final units = context.read<SettingsController>().units;
  GlanceModeScreen.open(
    context,
    listenable: sim.clock,
    hero: () => GlanceMetric(fmtDuration(sim.elapsedAt(c.you, sim.raceTime), forceHours: true), tr('Net time')),
    metrics: () {
      final t = sim.raceTime;
      final d = c.distanceAt(t);
      final e = sim.elapsedAt(c.you, t);
      final place = c.heavy.value?.place;
      return [
        GlanceMetric(fmtDistance(d, units, decimals: 2, withUnit: false), tr('Distance ({unit})', {'unit': distUnit(units)})),
        GlanceMetric(fmtPace(sim.paceAt(c.you, t), units, withUnit: false), tr('Pace {unit}', {'unit': paceUnit(units)}), color: RL.amber),
        GlanceMetric(d < 50 ? '–:–' : fmtPace(e / (d / 1000), units, withUnit: false), tr('Avg pace')),
        GlanceMetric(place == null ? '–' : '#${fmtInt(place)}', tr('On the road')),
      ];
    },
    footer: () {
      final t = sim.raceTime;
      final cp = c.nextCheckpoint(c.distanceAt(t));
      if (cp == null) return tr('Finish!');
      final eta = sim.etaToDistance(c.you, cp.distanceM, t);
      return tr('Next {cp} in {time}', {'cp': cp.shortLabel, 'time': eta == null ? '–' : fmtDuration(eta - t)});
    },
  );
}

class _LiveHero extends StatelessWidget {
  const _LiveHero({required this.controller});
  final RaceRunController controller;

  @override
  Widget build(BuildContext context) {
    final sim = controller.sim;
    final you = controller.you;
    final units = context.select<SettingsController, Units>((s) => s.units);
    return HeroPanel(
      padding: const EdgeInsets.fromLTRB(18, 12, 8, 18),
      child: ValueListenableBuilder<double>(
        valueListenable: sim.clock,
        builder: (context, t, _) {
          final waiting = sim.stateAt(you, t) == RunnerState.notStarted;
          final d = controller.distanceAt(t);
          final elapsed = sim.elapsedAt(you, t);
          final avg = d < 50 ? null : elapsed / (d / 1000);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  LiveDot(color: waiting ? RL.amber : const Color(0xFF34D399)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      waiting ? tr('GUN FIRED · HEADING TO THE START') : tr('LIVE · BIB {bib}', {'bib': sim.you.bib}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 11.5, letterSpacing: 1),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Glance mode'),
                    onPressed: () => _openGlance(context, controller),
                    icon: const Icon(Icons.fullscreen_rounded, color: Colors.white),
                  ),
                ],
              ),
              if (waiting) ...[
                Metric(
                  value: fmtDuration(math.max(0, controller.startDelayS - t)),
                  label: tr('until you cross the start mat'),
                  size: 54,
                  color: Colors.white,
                  labelColor: Colors.white60,
                ),
                const SizedBox(height: 6),
                Text(
                  tr('Corrals move up slowly. Your net time starts at the mat.'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ] else ...[
                Metric(value: fmtDuration(elapsed, forceHours: true), label: tr('Net time'), size: 58, color: Colors.white, labelColor: Colors.white60),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Metric(
                          value: fmtDistance(d, units, decimals: 2, withUnit: false),
                          unit: distUnit(units),
                          label: tr('Distance'),
                          size: 24,
                          color: Colors.white,
                          labelColor: Colors.white60,
                        ),
                      ),
                      Expanded(
                        child: Metric(
                          value: fmtPace(sim.paceAt(you, t), units, withUnit: false),
                          unit: paceUnit(units),
                          label: tr('Current pace'),
                          size: 24,
                          color: RL.amber,
                          labelColor: Colors.white60,
                        ),
                      ),
                      Expanded(
                        child: Metric(
                          value: fmtPace(avg, units, withUnit: false),
                          unit: paceUnit(units),
                          label: tr('Avg pace'),
                          size: 24,
                          color: Colors.white,
                          labelColor: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _CourseProgress(fraction: d / sim.race.distanceM, checkpoints: [for (final c in sim.race.checkpoints) c.distanceM / sim.race.distanceM]),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: ValueListenableBuilder<LiveHeavy?>(
                  valueListenable: controller.heavy,
                  builder: (_, h, _) => Row(
                    children: [
                      Text(fmtPct(d / sim.race.distanceM * 100), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontFeatures: _tab)),
                      const Spacer(),
                      if (h != null)
                        Flexible(
                          child: Text(
                            tr('#{place} on the road', {'place': fmtInt(h.place)}),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontFeatures: _tab),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Thin course bar with checkpoint ticks and a glowing runner head.
class _CourseProgress extends StatelessWidget {
  const _CourseProgress({required this.fraction, required this.checkpoints});
  final double fraction;
  final List<double> checkpoints;

  @override
  Widget build(BuildContext context) => SizedBox(height: 16, child: CustomPaint(painter: _ProgressPainter(fraction.clamp(0.0, 1.0), checkpoints), size: Size.infinite));
}

class _ProgressPainter extends CustomPainter {
  _ProgressPainter(this.f, this.cps);
  final double f;
  final List<double> cps;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final track = RRect.fromLTRBR(0, y - 3, size.width, y + 3, const Radius.circular(3));
    canvas.drawRRect(track, Paint()..color = Colors.white.withValues(alpha: 0.14));
    if (f > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(0, y - 3, size.width * f, y + 3, const Radius.circular(3)),
        Paint()..shader = const LinearGradient(colors: [Color(0xFFF5B342), RL.amber]).createShader(Offset.zero & size),
      );
    }
    for (final c in cps) {
      final x = size.width * c;
      canvas.drawCircle(Offset(x, y), 3.2, Paint()..color = c <= f ? RL.amber : Colors.white.withValues(alpha: 0.4));
    }
    final hx = size.width * f;
    canvas.drawCircle(Offset(hx, y), 8, Paint()..color = RL.amber.withValues(alpha: 0.3));
    canvas.drawCircle(Offset(hx, y), 5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _ProgressPainter old) => old.f != f;
}

/// Projected finish vs target, with an alert when you're behind.
class _TargetBanner extends StatelessWidget {
  const _TargetBanner({required this.controller});
  final RaceRunController controller;

  @override
  Widget build(BuildContext context) {
    final sim = controller.sim;
    final s = context.watch<SettingsController>();
    return ValueListenableBuilder<double>(
      valueListenable: controller.mapTick,
      builder: (context, t, _) {
        if (sim.stateAt(controller.you, t) != RunnerState.running) return const SizedBox.shrink();
        final proj = sim.projectedFinish(controller.you, t);
        if (proj == null) return const SizedBox.shrink();
        final target = s.targetTimeS.toDouble();
        final behind = proj > target;
        final d = controller.distanceAt(t);
        final left = (sim.race.distanceM - d) / 1000;
        final timeLeft = target - sim.elapsedAt(controller.you, t);
        final needed = left > 0.05 && timeLeft > 0 ? timeLeft / left : null;
        final color = behind ? RL.red : RL.green;
        final dark = Theme.of(context).brightness == Brightness.dark;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: dark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(RL.radius),
              border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
            ),
            child: InkWell(
              onTap: () => showTargetPicker(context),
              child: Row(
                children: [
                  Icon(behind ? Icons.warning_amber_rounded : Icons.verified_rounded, color: color, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          behind ? tr('Target alert') : tr('On target'),
                          style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.8),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          behind
                              ? tr('Projected {proj}, {gap} behind your {target} target.', {'proj': fmtDuration(proj), 'gap': fmtGap(proj - target), 'target': fmtDuration(target)})
                              : tr('Projected {proj}, {gap} under your {target} target.', {'proj': fmtDuration(proj), 'gap': fmtGap(target - proj), 'target': fmtDuration(target)}),
                          style: TextStyle(fontWeight: FontWeight.w800, color: ink(context)),
                        ),
                        if (behind) ...[
                          const SizedBox(height: 2),
                          Text(
                            needed == null ? tr('Target is out of reach today. Run your own race.') : tr('Hold {pace} from here to make it.', {'pace': fmtPace(needed, s.units)}),
                            style: TextStyle(fontSize: 12.5, color: muted(context)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// "You've passed 1,094 runners" since the start line.
class _OvertakeCard extends StatelessWidget {
  const _OvertakeCard({required this.controller, this.finished = false});
  final RaceRunController controller;
  final bool finished;

  @override
  Widget build(BuildContext context) {
    return RLCard(
      child: ValueListenableBuilder<LiveHeavy?>(
        valueListenable: controller.heavy,
        builder: (context, h, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(tr('Overtakes since the start line'), trailing: const Icon(Icons.trending_up_rounded, color: RL.amber, size: 20)),
            if (h == null)
              Text(tr('Counting the runners around you…'), style: TextStyle(color: muted(context)))
            else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: CountUpText(h.passed, style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w900, color: RL.amber, height: 1)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        finished ? tr('runners passed on your way to the finish') : tr('runners passed so far'),
                        style: TextStyle(fontWeight: FontWeight.w700, color: ink(context)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                h.passed >= h.passedBy
                    ? tr('Only {n} passed you. Strong, steady running.', {'n': fmtInt(h.passedBy)})
                    : tr('{n} runners passed you. Settle in and pick them off later.', {'n': fmtInt(h.passedBy)}),
                style: TextStyle(fontSize: 12.5, color: muted(context)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NextCheckpointCard extends StatelessWidget {
  const _NextCheckpointCard({required this.controller});
  final RaceRunController controller;

  @override
  Widget build(BuildContext context) {
    final sim = controller.sim;
    final units = context.select<SettingsController, Units>((s) => s.units);
    return RLCard(
      child: ValueListenableBuilder<double>(
        valueListenable: controller.mapTick,
        builder: (context, t, _) {
          final d = controller.distanceAt(t);
          final cp = controller.nextCheckpoint(d);
          final finishEta = sim.etaToDistance(controller.you, sim.race.distanceM, t);
          if (cp == null) {
            return InfoRow(icon: Icons.sports_score_rounded, color: RL.amber, title: tr('Finish straight!'), subtitle: sim.race.finish.name);
          }
          final eta = sim.etaToDistance(controller.you, cp.distanceM, t);
          return Column(
            children: [
              InfoRow(
                icon: Icons.flag_circle_rounded,
                color: RL.teal,
                title: tr('Next: {name} ({cp})', {'name': cp.name, 'cp': cp.shortLabel}),
                subtitle: tr('{dist} to go · ETA {clock}', {'dist': fmtDistance(cp.distanceM - d, units, decimals: 2), 'clock': eta == null ? '–' : fmtClock(sim.wallClockAt(eta))}),
                trailing: eta == null
                    ? null
                    : Text(fmtDuration(math.max(0, eta - t)), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: ink(context), fontFeatures: _tab)),
              ),
              const Divider(height: 20),
              InfoRow(
                icon: Icons.sports_score_rounded,
                color: RL.amber,
                title: tr('Finish ETA {clock}', {'clock': finishEta == null ? '–' : fmtClock(sim.wallClockAt(finishEta))}),
                subtitle: tr('{dist} left at your current pace', {'dist': fmtDistance(sim.race.distanceM - d, units)}),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LiveMapCard extends StatelessWidget {
  const _LiveMapCard({required this.controller});
  final RaceRunController controller;

  @override
  Widget build(BuildContext context) {
    final sim = controller.sim;
    return RLCard(
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 230,
            child: ValueListenableBuilder<double>(
              valueListenable: controller.mapTick,
              builder: (context, t, _) {
                final d = controller.distanceAt(t);
                final friends = sim.friendIds;
                return CourseMap(
                  race: sim.race,
                  interactive: false,
                  showLandmarks: false,
                  padding: const EdgeInsets.all(18),
                  doneUpTo: d,
                  dots: [
                    for (final (i, id) in friends.indexed)
                      if (sim.stateAt(id, t) == RunnerState.running)
                        MapDot(
                          point: sim.positionAt(id, t),
                          color: RL.series[(i + 1) % RL.series.length],
                          size: 13,
                          estimated: !sim.participant(id).hasGps,
                        ),
                    MapDot(point: sim.race.route.at(d), color: RL.amber, pulse: true, size: 20, icon: Icons.directions_run_rounded),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _Legend(color: RL.amber, label: tr('You')),
                for (final (i, id) in sim.friendIds.indexed)
                  _Legend(
                    color: RL.series[(i + 1) % RL.series.length],
                    label: sim.participant(id).hasGps ? sim.participant(id).firstName : tr('{name} (estimated)', {'name': sim.participant(id).firstName}),
                    hollow: !sim.participant(id).hasGps,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.hollow = false});
  final Color color;
  final String label;
  final bool hollow;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(shape: BoxShape.circle, color: hollow ? Colors.transparent : color, border: Border.all(color: color, width: 2.5)),
          ),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: muted(context))),
        ],
      );
}

class _SplitsCard extends StatelessWidget {
  const _SplitsCard({required this.controller, this.all = false});
  final RaceRunController controller;
  final bool all;

  @override
  Widget build(BuildContext context) {
    final units = context.select<SettingsController, Units>((s) => s.units);
    return RLCard(
      child: ValueListenableBuilder<int>(
        valueListenable: controller.kmDone,
        builder: (context, km, _) {
          final splits = controller.splitsAt(controller.sim.raceTime);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionLabel(
                tr('Km splits'),
                trailing: splits.isEmpty ? null : Pill(tr('Best {pace}', {'pace': fmtPace(splits.reduce(math.min), Units.km)}), color: RL.amber),
              ),
              KmSplitsList(splitsS: splits, units: units, maxRows: all ? null : 6),
            ],
          );
        },
      ),
    );
  }
}

class _CheersCard extends StatelessWidget {
  const _CheersCard({required this.controller});
  final RaceRunController controller;

  @override
  Widget build(BuildContext context) {
    final sim = controller.sim;
    context.select<RaceSim, int>((s) => s.cheersFor(s.youId).length);
    final cheers = sim.cheersFor(sim.youId);
    final s = context.watch<SettingsController>();
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(
            tr('Cheers for you'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (cheers.isNotEmpty) Pill('${cheers.length}', color: const Color(0xFFEC4899)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: s.readCheers ? tr('Reading cheers aloud') : tr('Cheers muted'),
                  onPressed: () => s.readCheers = !s.readCheers,
                  icon: Icon(s.readCheers ? Icons.volume_up_rounded : Icons.volume_off_rounded, size: 20, color: s.readCheers ? const Color(0xFFEC4899) : muted(context)),
                ),
              ],
            ),
          ),
          if (cheers.isEmpty)
            Text(tr('Messages from friends pop up here and are read aloud.'), style: TextStyle(color: muted(context)))
          else
            for (final (i, c) in cheers.take(5).indexed)
              FadeSlideIn(
                key: ObjectKey(c),
                index: i == 0 ? 0 : 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: const Color(0xFFEC4899).withValues(alpha: 0.15),
                        child: Text(c.from.isEmpty ? '?' : c.from[0].toUpperCase(), style: const TextStyle(color: Color(0xFFEC4899), fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEC4899).withValues(alpha: 0.08),
                            borderRadius: const BorderRadius.only(topRight: Radius.circular(14), bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(c.from, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: ink(context)))),
                                  Text(fmtClock(c.at), style: TextStyle(fontSize: 11, color: muted(context))),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(c.body, style: TextStyle(color: ink(context))),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- finished

class _FinishedView extends StatelessWidget {
  const _FinishedView({super.key, required this.controller});
  final RaceRunController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FadeSlideIn(index: 0, child: _FinishSummary(controller: controller)),
        const SizedBox(height: 12),
        FadeSlideIn(index: 1, child: _OvertakeCard(controller: controller, finished: true)),
        const SizedBox(height: 12),
        FadeSlideIn(index: 2, child: _SplitsCard(controller: controller, all: true)),
        const SizedBox(height: 12),
        FadeSlideIn(index: 3, child: _CheersCard(controller: controller)),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () => openRace3D(context, Race3DMode.replay, focusParticipantId: controller.you),
          icon: const Icon(Icons.view_in_ar_rounded),
          label: Text(tr('Replay your race in 3D')),
        ),
      ],
    );
  }
}

class _FinishSummary extends StatelessWidget {
  const _FinishSummary({required this.controller});
  final RaceRunController controller;

  @override
  Widget build(BuildContext context) {
    final sim = controller.sim;
    final you = controller.you;
    final plan = sim.plan(you);
    final units = context.select<SettingsController, Units>((s) => s.units);
    final row = context.select<InsightsController, ResultRow>((c) => c.snapshot.result(you));
    final official = context.select<RaceSim, bool>((s) => s.official);
    final overall = row.overall;
    return Hero(
      tag: 'run-finish',
      child: HeroPanel(
        colors: const [Color(0xFF233A6B), RL.navy, Color(0xFF3A2A0E)],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Pill(tr('Finisher'), color: RL.amber, filled: true, icon: Icons.emoji_events_rounded),
                const Spacer(),
                Pill(official ? tr('Official') : tr('Provisional'), color: official ? RL.green : Colors.white),
              ],
            ),
            const SizedBox(height: 12),
            Metric(value: fmtDuration(plan.netS, forceHours: true), label: tr('Net time'), size: 58, color: Colors.white, labelColor: Colors.white60),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: Metric(value: fmtDuration(plan.startDelayS + plan.netS, forceHours: true), label: tr('Gun time'), size: 20, color: Colors.white, labelColor: Colors.white60)),
                Expanded(child: Metric(value: fmtDuration(plan.startDelayS), label: tr('Start delay'), size: 20, color: Colors.white, labelColor: Colors.white60)),
                Expanded(
                  child: Metric(
                    value: fmtPace(plan.netS / (sim.race.distanceM / 1000), units, withUnit: false),
                    unit: paceUnit(units),
                    label: tr('Avg pace'),
                    size: 20,
                    color: RL.amber,
                    labelColor: Colors.white60,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: overall == null
                  ? Text(tr('Working out your place…'), key: const ValueKey('w'), style: const TextStyle(color: Colors.white70))
                  : Container(
                      key: ValueKey(overall.place),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
                      child: Row(
                        children: [
                          const Icon(Icons.leaderboard_rounded, color: RL.amber),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              tr('{place} of {of} · Top {pct}', {'place': ordinal(overall.place), 'of': fmtInt(overall.of), 'pct': fmtPct(overall.topPct)}),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontFeatures: _tab),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => openInsights(context, you),
                    icon: const Icon(Icons.insights_rounded, size: 20),
                    label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('See Race Insights'))),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38, width: 1.5), minimumSize: const Size(52, 52)),
                  onPressed: () => openShareCard(context, you),
                  child: Semantics(label: tr('Share'), child: const Icon(Icons.ios_share_rounded)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DnfView extends StatelessWidget {
  const _DnfView({super.key});

  @override
  Widget build(BuildContext context) {
    return RLCard(
      child: InfoRow(
        icon: Icons.do_not_disturb_on_rounded,
        color: RL.slate,
        title: tr('Did not finish'),
        subtitle: tr('Every start line counts. Rest up and come back stronger.'),
      ),
    );
  }
}
