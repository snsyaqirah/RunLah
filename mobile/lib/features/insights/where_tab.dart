import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../core/widgets/course_map.dart';
import '../../data/app_state.dart';
import '../../data/insights/insights_engine.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import '../three/race3d_mode.dart';
import 'common.dart';
import 'finish_tab.dart' show WaitingCard;

class _Moment {
  const _Moment(this.key, this.chip, this.headline, this.t, this.icon);
  final String key;
  final String chip;
  final String headline;
  final double t;
  final IconData icon;
}

enum _St { notStarted, running, finished, dnf }

class _Where {
  const _Where(this.point, this.d, this.st, this.finishT, this.estimated);
  final LatLng point;
  final double d;
  final _St st;
  final double? finishT;
  final bool estimated;
}

/// Where tab (F23): the runner on the course map at key moments, with
/// followed friends. GPS runners are exact, others estimated (hollow ring).
class WhereTab extends StatefulWidget {
  const WhereTab({super.key, required this.participantId});
  final int participantId;

  @override
  State<WhereTab> createState() => _WhereTabState();
}

class _WhereTabState extends State<WhereTab> with AutomaticKeepAliveClientMixin {
  String? _key;
  bool _friends = true;

  @override
  bool get wantKeepAlive => true;

  int get pid => widget.participantId;

  List<_Moment> _moments(BuildContext context, InsightsSnapshot s, RaceSim sim, List<int> friends) {
    final last = s.race.checkpoints.length - 1;
    final p = sim.participant(pid);
    final isYou = pid == sim.youId;
    final out = <_Moment>[_Moment('gun', tr('Gun'), tr('the gun went off'), 0, Icons.flag_rounded)];
    final mw = s.firstFinishByGender[Gender.m], fw = s.firstFinishByGender[Gender.f];
    if (mw != null) out.add(_Moment('male', tr('Male winner'), tr('the male winner finished'), mw, Icons.emoji_events_rounded));
    if (fw != null) out.add(_Moment('female', tr('Female winner'), tr('the female winner finished'), fw, Icons.emoji_events_rounded));
    final own = crossAt(s, pid, last);
    if (own != null) {
      out.add(_Moment('own', isYou ? tr('You') : firstNameOf(context, p), isYou ? tr('you finished') : tr('{name} finished', {'name': firstNameOf(context, p)}), own, Icons.sports_score_rounded));
    }
    final others = [if (!isYou) sim.youId, ...friends.where((f) => f != pid && f != sim.youId)];
    for (final f in others) {
      final ft = crossAt(s, f, last);
      if (ft == null) continue;
      final fp = sim.participant(f);
      final name = f == sim.youId ? tr('You') : firstNameOf(context, fp);
      out.add(_Moment('f$f', name, f == sim.youId ? tr('you finished') : tr('{name} finished', {'name': name}), ft, Icons.sports_score_rounded));
    }
    if (s.closed) {
      out.add(_Moment('cutoff', tr('Cutoff'), tr('the course closed'), s.race.cutoffS.toDouble(), Icons.lock_clock_rounded));
    } else if (sim.status == RaceStatus.live) {
      out.add(_Moment('now', tr('Now'), tr('right now'), s.asOf, Icons.sensors_rounded));
    }
    out.sort((a, b) => a.t.compareTo(b.t));
    return out;
  }

  _Where _where(InsightsSnapshot s, RaceSim sim, int id, double t) {
    final p = sim.participant(id);
    final race = s.race;
    final fin = crossAt(s, id, race.checkpoints.length - 1);
    final start = crossAt(s, id, 0);
    if (fin != null && fin <= t + 0.5) return _Where(race.finish.location, race.distanceM, _St.finished, fin, false);
    if (start == null || start > t) return _Where(race.start.location, 0, _St.notStarted, fin, !p.hasGps);
    if (sim.stateAt(id, t) == RunnerState.dnf) {
      final last = lastCheckpoint(s, id) ?? 0;
      final d = p.hasGps ? sim.distanceAt(id, t) : race.checkpoints[last].distanceM;
      return _Where(race.route.at(d), d, _St.dnf, null, !p.hasGps);
    }
    if (p.hasGps) return _Where(sim.positionAt(id, t), sim.distanceAt(id, t), _St.running, fin, false);
    final d = s.estimatedDistanceAt(id, t);
    return _Where(race.route.at(d), d, _St.running, fin, true);
  }

  String _mapLabel(BuildContext context, String name, _Where w, Units units) => switch (w.st) {
        _St.finished => '$name · ${tr('Finished')}',
        _St.notStarted => '$name · ${tr('Start')}',
        _St.dnf => '$name · ${tr('Stopped')}',
        _St.running => '$name · ${kmLabel(w.d, units)}',
      };

