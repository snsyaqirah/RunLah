import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/insights/insights_engine.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import 'common.dart';
import 'finish_tab.dart' show LiveHero;

/// Results tab (F16): your result, search, filters and the paged ranking.
class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  static const pageSize = 50;
  static const rowH = 66.0;

  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _listMarker = GlobalKey();
  String _q = '';

  /// `overall` | `gender:F` | `gender:M` | `category:ID`
  String _filter = 'overall';
  int _page = 0;

  InsightsSnapshot? _memoSnap;
  String? _memoFilter;
  List<int> _ids = const [];

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<int> _ranking(InsightsSnapshot s) {
    if (identical(s, _memoSnap) && _memoFilter == _filter) return _ids;
    _memoSnap = s;
    _memoFilter = _filter;
    final parts = _filter.split(':');
    _ids = switch (parts.first) {
      'gender' => s.ranking(gender: parts[1] == 'F' ? Gender.f : Gender.m),
      'category' => s.ranking(categoryId: int.parse(parts[1])),
      _ => s.ranking(),
    };
    return _ids;
  }

  int _placeOf(InsightsSnapshot s, int i) => switch (_filter.split(':').first) {
        'gender' => s.placeGender[i],
        'category' => s.placeCategory[i],
        _ => s.placeOverall[i],
      };

  void _jumpTo(int pos) {
    setState(() => _page = pos ~/ pageSize);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final ro = _listMarker.currentContext?.findRenderObject();
      var base = 0.0;
      try {
        if (ro is RenderSliver) base = ro.constraints.precedingScrollExtent;
      } catch (_) {}
      final target = base + (pos % pageSize) * rowH - 180;
      _scroll.animateTo(target.clamp(0.0, _scroll.position.maxScrollExtent), duration: const Duration(milliseconds: 650), curve: Curves.easeOutCubic);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<InsightsController>().snapshot;
    final sim = context.watch<RaceSim>();
    final units = context.watch<SettingsController>().units;
    final follows = context.watch<FollowsController>();
    final race = sim.race;
    final ids = _ranking(s);
    final pages = math.max(1, (ids.length / pageSize).ceil());
    if (_page >= pages) _page = pages - 1;
    final from = _page * pageSize;
    final pageIds = ids.isEmpty ? const <int>[] : ids.sublist(from, math.min(ids.length, from + pageSize));
    final searching = _q.trim().isNotEmpty;
    final found = searching ? sim.search(_q, limit: 30) : const <Participant>[];
    final youPos = ids.indexOf(sim.youId);
    final dark = Theme.of(context).brightness == Brightness.dark;

    final filters = <(String, String)>[
      ('overall', tr('Overall')),
      ('gender:F', tr('Women')),
      ('gender:M', tr('Men')),
      for (final c in race.categories) ('category:${c.id}', c.name),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Results')),
        actions: [
          if (youPos >= 0 && !searching)
            IconButton(tooltip: tr('Jump to you'), onPressed: () => _jumpTo(youPos), icon: const Icon(Icons.my_location_rounded)),
          const Padding(padding: EdgeInsets.only(right: 14), child: Center(child: ResultsStatusPill())),
        ],
      ),
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _RaceStrip(snapshot: s),
                const SizedBox(height: 12),
                const Entrance(index: 0, child: _YourResult()),
                const SizedBox(height: 18),
                TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: tr('Search name or bib'),
                    suffixIcon: searching
                        ? IconButton(
                            tooltip: tr('Clear'),
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(() {
                              _search.clear();
                              _q = '';
                            }),
                          )
                        : null,
                  ),
                  onChanged: (v) => setState(() => _q = v),
                ),
                const SizedBox(height: 12),
                if (!searching) ...[
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: filters.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => ChoiceChip(
                        label: Text(filters[i].$2),
                        selected: filters[i].$1 == _filter,
                        showCheckmark: false,
                        selectedColor: RL.navy,
                        labelStyle: TextStyle(fontWeight: FontWeight.w700, color: filters[i].$1 == _filter ? Colors.white : ink(context)),
                        onSelected: (_) => setState(() {
                          _filter = filters[i].$1;
                          _page = 0;
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          sim.status == RaceStatus.preRace
                              ? tr('Start list')
                              : (s.official ? tr('{n} finishers', {'n': fmtInt(ids.length)}) : tr('{n} finishers so far', {'n': fmtInt(ids.length)})),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w800, color: ink(context)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: SegToggle<RankBasis>(
                            value: s.basis,
                            options: [(RankBasis.net, tr('Net')), (RankBasis.gun, tr('Gun'))],
                            onChanged: (b) => context.read<InsightsController>().basis = b,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ]),
            ),
          ),
          if (searching)
            found.isEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(child: Text(tr('No runners match “{q}”', {'q': _q.trim()}), style: TextStyle(color: muted(context)))),
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _SearchRow(participant: found[i], snapshot: s, units: units, followed: follows.isFollowing(found[i].id)),
                        childCount: found.length,
                      ),
                    ),
                  )
          else if (ids.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: _EmptyList(preRace: sim.status == RaceStatus.preRace, runners: sim.participants.length),
              ),
            )
          else ...[
            SliverToBoxAdapter(key: _listMarker, child: const SizedBox.shrink()),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverFixedExtentList(
                itemExtent: rowH,
                delegate: SliverChildBuilderDelegate(
                  (context, j) {
                    final id = pageIds[j];
                    final i = s.table.indexOf[id]!;
                    return _RankRow(
                      place: _placeOf(s, i),
                      participant: sim.participant(id),
                      timeS: s.basisTime(i),
                      isYou: id == sim.youId,
                      followed: follows.isFollowing(id),
                      category: categoryName(race, sim.participant(id)),
                      dark: dark,
                    );
                  },
                  childCount: pageIds.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton.outlined(
                          tooltip: tr('Previous page'),
                          onPressed: _page > 0 ? () => setState(() => _page--) : null,
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                tr('{from}–{to} of {n}', {'from': fmtInt(from + 1), 'to': fmtInt(from + pageIds.length), 'n': fmtInt(ids.length)}),
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.w800, color: ink(context), fontFeatures: tabular),
                              ),
                              Text(tr('Page {p} of {n}', {'p': _page + 1, 'n': pages}), style: TextStyle(fontSize: 12, color: muted(context))),
                            ],
                          ),
                        ),
                        IconButton.outlined(
                          tooltip: tr('Next page'),
                          onPressed: _page < pages - 1 ? () => setState(() => _page++) : null,
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                    ),
                    if (youPos >= 0)
                      TextButton.icon(
                        onPressed: () => _jumpTo(youPos),
                        icon: const Icon(Icons.my_location_rounded, size: 18),
                        label: Text(tr('Jump to you · {place}', {'place': ordinal(_placeOf(s, s.table.indexOf[sim.youId]!))})),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );
  }
}

