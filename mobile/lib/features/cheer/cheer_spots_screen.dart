import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/course_map.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import '../../services/notification_center.dart';
import 'cheer_live.dart';
import 'cheer_widgets.dart';
import 'runner_view.dart';

const _tabular = [FontFeature.tabularFigures()];

Future<void> openCheerSpots(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CheerSpotsScreen()));

IconData spotIcon(SpotKind k) => switch (k) {
      SpotKind.start || SpotKind.finish => Icons.sports_score_rounded,
      SpotKind.checkpoint => Icons.flag_rounded,
      SpotKind.landmark => Icons.location_city_rounded,
      SpotKind.custom => Icons.push_pin_rounded,
    };

/// Pick where to stand. For each runner you follow: a live countdown to
/// the spot, "already passed", a "leave now" alert based on your walking
/// time, and the spots you can still make it to.
class CheerSpotsScreen extends StatefulWidget {
  const CheerSpotsScreen({super.key});

  @override
  State<CheerSpotsScreen> createState() => _CheerSpotsScreenState();
}

class _CheerSpotsScreenState extends State<CheerSpotsScreen> with SingleTickerProviderStateMixin {
  late final RaceSim _sim = context.read<RaceSim>();
  late final CheerLive _live = CheerLive.of(_sim);
  late final SmoothClock _clock = SmoothClock(_sim, this);
  late final List<CheerSpot> _suggested = CheerSpot.suggested(_sim.race);
  final _scroll = ScrollController();
  int? _catchFor;

  @override
  void initState() {
    super.initState();
    _live.addListener(_rebuild);
    // Default spot, set without notifying (we are inside a build).
    _live.initSpot(_suggested.firstWhere((s) => s.name == 'KLCC', orElse: () => _suggested.first));
  }

  @override
  void dispose() {
    _live.removeListener(_rebuild);
    _clock.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onMapTap(LatLng p) {
    final snap = _sim.race.route.snap(p);
    if (snap.offCourse > 400) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('That\'s {m} m from the course. Tap closer to the route.', {'m': fmtInt(snap.offCourse.round())}))),
      );
      return;
    }
    _live.spot = CheerSpot(name: tr('My spot'), distanceM: snap.distance, kind: SpotKind.custom);
  }

  void _select(CheerSpot s) {
    _live.spot = s;
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final follows = context.watch<FollowsController>();
    final units = context.select<SettingsController, Units>((s) => s.units);
    final ids = cheerIds(_sim, follows.ids, showMe: cheerShowMe(context.read<SettingsController>()));
    final spot = _live.spot!;
    final catchFor = ids.contains(_catchFor) ? _catchFor! : (ids.isEmpty ? null : ids.first);

    return Scaffold(
      appBar: AppBar(title: Text(tr('Cheer spots'))),
      body: ListView(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(16, 4, 16, 90 + MediaQuery.of(context).padding.bottom),
        children: [
          // ---- map
          SizedBox(
            height: 250,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CourseMap(
                    race: _sim.race,
                    onTap: _onMapTap,
                    showLandmarks: false,
                    extraLayers: [
                      MarkerLayer(markers: [PlacePin.marker(spot.point(_sim.race), icon: spotIcon(spot.kind), color: RL.navy, label: spot.name)]),
                      RunnersLayer(clock: _clock, ids: ids, labels: false, size: 22),
                    ],
                  ),
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  right: 10,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Pill(tr('Tap the course to drop your own spot'), color: RL.navy, filled: true, icon: Icons.touch_app_rounded),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ---- suggested
          SectionLabel(tr('Suggested spots')),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _suggested.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final s = _suggested[i];
                return ChoiceChip(
                  selected: s.sameAs(spot),
                  avatar: Icon(spotIcon(s.kind), size: 16),
                  showCheckmark: false,
                  label: Text('${s.name} · ${fmtDistance(s.distanceM, units)}'),
                  onSelected: (_) => _select(s),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // ---- chosen spot + walking time
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _SpotCard(key: ValueKey('${spot.name}${spot.distanceM}'), spot: spot, live: _live, units: units),
          ),
          const SizedBox(height: 16),

          // ---- runners coming
          SectionLabel(tr('Who\'s coming')),
          if (ids.isEmpty)
            RLCard(child: Text(tr('Follow a runner to see when they reach your spot.'), style: TextStyle(color: muted(context))))
          else
            for (var i = 0; i < ids.length; i++) ...[
              Appear(index: i, child: _SpotRunnerRow(id: ids[i], spot: spot, live: _live, color: runnerColor(_sim, follows.ids, ids[i]))),
              const SizedBox(height: 10),
            ],
          const SizedBox(height: 8),

          // ---- spots you can still catch
          if (catchFor != null) ...[
            SectionLabel(tr('Spots you can still catch')),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final id in ids)
                  ChoiceChip(
                    selected: id == catchFor,
                    showCheckmark: false,
                    label: Text(id == _sim.youId ? tr('You') : shortName(_sim.participant(id))),
                    onSelected: (_) => setState(() => _catchFor = id),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _CatchList(id: catchFor, spots: _suggested, live: _live, onPick: _select),
          ],
        ],
      ),
    );
  }
}