  String _status(_Where w, double t, Units units, double total) => switch (w.st) {
        _St.finished => (t - w.finishT!).abs() < 1.5 ? tr('Crossing the finish line') : tr('Finished {gap} earlier', {'gap': fmtDuration(t - w.finishT!)}),
        _St.notStarted => tr('Waiting to cross the start'),
        _St.dnf => tr('Stopped at {km}', {'km': kmLabel(w.d, units)}),
        _St.running => tr('{left} to go', {'left': fmtDistance((total - w.d).clamp(0.0, total), units)}),
      };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = context.watch<InsightsController>().snapshot;
    final sim = context.watch<RaceSim>();
    final units = context.watch<SettingsController>().units;
    final follows = context.watch<FollowsController>();
    final phase = phaseOf(sim, s, pid);
    if (phase == Phase.preRace) {
      return TabScroll(storageKey: 'where-$pid', children: [WaitingCard(phase: phase, participantId: pid)]);
    }
    final p = sim.participant(pid);
    final isYou = pid == sim.youId;
    final friendIds = [
      if (!isYou) sim.youId,
      ...follows.ids.where((f) => f != pid && f != sim.youId),
    ].take(5).toList();
    final moments = _moments(context, s, sim, follows.ids);
    var idx = moments.indexWhere((m) => m.key == _key);
    if (idx < 0) {
      idx = moments.indexWhere((m) => m.key == 'male');
      if (idx < 0) idx = moments.length - 1;
    }
    final m = moments[idx];
    final t = m.t;
    final race = s.race;
    final name = isYou ? tr('You') : firstNameOf(context, p);
    final me = _where(s, sim, pid, t);
    final friends = [for (final f in friendIds) (f, _where(s, sim, f, t))];

    final prefix = switch (m.key) {
      'now' => isYou ? tr('Where are you') : tr('Where is {name}', {'name': name}),
      'own' when isYou => tr('Where was everyone when'),
      _ => isYou ? tr('Where were you when') : tr('Where was {name} when', {'name': name}),
    };

    final dots = <MapDot>[
      if (m.key == 'male' || m.key == 'female')
        MapDot(point: race.finish.location, color: RL.navy, size: 24, icon: Icons.emoji_events_rounded),
      if (_friends)
        for (var i = 0; i < friends.length; i++)
          MapDot(
            point: friends[i].$2.point,
            color: friends[i].$1 == sim.youId ? RL.amber : RL.series[(i % (RL.series.length - 1)) + 1],
            estimated: friends[i].$2.estimated,
            size: 16,
            label: friends[i].$1 == sim.youId ? tr('You') : firstNameOf(context, sim.participant(friends[i].$1)),
            onTap: () => openInsights(context, friends[i].$1, tab: 2),
          ),
      MapDot(
        point: me.point,
        color: isYou ? RL.amber : RL.series[1],
        estimated: me.estimated,
        pulse: me.st == _St.running,
        size: 22,
        label: _mapLabel(context, name, me, units),
      ),
    ];

