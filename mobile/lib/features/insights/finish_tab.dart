import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/insights/insights_engine.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import 'certificate_screen.dart';
import 'common.dart';
import 'place_line.dart';

/// Finish tab (F18 + F24): time, places, gender compare, ghost runners.
class FinishTab extends StatefulWidget {
  const FinishTab({super.key, required this.participantId});
  final int participantId;

  @override
  State<FinishTab> createState() => _FinishTabState();
}

class _FinishTabState extends State<FinishTab> with AutomaticKeepAliveClientMixin {
  bool _nation = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = context.watch<InsightsController>().snapshot;
    final sim = context.watch<RaceSim>();
    final units = context.watch<SettingsController>().units;
    final pid = widget.participantId;
    final p = sim.participant(pid);
    final phase = phaseOf(sim, s, pid);

    final List<Widget> children;
    switch (phase) {
      case Phase.finished:
        final r = s.result(pid);
        children = [
          TimeHero(result: r, basis: s.basis, units: units),
          _placesCard(context, p, r),
          ?_genderCompare(context, s, p, r),
          _GhostsCard(snapshot: s, participantId: pid),
          _Actions(participantId: pid, official: s.official),
        ];
      case Phase.onCourse:
        children = [
          LiveHero(snapshot: s, participantId: pid),
          ?_checkpointPlace(context, s, p),
          SplitsSoFar(snapshot: s, participantId: pid),
          _Actions(participantId: pid, official: false, live: true),
        ];
      case Phase.dnf:
        children = [DnfCard(snapshot: s, participantId: pid)];
      case Phase.preRace || Phase.notStarted || Phase.dns:
        children = [WaitingCard(phase: phase, participantId: pid)];
    }
    return TabScroll(storageKey: 'finish-$pid', children: children);
  }

  Widget _placesCard(BuildContext context, Participant p, ResultRow r) {
    final race = context.read<RaceSim>().race;
    return RLCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(tr('Where you placed')),
          PlaceLine(label: tr('Entire field'), info: r.overall!, seed: 1),
          const Divider(height: 30),
          PlaceLine(label: p.gender == Gender.f ? tr('Women') : tr('Men'), info: r.gender!, seed: 2),
          const Divider(height: 30),
          PlaceLine(
            key: ValueKey(_nation),
            label: _nation ? nationName(p.nation) : categoryName(race, p),
            info: _nation ? r.nation! : r.category!,
            seed: _nation ? 4 : 3,
            trailing: SegToggle<bool>(
              value: _nation,
              options: [(false, tr('Division')), (true, tr('Nation'))],
              onChanged: (v) => setState(() => _nation = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _genderCompare(BuildContext context, InsightsSnapshot s, Participant p, ResultRow r) {
    final pct = r.otherGenderAheadPct;
    if (pct == null || pct.isNaN) return null;
    final other = p.gender == Gender.m ? Gender.f : Gender.m;
    final total = s.stats['gender:${other.code}']?.finishers ?? 0;
    final count = (pct / 100 * total).round();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = other == Gender.f ? RL.female : (dark ? const Color(0xFF6FA3D8) : RL.male);
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(tr('Gender compare')),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CountUp(
                value: pct,
                format: fmtPct,
                style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: color, height: 1, fontFeatures: tabular),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  other == Gender.f ? tr('of female finishers crossed the line after you') : tr('of male finishers crossed the line after you'),
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: ink(context), height: 1.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SplitBar(fraction: pct / 100, color: color),
          const SizedBox(height: 10),
          Text(
            other == Gender.f
                ? tr('Ahead of {pct} of female finishers', {'pct': fmtPct(pct)})
                : tr('Ahead of {pct} of male finishers', {'pct': fmtPct(pct)}),
            style: TextStyle(fontWeight: FontWeight.w800, color: ink(context)),
          ),
          const SizedBox(height: 2),
          Text(
            other == Gender.f
                ? tr('{n} of {total} women finished behind', {'n': fmtInt(count), 'total': fmtInt(total)})
                : tr('{n} of {total} men finished behind', {'n': fmtInt(count), 'total': fmtInt(total)}),
            style: TextStyle(fontSize: 12.5, color: muted(context)),
          ),
        ],
      ),
    );
  }

  Widget? _checkpointPlace(BuildContext context, InsightsSnapshot s, Participant p) {
    final last = lastCheckpoint(s, p.id);
    if (last == null) return null;
    final place = s.placesByCheckpoint(p.id)[last];
    if (place == null) return null;
    final cp = s.race.checkpoints[last];
    final crossed = s.table.times[last].where((t) => !t.isNaN && t <= s.asOf).length;
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(tr('Provisional place')),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                CountUp(
                  value: place.toDouble(),
                  format: (v) => ordinal(v.round()),
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: ink(context), fontFeatures: tabular),
                ),
                const SizedBox(width: 8),
                Text(tr('of {n} so far', {'n': fmtInt(crossed)}), style: TextStyle(color: muted(context), fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            last == 0 ? tr('Crossing the start mat') : tr('Through {cp} ({km})', {'cp': cp.name, 'km': cp.shortLabel}),
            style: TextStyle(fontWeight: FontWeight.w700, color: ink(context)),
          ),
          const SizedBox(height: 6),
          Text(
            tr('Clock-order place at the last checkpoint. Final places appear at the finish.'),
            style: TextStyle(fontSize: 12.5, color: muted(context)),
          ),
        ],
      ),
    );
  }
}

