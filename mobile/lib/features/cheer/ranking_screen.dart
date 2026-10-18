import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/insights/insights_engine.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import 'cheer_live.dart';
import 'cheer_widgets.dart';
import 'runner_detail_screen.dart';
import 'runner_view.dart';

const _tabular = [FontFeature.tabularFigures()];

Future<void> openRanking(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RankingScreen()));

enum RankSegment { overall, women, men, category }

/// Live ranking (F16): finishers so far by net (or gun) time, top 50 plus
/// the people you follow, with a provisional / official badge. While the
/// race is live, a strip shows who is leading out on the course.
class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key, this.initial = RankSegment.overall});
  final RankSegment initial;

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  late RankSegment _seg = widget.initial;
  late final RaceSim _sim = context.read<RaceSim>();
  late final CheerLive _live = CheerLive.of(_sim);

  // Ranking lists are cached per snapshot + segment.
  InsightsSnapshot? _cachedSnap;
  RankSegment? _cachedSeg;
  List<int> _list = const [];

  List<int> _ranking(InsightsSnapshot snap) {
    if (identical(snap, _cachedSnap) && _cachedSeg == _seg) return _list;
    _cachedSnap = snap;
    _cachedSeg = _seg;
    _list = switch (_seg) {
      RankSegment.overall => snap.ranking(),
      RankSegment.women => snap.ranking(gender: Gender.f),
      RankSegment.men => snap.ranking(gender: Gender.m),
      RankSegment.category => snap.ranking(categoryId: _sim.you.categoryId),
    };
    return _list;
  }

  @override
  Widget build(BuildContext context) {
    final snap = context.watch<InsightsController>().snapshot;
    final follows = context.watch<FollowsController>();
    final status = context.select<RaceSim, RaceStatus>((s) => s.status);
    final list = _ranking(snap);
    final myCat = _sim.race.categoryById(_sim.you.categoryId).name;
    final mine = {...follows.ids, _sim.youId};
    final top = list.take(50).toList();
    final extra = [
      for (var i = 50; i < list.length; i++)
        if (mine.contains(list[i])) i,
    ];
    double timeOf(int id) {
      final r = snap.result(id);
      return (snap.basis == RankBasis.net ? r.netS : r.gunS) ?? 0;
    }

    final leadTime = list.isEmpty ? 0.0 : timeOf(list.first);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Live ranking')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Pill(
                snap.official ? tr('Official') : tr('Provisional'),
                color: snap.official ? RL.green : RL.amber,
                filled: snap.official,
                icon: snap.official ? Icons.verified_rounded : Icons.timelapse_rounded,
              ),
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            sliver: SliverList.list(
              children: [
                Text(
                  tr('{n} finishers · ranked by {basis} time · as of {time}', {
                    'n': fmtInt(list.length),
                    'basis': snap.basis == RankBasis.net ? tr('net') : tr('gun'),
                    'time': fmtClock(_sim.wallClockAt(snap.asOf < 0 ? 0 : snap.asOf)),
                  }),
                  style: TextStyle(fontSize: 12.5, color: muted(context)),
                ),
                const SizedBox(height: 12),
                if (status == RaceStatus.live) ...[
                  LeadersStrip(live: _live),
                  const SizedBox(height: 12),
                ],
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (seg, label) in [
                        (RankSegment.overall, tr('Overall')),
                        (RankSegment.women, tr('Women')),
                        (RankSegment.men, tr('Men')),
                        (RankSegment.category, tr('My category · {cat}', {'cat': myCat})),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            selected: _seg == seg,
                            showCheckmark: false,
                            label: Text(label),
                            onSelected: (_) => setState(() => _seg = seg),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (list.length >= 3) ...[
                  _Podium(ids: list.take(3).toList(), times: [for (final id in list.take(3)) timeOf(id)]),
                  const SizedBox(height: 12),
                ],
                if (list.isEmpty) _NoFinishers(live: _live),
              ],
            ),
          ),
          if (top.length > 3)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: RLCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (var i = 3; i < top.length; i++)
                        _RankRow(
                          place: i + 1,
                          id: top[i],
                          time: timeOf(top[i]),
                          gap: timeOf(top[i]) - leadTime,
                          highlight: mine.contains(top[i]),
                          you: top[i] == _sim.youId,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (extra.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionLabel(tr('Your people')),
                    RLCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          for (final i in extra)
                            _RankRow(
                              place: i + 1,
                              id: list[i],
                              time: timeOf(list[i]),
                              gap: timeOf(list[i]) - leadTime,
                              highlight: true,
                              you: list[i] == _sim.youId,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SliverToBoxAdapter(child: SizedBox(height: 90 + MediaQuery.of(context).padding.bottom)),
        ],
      ),
    );
  }
}