    return TabScroll(
      storageKey: 'where-$pid',
      children: [
        // Headline + moment picker.
        HeroCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(prefix, style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (c, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(a), child: c),
                ),
                child: Text(
                  '${m.headline.toUpperCase()}?',
                  key: ValueKey(m.key),
                  style: const TextStyle(color: RL.amber, fontSize: 25, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: 0.3),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${fmtClockSec(sim.wallClockAt(t))} · ${tr('race time {t}', {'t': fmtDuration(t, forceHours: true)})}',
                style: heroMuted.copyWith(fontFeatures: tabular),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _NavButton(icon: Icons.chevron_left_rounded, tooltip: tr('Previous'), onTap: idx > 0 ? () => setState(() => _key = moments[idx - 1].key) : null),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < moments.length; i++)
                          Flexible(
                            child: GestureDetector(
                              onTap: () => setState(() => _key = moments[i].key),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                width: i == idx ? 22 : 8,
                                height: 8,
                                decoration: BoxDecoration(color: i == idx ? RL.amber : Colors.white30, borderRadius: BorderRadius.circular(99)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _NavButton(icon: Icons.chevron_right_rounded, tooltip: tr('Next'), onTap: idx < moments.length - 1 ? () => setState(() => _key = moments[idx + 1].key) : null),
                ],
              ),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: moments.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => ChoiceChip(
              avatar: Icon(moments[i].icon, size: 16, color: i == idx ? Colors.white : RL.amber),
              label: Text(moments[i].chip),
              selected: i == idx,
              showCheckmark: false,
              selectedColor: RL.navy,
              labelStyle: TextStyle(fontWeight: FontWeight.w700, color: i == idx ? Colors.white : ink(context)),
              onSelected: (_) => setState(() => _key = moments[i].key),
            ),
          ),
        ),
        // Map.
        Stack(
          children: [
            SizedBox(
              height: 340,
              child: CourseMap(
                race: race,
                dots: dots,
                doneUpTo: me.d > 0 ? me.d : null,
                showLandmarks: false,
                padding: const EdgeInsets.fromLTRB(28, 56, 28, 28),
              ),
            ),
            if (friendIds.isNotEmpty)
              Positioned(
                top: 10,
                left: 10,
                child: FilterChip(
                  avatar: Icon(Icons.group_rounded, size: 16, color: _friends ? Colors.white : RL.navy),
                  label: Text(tr('Friends')),
                  selected: _friends,
                  showCheckmark: false,
                  selectedColor: RL.navy,
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(fontWeight: FontWeight.w800, color: _friends ? Colors.white : RL.navy),
                  onSelected: (v) => setState(() => _friends = v),
                ),
              ),
          ],
        ),
        // Caption.
        RLCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RunnerLine(
                color: isYou ? RL.amber : RL.series[1],
                name: isYou ? nameOf(context, p) : firstNameOf(context, p),
                big: me.st == _St.running ? kmLabel(me.d, units) : null,
                status: _status(me, t, units, race.distanceM),
                estimated: me.estimated && me.st == _St.running,
              ),
              if (me.finishT != null && me.finishT! > t + 1.5 && me.st != _St.finished) ...[
                const SizedBox(height: 8),
                Text(
                  isYou
                      ? tr('You crossed the line {gap} later.', {'gap': fmtDuration(me.finishT! - t)})
                      : tr('{name} crossed the line {gap} later.', {'name': name, 'gap': fmtDuration(me.finishT! - t)}),
                  style: TextStyle(fontSize: 13, color: muted(context)),
                ),
              ],
              if (_friends && friends.isNotEmpty) ...[
                const Divider(height: 24),
                for (var i = 0; i < friends.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _RunnerLine(
                    color: friends[i].$1 == sim.youId ? RL.amber : RL.series[(i % (RL.series.length - 1)) + 1],
                    name: friends[i].$1 == sim.youId ? nameOf(context, sim.you) : firstNameOf(context, sim.participant(friends[i].$1)),
                    big: friends[i].$2.st == _St.running ? kmLabel(friends[i].$2.d, units) : null,
                    status: _status(friends[i].$2, t, units, race.distanceM),
                    estimated: friends[i].$2.estimated && friends[i].$2.st == _St.running,
                    small: true,
                  ),
                ],
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  _LegendDot(estimated: false),
                  const SizedBox(width: 6),
                  Flexible(child: Text(tr('Live GPS'), style: TextStyle(fontSize: 11.5, color: muted(context)))),
                  const SizedBox(width: 14),
                  _LegendDot(estimated: true),
                  const SizedBox(width: 6),
                  Flexible(child: Text(tr('Estimated from checkpoints'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: muted(context)))),
                ],
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: () => openRace3D(context, Race3DMode.replay, focusParticipantId: pid, atRaceTime: t),
          icon: const Icon(Icons.threed_rotation_rounded),
          label: Text(tr('Open this moment in 3D')),
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.white.withValues(alpha: onTap == null ? 0.05 : 0.14),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 40, height: 40, child: Icon(icon, color: onTap == null ? Colors.white30 : Colors.white)),
          ),
        ),
      );
}

class _RunnerLine extends StatelessWidget {
  const _RunnerLine({required this.color, required this.name, required this.status, this.big, this.estimated = false, this.small = false});
  final Color color;
  final String name;
  final String status;
  final String? big;
  final bool estimated;
  final bool small;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          _LegendDot(estimated: estimated, color: color, size: small ? 12 : 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: small ? 14 : 16, color: ink(context))),
                Text(status, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: muted(context))),
              ],
            ),
          ),
          if (big != null) ...[
            const SizedBox(width: 8),
            Text(big!, style: TextStyle(fontWeight: FontWeight.w900, fontSize: small ? 16 : 22, color: small ? ink(context) : color, fontFeatures: tabular)),
          ],
        ],
      );
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.estimated, this.color = RL.amber, this.size = 12});
  final bool estimated;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: estimated ? Colors.transparent : color,
          border: Border.all(color: color, width: estimated ? 2.5 : 0),
        ),
      );
}