/// Big net/gun time with the Net | Gun toggle.
class TimeHero extends StatelessWidget {
  const TimeHero({super.key, required this.result, required this.basis, required this.units});
  final ResultRow result;
  final RankBasis basis;
  final Units units;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final net = basis == RankBasis.net;
    final time = (net ? r.netS : r.gunS) ?? 0;
    return HeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text((net ? tr('Net time') : tr('Gun time')).toUpperCase(), style: heroLabel)),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SegToggle<RankBasis>(
                    value: basis,
                    onDark: true,
                    options: [(RankBasis.net, tr('Net')), (RankBasis.gun, tr('Gun'))],
                    onChanged: (b) => context.read<InsightsController>().basis = b,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: CountUp(
              value: time,
              format: fmtDuration,
              style: const TextStyle(fontSize: 62, fontWeight: FontWeight.w900, color: Colors.white, height: 1.0, letterSpacing: -1, fontFeatures: tabular),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.flag_rounded, size: 15, color: RL.amber),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tr('Crossed the start {delay} after the gun', {'delay': fmtDuration(r.startDelayS)}),
                  style: heroMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: HeroStat(value: fmtPace(r.avgPaceSPerKm, units), label: tr('avg pace'))),
              Expanded(child: HeroStat(value: fmtSpeed(r.avgKph ?? 0, units), label: tr('avg speed'))),
              Expanded(child: HeroStat(value: fmtDuration(net ? r.gunS : r.netS), label: net ? tr('gun time') : tr('net time'))),
            ],
          ),
        ],
      ),
    );
  }
}

/// Animated bar filled to [fraction] with a "you" marker at the end.
class SplitBar extends StatelessWidget {
  const SplitBar({super.key, required this.fraction, required this.color});
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 1400),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          return SizedBox(
            height: 22,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 12,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
                ),
                Container(
                  height: 12,
                  width: w * v,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [color.withValues(alpha: 0.55), color]),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Positioned(
                  left: (w * v - 11).clamp(0.0, w - 22),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: RL.amber,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 5)],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GhostsCard extends StatelessWidget {
  const _GhostsCard({required this.snapshot, required this.participantId});
  final InsightsSnapshot snapshot;
  final int participantId;

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final sim = context.read<RaceSim>();
    final g = s.ghosts(participantId);
    final isYou = participantId == sim.youId;
    double? timeOf(int id) {
      final r = s.result(id);
      return s.basis == RankBasis.net ? r.netS : r.gunS;
    }

    final mine = timeOf(participantId) ?? 0;
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(tr('Ghost runners')),
          Text(
            isYou ? tr('The finishers just ahead of and just behind you.') : tr('The finishers just ahead and just behind.'),
            style: TextStyle(fontSize: 13, color: muted(context)),
          ),
          const SizedBox(height: 12),
          _GhostRow(id: g.ahead, ahead: true, gap: g.ahead == null ? null : mine - (timeOf(g.ahead!) ?? mine)),
          const SizedBox(height: 10),
          _GhostRow(id: g.behind, ahead: false, gap: g.behind == null ? null : (timeOf(g.behind!) ?? mine) - mine),
        ],
      ),
    );
  }
}

class _GhostRow extends StatelessWidget {
  const _GhostRow({required this.id, required this.ahead, required this.gap});
  final int? id;
  final bool ahead;
  final double? gap;