class _RaceStrip extends StatelessWidget {
  const _RaceStrip({required this.snapshot});
  final InsightsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final units = context.read<SettingsController>().units;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: RL.amber.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.emoji_events_rounded, color: RL.amber),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(sim.event.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: ink(context))),
              Text(
                '${tr(sim.race.name)} · ${fmtDistance(sim.race.distanceM, units)} · ${fmtDate(sim.event.date)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: muted(context)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Hero card at the top of Results: your own result in its current state.
class _YourResult extends StatelessWidget {
  const _YourResult();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<InsightsController>().snapshot;
    final sim = context.watch<RaceSim>();
    context.watch<SettingsController>();
    final you = sim.you;
    final phase = phaseOf(sim, s, you.id);
    switch (phase) {
      case Phase.preRace:
        return HeroCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Your result').toUpperCase(), style: heroLabel),
              const SizedBox(height: 10),
              Text(tr('Results appear here as runners finish'), style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900, height: 1.15)),
              const SizedBox(height: 8),
              Text(
                tr('Once the gun fires, provisional results update live as runners cross the line. Tap the race clock at the bottom right to fire the gun or jump to any moment of the race.'),
                style: heroMuted.copyWith(height: 1.4, fontSize: 13.5),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: HeroStat(value: fmtClock(sim.race.scheduledStart), label: tr('gun time'))),
                  Expanded(child: HeroStat(value: fmtInt(sim.participants.length), label: tr('runners'))),
                  Expanded(child: HeroStat(value: '#${you.bib}', label: tr('your bib'))),
                ],
              ),
            ],
          ),
        );
      case Phase.finished:
        final r = s.result(you.id);
        final time = s.basis == RankBasis.net ? r.netS : r.gunS;
        Widget chip(String text) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(999)),
              child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            );
        return HeroCard(
          onTap: () => openInsights(context, you.id),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(tr('Your result').toUpperCase(), style: heroLabel)),
                  Text('${nameOf(context, you)} · #${you.bib}', style: heroMuted),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: CountUp(
                        value: time ?? 0,
                        format: fmtDuration,
                        style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900, height: 1, letterSpacing: -1, fontFeatures: tabular),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      CountUp(
                        value: r.overall!.place.toDouble(),
                        from: r.overall!.of.toDouble(),
                        format: (v) => ordinal(v.round()),
                        style: const TextStyle(color: RL.amber, fontSize: 26, fontWeight: FontWeight.w900, height: 1, fontFeatures: tabular),
                      ),
                      Text(tr('of {n}', {'n': fmtInt(r.overall!.of)}), style: heroMuted),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(s.basis == RankBasis.net ? tr('net time') : tr('gun time'), style: heroMuted),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  chip(r.overall!.place == 1 ? tr('Winner') : tr('Top {pct}', {'pct': fmtPct(r.overall!.topPct)})),
                  chip('${ordinal(r.gender!.place)} ${you.gender == Gender.f ? tr('Women') : tr('Men')}'),
                  chip('${ordinal(r.category!.place)} ${categoryName(sim.race, you)}'),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: Text(tr('See your Race Insights'), style: const TextStyle(color: RL.amber, fontWeight: FontWeight.w900))),
                  const Icon(Icons.arrow_forward_rounded, color: RL.amber),
                ],
              ),
            ],
          ),
        );
      case Phase.onCourse:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(onTap: () => openInsights(context, you.id), child: LiveHero(snapshot: s, participantId: you.id)),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => openInsights(context, you.id),
                icon: const Icon(Icons.insights_rounded, size: 18),
                label: Text(tr('Live Race Insights')),
              ),
            ),
          ],
        );
      case Phase.notStarted:
        return StateCard(
          icon: Icons.hourglass_top_rounded,
          title: tr('Waiting at the start'),
          message: tr('The gun has gone. Your result appears here once you cross the start mat and the finish line.'),
        );
      case Phase.dnf:
        return StateCard(
          icon: Icons.favorite_rounded,
          color: RL.teal,
          title: tr('Not this time'),
          message: tr('You didn\'t finish this one. Every start line takes courage. Rest up, recover well and come back stronger.'),
        );
      case Phase.dns:
        return StateCard(
          icon: Icons.event_busy_rounded,
          color: RL.slate,
          title: tr('Did not start'),
          message: tr('No start pass was recorded for you in this race.'),
        );
    }
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.preRace, required this.runners});
  final bool preRace;
  final int runners;

  @override
  Widget build(BuildContext context) => RLCard(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(preRace ? Icons.people_alt_rounded : Icons.directions_run_rounded, color: RL.amber, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                preRace
                    ? tr('{n} runners on the start list. Search by name or bib to open anyone\'s Race Insights.', {'n': fmtInt(runners)})
                    : tr('No finishers yet. The leaders are still out on the course.'),
                style: TextStyle(color: ink(context), height: 1.35),
              ),
            ),
          ],
        ),
      );
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.place,
    required this.participant,
    required this.timeS,
    required this.isYou,
    required this.followed,
    required this.category,
    required this.dark,
  });
  final int place;
  final Participant participant;
  final double timeS;
  final bool isYou;
  final bool followed;
  final String category;
  final bool dark;

  static const _medals = [Color(0xFFE5B80B), Color(0xFFA7B1C2), Color(0xFFC77B3A)];

  @override
  Widget build(BuildContext context) {
    final p = participant;
    final bg = isYou
        ? (dark ? RL.amber.withValues(alpha: 0.16) : RL.amberSoft)
        : followed
            ? RL.series[1].withValues(alpha: dark ? 0.12 : 0.07)
            : Theme.of(context).cardTheme.color;
    final border = isYou ? RL.amber : (followed ? RL.series[1].withValues(alpha: 0.4) : (dark ? const Color(0xFF1F2937) : RL.line));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: border, width: isYou ? 1.6 : 1)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openInsights(context, p.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 50,
                  child: place <= 3
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: _medals[place - 1], shape: BoxShape.circle),
                            child: Text('$place', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                          ),
                        )
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(fmtInt(place), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: isYou ? RL.amber : ink(context), fontFeatures: tabular)),
                        ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              nameOf(context, p),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w800, color: ink(context)),
                            ),
                          ),
                          if (isYou) ...[const SizedBox(width: 6), Pill(tr('You'), filled: true)],
                          if (followed) ...[const SizedBox(width: 4), Icon(Icons.star_rounded, size: 16, color: RL.series[1])],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '#${p.bib} · $category · ${p.nation}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: muted(context)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(fmtDuration(timeS), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: ink(context), fontFeatures: tabular)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.participant, required this.snapshot, required this.units, required this.followed});
  final Participant participant;
  final InsightsSnapshot snapshot;
  final Units units;
  final bool followed;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final p = participant;
    final isYou = p.id == sim.youId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: RLCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: isYou ? (Theme.of(context).brightness == Brightness.dark ? RL.amber.withValues(alpha: 0.16) : RL.amberSoft) : null,
        onTap: () => openInsights(context, p.id),
        child: Row(
          children: [
            RunnerAvatar(name: nameOf(context, p), color: isYou ? RL.amber : genderColor(p.gender)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(nameOf(context, p), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: ink(context)))),
                      if (isYou) ...[const SizedBox(width: 6), Pill(tr('You'), filled: true)],
                      if (followed) ...[const SizedBox(width: 4), Icon(Icons.star_rounded, size: 16, color: RL.series[1])],
                    ],
                  ),
                  Text(
                    '#${p.bib} · ${categoryName(sim.race, p)} · ${statusLine(snapshot, sim, p.id, units)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: muted(context)),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: muted(context)),
          ],
        ),
      ),
    );
  }
}
