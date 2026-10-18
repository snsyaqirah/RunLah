import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import 'cheer_live.dart';
import 'cheer_widgets.dart';
import 'runner_detail_screen.dart';
import 'runner_view.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Hero tag shared by the card avatar and the runner detail header.
String avatarHeroTag(int id) => 'cheer-avatar-$id';

/// A followed runner, live: status, distance along the course with
/// checkpoint ticks, pace, finish ETA, last checkpoint and the overtakes
/// since that checkpoint.
class LiveRunnerCard extends StatelessWidget {
  const LiveRunnerCard({super.key, required this.id, required this.live});
  final int id;
  final CheerLive live;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final follows = context.watch<FollowsController>();
    final p = sim.participant(id);
    final you = id == sim.youId;
    final color = runnerColor(sim, follows.ids, id);
    final category = sim.race.categoryById(p.categoryId).name;
    return RLCard(
      onTap: () => openRunnerDetail(context, id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Hero(
                tag: avatarHeroTag(id),
                child: RunnerAvatar(participant: p, color: color, badge: p.hasGps ? Icons.gps_fixed_rounded : Icons.flag_circle_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            you ? tr('You · {name}', {'name': p.firstName}) : p.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ink(context)),
                          ),
                        ),
                        if (!you && !follows.notifies(id)) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.notifications_off_rounded, size: 14, color: muted(context)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tr('Bib {bib} · {cat}', {'bib': p.bib, 'cat': category}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: muted(context)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<double>(
                valueListenable: sim.clock,
                builder: (_, t, _) => StatusChip(sim.stateAt(id, t)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ValueListenableBuilder<double>(
            valueListenable: sim.clock,
            builder: (context, t, _) {
              final v = RunnerNow.of(sim, context.read<InsightsController>().snapshot, id, t);
              return AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _CardBody(view: v, color: color, live: live, sim: sim),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({required this.view, required this.color, required this.live, required this.sim});
  final RunnerNow view;
  final Color color;
  final CheerLive live;
  final RaceSim sim;

  @override
  Widget build(BuildContext context) {
    final units = context.select<SettingsController, Units>((s) => s.units);
    final race = sim.race;
    final v = view;
    final ticks = [for (final c in race.checkpoints) c.distanceM / race.distanceM];
    final bar = CourseProgressBar(fraction: v.fraction, checkpointFractions: ticks, color: color, estimated: v.estimated, passedUpTo: v.lastCp);

    switch (v.state) {
      case RunnerState.notStarted:
        final preGun = sim.status == RaceStatus.preRace;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            bar,
            const SizedBox(height: 8),
            _InfoLine(
              icon: preGun ? Icons.schedule_rounded : Icons.groups_rounded,
              text: preGun
                  ? tr('Gun at {time} · {place}', {'time': fmtClock(sim.gunWallClock), 'place': race.start.name})
                  : tr('In the start pen · crossing the mat soon'),
            ),
          ],
        );
      case RunnerState.finished:
        return _FinishedBody(view: v, color: color, sim: sim, bar: bar);
      case RunnerState.dnf:
        final cp = v.lastCp >= 0 ? race.checkpoints[v.lastCp] : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            bar,
            const SizedBox(height: 8),
            _InfoLine(
              icon: Icons.info_outline_rounded,
              color: RL.red,
              text: cp == null
                  ? tr('Did not finish')
                  : tr('Did not finish · last seen at {cp} {place}, {time}', {
                      'cp': cpLabel(cp),
                      'place': cp.name,
                      'time': fmtClock(sim.wallClockAt(v.lastCpTime!)),
                    }),
            ),
          ],
        );
      case RunnerState.running:
        final cp = v.lastCp >= 0 ? race.checkpoints[v.lastCp] : race.start;
        final projected = v.finishEta == null ? null : v.finishEta! - sim.plan(v.participant.id).startDelayS;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${v.estimated ? '≈' : ''}${fmtDistance(v.distanceM, units, withUnit: false)}',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: ink(context), fontFeatures: _tabular, height: 1),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '/ ${fmtDistance(race.distanceM, units)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: muted(context)),
                    ),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    fmtDuration(v.elapsedS),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color, fontFeatures: _tabular),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            bar,
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: MiniStat(label: v.estimated ? tr('Pace (est.)') : tr('Pace'), value: fmtPace(v.paceSPerKm, units, withUnit: false), sub: paceUnit(units))),
                Expanded(
                  child: MiniStat(
                    label: tr('Finish ETA'),
                    value: v.finishEta == null ? '–' : fmtClock(sim.wallClockAt(v.finishEta!)),
                    sub: projected == null ? null : '≈ ${fmtDuration(projected)}',
                  ),
                ),
                Expanded(
                  child: MiniStat(
                    label: tr('Last checkpoint'),
                    value: cpLabel(cp),
                    sub: v.lastCpTime == null ? null : tr('at {time}', {'time': fmtClock(sim.wallClockAt(v.lastCpTime!))}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _OvertakeStrip(id: v.participant.id, live: live, cpName: cpLabel(cp), estimated: v.estimated),
          ],
        );
    }
  }
}