  @override
  Widget build(BuildContext context) {
    final color = ahead ? RL.green : RL.teal;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? Colors.white.withValues(alpha: 0.04) : RL.bg;
    if (id == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Icon(ahead ? Icons.emoji_events_rounded : Icons.flag_circle_rounded, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                ahead ? tr('Nobody ahead — first across the line!') : tr('Nobody behind — last finisher, still a finisher!'),
                style: TextStyle(fontWeight: FontWeight.w700, color: ink(context)),
              ),
            ),
          ],
        ),
      );
    }
    final sim = context.read<RaceSim>();
    final follows = context.watch<FollowsController>();
    final p = sim.participant(id!);
    final isYou = p.id == sim.youId;
    final following = follows.isFollowing(p.id);
    final secs = (gap ?? 0).abs();
    final gapText = secs < 0.5 ? tr('same time') : (ahead ? tr('{gap} ahead', {'gap': fmtGap(secs)}) : tr('{gap} behind', {'gap': fmtGap(secs)}));
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openInsights(context, p.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
          child: Row(
            children: [
              RunnerAvatar(name: nameOf(context, p), color: color, size: 40, icon: ahead ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isYou ? '${nameOf(context, p)} (${tr('You')})' : nameOf(context, p),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, color: ink(context)),
                    ),
                    Text(
                      '#${p.bib} · ${categoryName(sim.race, p)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted(context)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(gapText, style: TextStyle(fontWeight: FontWeight.w900, color: color, fontFeatures: tabular)),
                ),
              ),
              if (!isYou)
                IconButton(
                  tooltip: following ? tr('Unfollow') : tr('Follow'),
                  onPressed: () {
                    if (following) {
                      follows.unfollow(p.id);
                    } else {
                      follows.follow(p.id);
                      showSnack(context, tr('Following {name} — you\'ll get their checkpoint alerts', {'name': nameOf(context, p)}));
                    }
                  },
                  icon: Icon(following ? Icons.how_to_reg_rounded : Icons.person_add_alt_1_rounded, color: following ? RL.amber : muted(context)),
                )
              else
                const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.participantId, required this.official, this.live = false});
  final int participantId;
  final bool official;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => openShareCard(context, participantId),
                icon: const Icon(Icons.ios_share_rounded),
                label: Text(tr('Share card'), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            if (official) ...[
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CertificateScreen(participantId: participantId))),
                  icon: const Icon(Icons.workspace_premium_rounded, color: RL.amber),
                  label: Text(tr('E-certificate'), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ],
        ),
        if (!official && !live) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.lock_clock_rounded, size: 16, color: muted(context)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tr('The e-certificate unlocks when the organizer publishes official results.'),
                  style: TextStyle(fontSize: 12.5, color: muted(context)),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Live card for a runner on course: distance, progress, elapsed, ETA.
class LiveHero extends StatelessWidget {
  const LiveHero({super.key, required this.snapshot, required this.participantId});
  final InsightsSnapshot snapshot;
  final int participantId;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final units = context.watch<SettingsController>().units;
    final p = sim.participant(participantId);
    final race = sim.race;
    return HeroCard(
      child: ValueListenableBuilder<double>(
        valueListenable: sim.clock,
        builder: (context, t, _) {
          final d = p.hasGps ? sim.distanceAt(p.id, t) : snapshot.estimatedDistanceAt(p.id, t);
          final frac = (d / race.distanceM).clamp(0.0, 1.0);
          final proj = sim.projectedFinish(p.id, t);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const LiveDot(),
                  const SizedBox(width: 6),
                  Text(tr('On course').toUpperCase(), style: heroLabel.copyWith(color: const Color(0xFF34D399))),
                  const Spacer(),
                  Text(tr('Provisional'), style: heroMuted),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  fmtDistance(d, units, decimals: 2),
                  style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: Colors.white, height: 1, fontFeatures: tabular),
                ),
              ),
              const SizedBox(height: 4),
              Text(tr('{left} to go', {'left': fmtDistance(race.distanceM - d, units)}), style: heroMuted),
              const SizedBox(height: 14),
              CourseProgress(fraction: frac),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: HeroStat(value: fmtDuration(sim.elapsedAt(p.id, t)), label: tr('elapsed'))),
                  Expanded(child: HeroStat(value: fmtDuration(proj), label: tr('projected finish'))),
                  Expanded(child: HeroStat(value: fmtPace(sim.paceAt(p.id, t), units), label: tr('current pace'))),
                ],
              ),
              if (!p.hasGps) ...[
                const SizedBox(height: 10),
                Text(tr('No live GPS: position estimated between checkpoint passes.'), style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Pulsing green dot for LIVE labels.
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, this.color = const Color(0xFF34D399)});
  final Color color;
  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 14,
        height: 14,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 6 + 8 * _c.value,
                height: 6 + 8 * _c.value,
                decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.4 * (1 - _c.value))),
              ),
              Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
            ],
          ),
        ),
      );
}