/// Leading man and woman still out on the course, refreshed ≤ 1 Hz.
class LeadersStrip extends StatelessWidget {
  const LeadersStrip({super.key, required this.live, this.onTap});
  final CheerLive live;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final units = context.select<SettingsController, Units>((s) => s.units);
    return ListenableBuilder(
      listenable: live,
      builder: (context, _) {
        Widget tile(String title, LeaderOnCourse? l, Color color) {
          final p = l == null ? null : sim.participant(l.id);
          return Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(colors: [RL.navy, Color.lerp(RL.navy, color, 0.35)!]),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bolt_rounded, size: 14, color: color),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l == null ? '–' : fmtDistance(l.distanceM, units),
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, fontFeatures: _tabular),
                    ),
                  ),
                  Text(
                    p == null ? tr('Nobody on course') : '${shortName(p)} · #${p.bib}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const LiveDot(color: RL.red, size: 7),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    tr('Leaders on course'),
                    style: TextStyle(fontSize: 11.5, letterSpacing: 1.1, fontWeight: FontWeight.w800, color: muted(context)),
                  ),
                ),
                Text(
                  tr('{n} finished', {'n': fmtInt(live.finished)}),
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: muted(context), fontFeatures: _tabular),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onTap,
              child: Row(
                children: [
                  tile(tr('Men'), live.leaderMen, RL.series[1]),
                  const SizedBox(width: 8),
                  tile(tr('Women'), live.leaderWomen, RL.series[3]),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NoFinishers extends StatelessWidget {
  const _NoFinishers({required this.live});
  final CheerLive live;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    return ListenableBuilder(
      listenable: live,
      builder: (context, _) {
        final l = live.leaderMen;
        final eta = l == null ? null : sim.etaToDistance(l.id, sim.race.distanceM, sim.raceTime);
        return RLCard(
          child: Column(
            children: [
              const Icon(Icons.emoji_events_outlined, size: 40, color: RL.amber),
              const SizedBox(height: 8),
              Text(tr('No finishers yet'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: ink(context))),
              const SizedBox(height: 4),
              Text(
                eta == null
                    ? tr('The ranking fills in live as runners cross the finish.')
                    : tr('First finisher expected around {time}.', {'time': fmtClock(sim.wallClockAt(eta))}),
                textAlign: TextAlign.center,
                style: TextStyle(color: muted(context), fontSize: 13),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.ids, required this.times});
  final List<int> ids;
  final List<double> times;

  static const _medal = [Color(0xFFE8B10C), Color(0xFFA7B1C2), Color(0xFFC9814A)];

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final follows = context.watch<FollowsController>();
    Widget step(int i, double h) {
      final p = sim.participant(ids[i]);
      return Expanded(
        child: GestureDetector(
          onTap: () => openRunnerDetail(context, p.id),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              RunnerAvatar(participant: p, color: runnerColor(sim, follows.ids, p.id), size: i == 0 ? 52 : 44, ring: _medal[i]),
              const SizedBox(height: 6),
              Text(shortName(p), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: ink(context), fontSize: 13)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(fmtDuration(times[i]), style: TextStyle(fontSize: 12, color: muted(context), fontFeatures: _tabular)),
              ),
              const SizedBox(height: 6),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: h),
                duration: Duration(milliseconds: 500 + 120 * i),
                curve: Curves.easeOutBack,
                builder: (_, v, _) => Container(
                  height: v,
                  alignment: Alignment.topCenter,
                  padding: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: _medal[i].withValues(alpha: 0.9),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                  ),
                  child: v < 24 ? null : Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RLCard(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [step(1, 56), const SizedBox(width: 8), step(0, 78), const SizedBox(width: 8), step(2, 42)],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.place, required this.id, required this.time, required this.gap, this.highlight = false, this.you = false});
  final int place;
  final int id;
  final double time;
  final double gap;
  final bool highlight;
  final bool you;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final p = sim.participant(id);
    final cat = sim.race.categoryById(p.categoryId).name;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: highlight ? RL.amber.withValues(alpha: dark ? 0.16 : 0.1) : Colors.transparent,
      child: InkWell(
        onTap: () => openRunnerDetail(context, id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(fmtInt(place), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: highlight ? RL.amber : ink(context), fontFeatures: _tabular)),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      you ? tr('You · {name}', {'name': p.firstName}) : p.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, color: ink(context), fontSize: 14),
                    ),
                    Text(
                      '#${p.bib} · $cat · ${p.nation}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: muted(context)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(fmtDuration(time), style: TextStyle(fontWeight: FontWeight.w800, color: ink(context), fontFeatures: _tabular)),
                  Text(
                    gap <= 0 ? '' : '+${fmtDuration(gap)}',
                    style: TextStyle(fontSize: 11.5, color: muted(context), fontFeatures: _tabular),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