class _SpotCard extends StatelessWidget {
  const _SpotCard({super.key, required this.spot, required this.live, required this.units});
  final CheerSpot spot;
  final CheerLive live;
  final Units units;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final race = sim.race;
    // Nearest checkpoint for context ("between 5.3K and 7.9K").
    final next = race.checkpoints.firstWhere((c) => c.distanceM >= spot.distanceM - 1, orElse: () => race.finish);
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: RL.navy, borderRadius: BorderRadius.circular(14)),
                child: Icon(spotIcon(spot.kind), color: RL.amber),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(spot.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: ink(context))),
                    Text(
                      tr('{km} into the race · next checkpoint {cp}', {'km': fmtDistance(spot.distanceM, units), 'cp': cpLabel(next)}),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: muted(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.directions_walk_rounded, color: muted(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('My walk to this spot'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, color: ink(context)),
                ),
              ),
              IconButton.outlined(
                tooltip: tr('Less'),
                onPressed: live.walkMinutes <= 1 ? null : () => live.walkMinutes = live.walkMinutes - (live.walkMinutes > 5 ? 5 : 1),
                icon: const Icon(Icons.remove_rounded, size: 18),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  tr('{n} min', {'n': live.walkMinutes}),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: ink(context), fontFeatures: _tabular),
                ),
              ),
              IconButton.outlined(
                tooltip: tr('More'),
                onPressed: live.walkMinutes >= 60 ? null : () => live.walkMinutes = live.walkMinutes + (live.walkMinutes >= 5 ? 5 : 1),
                icon: const Icon(Icons.add_rounded, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpotRunnerRow extends StatelessWidget {
  const _SpotRunnerRow({required this.id, required this.spot, required this.live, required this.color});
  final int id;
  final CheerSpot spot;
  final CheerLive live;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final p = sim.participant(id);
    final name = id == sim.youId ? tr('You') : shortName(p);
    final alarm = live.alarmFor(spot, id);
    return RLCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: ValueListenableBuilder<double>(
        valueListenable: sim.clock,
        builder: (context, t, _) {
          final v = RunnerNow.of(sim, context.read<InsightsController>().snapshot, id, t);
          final passed = v.distanceM >= spot.distanceM && v.state != RunnerState.notStarted;
          final eta = passed ? sim.crossingTime(id, spot.distanceM) : sim.etaToDistance(id, spot.distanceM, t);
          final walk = live.walkMinutes * 60;
          final canAlarm = !passed && eta != null && v.state != RunnerState.dnf;

          late final String headline;
          late final String detail;
          Widget? badge;
          if (v.state == RunnerState.dnf && !passed) {
            headline = tr('{name} won\'t reach {spot}', {'name': name, 'spot': spot.name});
            detail = tr('Stopped before this spot');
          } else if (passed) {
            final ago = eta == null ? 0.0 : (t - eta).clamp(0.0, double.infinity);
            headline = tr('{name} passed {spot}', {'name': name, 'spot': spot.name});
            detail = eta == null ? '' : tr('{ago} ago · at {time}', {'ago': _ago(ago), 'time': fmtClock(sim.wallClockAt(eta))});
            badge = const Icon(Icons.check_circle_rounded, color: RL.green);
          } else if (eta == null) {
            headline = name;
            detail = '–';
          } else {
            final left = eta - t;
            final leaveIn = left - walk;
            headline = sim.status == RaceStatus.preRace
                ? tr('{name} expected at {spot}', {'name': name, 'spot': spot.name})
                : tr('{name} reaches {spot} in', {'name': name, 'spot': spot.name});
            detail = leaveIn <= 0
                ? tr('Arrives {time}', {'time': fmtClock(sim.wallClockAt(eta))})
                : tr('Arrives {time} · leave by {leave}', {'time': fmtClock(sim.wallClockAt(eta)), 'leave': fmtClock(sim.wallClockAt(eta - walk))});
            badge = Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sim.status == RaceStatus.preRace ? fmtClock(sim.wallClockAt(eta)) : fmtDuration(left),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: ink(context), fontFeatures: _tabular),
                ),
                if (leaveIn <= 0 && sim.status != RaceStatus.preRace) Pill(tr('Leave now!'), color: RL.red, filled: true, icon: Icons.directions_run_rounded),
              ],
            );
          }

          return Row(
            children: [
              RunnerAvatar(participant: p, color: color, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(headline, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: ink(context), fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: muted(context))),
                  ],
                ),
              ),
              if (badge != null) ...[const SizedBox(width: 8), Flexible(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: badge))],
              IconButton(
                tooltip: tr('Leave-now alert'),
                onPressed: !canAlarm ? null : () => live.setAlarm(spot, id, context.read<NotificationCenter>(), alarm == null),
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                  child: Icon(
                    alarm == null ? Icons.notifications_none_rounded : (alarm.fired ? Icons.notifications_rounded : Icons.notifications_active_rounded),
                    key: ValueKey(alarm == null ? 0 : (alarm.fired ? 1 : 2)),
                    color: alarm == null ? muted(context) : RL.amber,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _ago(double s) => s < 60 ? tr('{n} s', {'n': s.round()}) : (s < 3600 ? tr('{n} min', {'n': (s / 60).round()}) : fmtDuration(s));
}

class _CatchList extends StatelessWidget {
  const _CatchList({required this.id, required this.spots, required this.live, required this.onPick});
  final int id;
  final List<CheerSpot> spots;
  final CheerLive live;
  final void Function(CheerSpot) onPick;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final units = context.select<SettingsController, Units>((s) => s.units);
    return ValueListenableBuilder<double>(
      valueListenable: sim.clock,
      builder: (context, t, _) {
        final v = RunnerNow.of(sim, context.read<InsightsController>().snapshot, id, t);
        if (v.state == RunnerState.finished || v.state == RunnerState.dnf) {
          return RLCard(
            child: Text(
              v.state == RunnerState.finished ? tr('Already finished. Head to the meeting point!') : tr('Not on course any more.'),
              style: TextStyle(color: muted(context)),
            ),
          );
        }
        final walk = live.walkMinutes * 60;
        final ahead = [for (final s in spots) if (s.distanceM > v.distanceM + 50) s];
        return RLCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              for (final s in ahead)
                () {
                  final eta = sim.etaToDistance(id, s.distanceM, t);
                  if (eta == null) return const SizedBox.shrink();
                  final slack = eta - walk - t;
                  final ok = slack >= 0;
                  final c = ok ? (slack < 300 ? RL.amber : RL.green) : RL.slate;
                  return ListTile(
                    dense: true,
                    onTap: () => onPick(s),
                    leading: Icon(spotIcon(s.kind), color: c),
                    title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: ink(context))),
                    subtitle: Text(
                      tr('{km} · passes {time}', {'km': fmtDistance(s.distanceM, units), 'time': fmtClock(sim.wallClockAt(eta))}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Pill(
                      ok ? (slack < 300 ? tr('Go soon') : tr('Catchable')) : tr('Too far'),
                      color: c,
                    ),
                  );
                }(),
              if (ahead.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(tr('No more spots ahead. Meet them at the finish!'), style: TextStyle(color: muted(context))),
                ),
            ],
          ),
        );
      },
    );
  }
}