/// Start → finish progress line with checkpoint ticks and a runner dot.
class CourseProgress extends StatelessWidget {
  const CourseProgress({super.key, required this.fraction});
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final cps = context.read<RaceSim>().race.checkpoints;
    final total = cps.last.distanceM;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return SizedBox(
          height: 20,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              Container(height: 6, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99))),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 6,
                width: w * fraction,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0x55E8930C), RL.amber]),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              for (final cp in cps.skip(1).take(cps.length - 2))
                Positioned(
                  left: w * cp.distanceM / total - 1,
                  child: Container(width: 2, height: 10, color: Colors.white.withValues(alpha: 0.3)),
                ),
              Positioned(
                left: (w * fraction - 10).clamp(0.0, w - 20),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(color: RL.amber, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Checkpoint splits a runner has completed so far.
class SplitsSoFar extends StatelessWidget {
  const SplitsSoFar({super.key, required this.snapshot, required this.participantId});
  final InsightsSnapshot snapshot;
  final int participantId;

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final units = context.watch<SettingsController>().units;
    final last = lastCheckpoint(s, participantId) ?? 0;
    final cps = s.race.checkpoints;
    final start = crossAt(s, participantId, 0);
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(tr('Splits so far')),
          if (last == 0 || start == null)
            Text(
              tr('No splits yet. First checkpoint at {km}.', {'km': fmtDistance(cps[1].distanceM, units)}),
              style: TextStyle(color: muted(context)),
            )
          else
            for (var k = 1; k <= last; k++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: RL.amber.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(cps[k].shortLabel, style: const TextStyle(fontWeight: FontWeight.w900, color: RL.amber, fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(cps[k].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: ink(context))),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      fmtDuration(crossAt(s, participantId, k)! - start),
                      style: TextStyle(fontWeight: FontWeight.w900, color: ink(context), fontFeatures: tabular),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 74,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          fmtPace((crossAt(s, participantId, k)! - crossAt(s, participantId, k - 1)!) / ((cps[k].distanceM - cps[k - 1].distanceM) / 1000), units),
                          style: TextStyle(fontSize: 12.5, color: muted(context), fontFeatures: tabular),
                        ),
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

/// Respectful state for a runner who stopped.
class DnfCard extends StatelessWidget {
  const DnfCard({super.key, required this.snapshot, required this.participantId});
  final InsightsSnapshot snapshot;
  final int participantId;

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final sim = context.read<RaceSim>();
    final units = context.watch<SettingsController>().units;
    final p = sim.participant(participantId);
    final last = lastCheckpoint(s, participantId);
    final d = p.hasGps ? sim.distanceAt(p.id, s.asOf) : (last == null ? 0.0 : s.race.checkpoints[last].distanceM);
    final cp = last == null ? null : s.race.checkpoints[last];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StateCard(
          icon: Icons.favorite_rounded,
          color: RL.teal,
          title: s.closed ? tr('Did not finish') : tr('Stopped racing'),
          message: tr(
            '{name} covered {dist} of the {total} course. Every start line takes courage. Rest up, recover well and come back stronger.',
            {'name': firstNameOf(context, p), 'dist': fmtDistance(d, units), 'total': fmtDistance(s.race.distanceM, units)},
          ),
          children: [
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: (d / s.race.distanceM).clamp(0.0, 1.0),
                minHeight: 8,
                color: RL.teal,
                backgroundColor: RL.teal.withValues(alpha: 0.14),
              ),
            ),
            if (cp != null && last! > 0) ...[
              const SizedBox(height: 12),
              Text(
                tr('Last seen at {cp} ({km}), {time} into the race.', {
                  'cp': cp.name,
                  'km': cp.shortLabel,
                  'time': fmtDuration(crossAt(s, p.id, last)! - (crossAt(s, p.id, 0) ?? 0)),
                }),
                style: TextStyle(fontSize: 13, color: ink(context), fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
        if (last != null && last > 0) ...[
          const SizedBox(height: RL.gap + 2),
          SplitsSoFar(snapshot: s, participantId: participantId),
        ],
      ],
    );
  }
}

/// Before the gun / before the start mat / no start recorded.
class WaitingCard extends StatelessWidget {
  const WaitingCard({super.key, required this.phase, required this.participantId});
  final Phase phase;
  final int participantId;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final p = sim.participant(participantId);
    final name = firstNameOf(context, p);
    return switch (phase) {
      Phase.dns => StateCard(
          icon: Icons.event_busy_rounded,
          color: RL.slate,
          title: tr('Did not start'),
          message: tr('No start pass was recorded for {name}, so there are no insights for this race.', {'name': name}),
        ),
      Phase.notStarted => StateCard(
          icon: Icons.hourglass_top_rounded,
          title: tr('Not across the start yet'),
          message: tr('{name} hasn\'t crossed the start mat. Insights go live as soon as they do.', {'name': name}),
        ),
      _ => StateCard(
          icon: Icons.timer_outlined,
          title: tr('Waiting for the gun'),
          message: tr('Race Insights go live when the gun fires at {time}. Places, speeds and overtakes then update as runners cross each checkpoint.', {
            'time': fmtClock(sim.race.scheduledStart),
          }),
        ),
    };
  }
}