class _FinishedBody extends StatelessWidget {
  const _FinishedBody({required this.view, required this.color, required this.sim, required this.bar});
  final RunnerNow view;
  final Color color;
  final RaceSim sim;
  final Widget bar;

  @override
  Widget build(BuildContext context) {
    final id = view.participant.id;
    final snap = context.watch<InsightsController>().snapshot;
    final result = snap.result(id);
    final cat = sim.race.categoryById(view.participant.categoryId).name;
    final meet = MeetingPoint.forRunner(view.participant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  fmtDuration(view.finishNetS),
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: ink(context), fontFeatures: _tabular, height: 1),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(tr('net'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: muted(context))),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                tr('at {time}', {'time': fmtClock(sim.wallClockAt(view.finishEta ?? 0))}),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        bar,
        if (result.overall != null) ...[
          const SizedBox(height: 8),
          Text(
            tr('{place} overall · {cplace} in {cat}', {
              'place': ordinal(result.overall!.place),
              'cplace': ordinal(result.category!.place),
              'cat': cat,
            }),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink(context)),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _SmallAction(
                icon: Icons.insights_rounded,
                label: tr('Race Insights'),
                color: RL.amber,
                onTap: () => openInsights(context, id),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SmallAction(
                icon: Icons.place_rounded,
                label: tr('Meet at {code}', {'code': meet.code}),
                color: RL.teal,
                onTap: () => openRunnerDetail(context, id, scrollToMeet: true),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OvertakeStrip extends StatelessWidget {
  const _OvertakeStrip({required this.id, required this.live, required this.cpName, required this.estimated});
  final int id;
  final CheerLive live;
  final String cpName;
  final bool estimated;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ListenableBuilder(
      listenable: live,
      builder: (context, _) {
        final c = live.counts(id);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: RL.green.withValues(alpha: dark ? 0.16 : 0.09),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.keyboard_double_arrow_up_rounded, size: 18, color: RL.green),
              const SizedBox(width: 4),
              CountUp(c.passed, prefix: estimated ? '≈' : '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: RL.green)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tr('passed since {cp}', {'cp': cpName}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: ink(context)),
                ),
              ),
              if (c.passedBy > 0) ...[
                const Icon(Icons.keyboard_double_arrow_down_rounded, size: 16, color: RL.red),
                CountUp(c.passedBy, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: RL.red)),
                const SizedBox(width: 8),
              ],
              if (c.roadPlace > 0)
                Text(
                  '#${fmtInt(c.roadPlace)}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: muted(context), fontFeatures: _tabular),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 16, color: color ?? muted(context)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: color ?? muted(context), fontWeight: FontWeight.w600)),
          ),
        ],
      );
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: color)),
                ),
              ],
            ),
          ),
        ),
      );
}
