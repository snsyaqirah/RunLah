import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
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
import '../three/race3d_mode.dart';
import 'common.dart';
import 'finish_tab.dart' show WaitingCard;

enum _SectionMode { quarters, checkpoints, perUnit }

/// Speed tab (F19–F21): pace, section speed, overtakes, place by
/// checkpoint, who's who, and the 3D views.
class SpeedTab extends StatefulWidget {
  const SpeedTab({super.key, required this.participantId});
  final int participantId;

  @override
  State<SpeedTab> createState() => _SpeedTabState();
}

class _SpeedTabState extends State<SpeedTab> with AutomaticKeepAliveClientMixin {
  _SectionMode _mode = _SectionMode.quarters;
  int? _selected;
  int _half = 0;
  String _scope = 'overall';

  // Live overtakes scan the whole field: memoise per snapshot.
  double _memoAsOf = double.nan;
  final Map<int, ({int passed, int passedBy})> _liveMemo = {};

  @override
  bool get wantKeepAlive => true;

  int get pid => widget.participantId;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = context.watch<InsightsController>().snapshot;
    final sim = context.watch<RaceSim>();
    final units = context.watch<SettingsController>().units;
    final phase = phaseOf(sim, s, pid);
    if (phase == Phase.preRace || phase == Phase.notStarted || phase == Phase.dns) {
      return TabScroll(storageKey: 'speed-$pid', children: [WaitingCard(phase: phase, participantId: pid)]);
    }
    if (_memoAsOf != s.asOf) {
      _memoAsOf = s.asOf;
      _liveMemo.clear();
    }
    final p = sim.participant(pid);
    return TabScroll(
      storageKey: 'speed-$pid',
      children: [
        _paceCard(context, s, p, units, phase),
        _sectionCard(context, s, sim, p, units),
        _overtakesCard(context, s, sim, p, units),
        _placeChartCard(context, s, p, units),
        _whosWhoCard(context, s, p, phase),
        Column(
          children: [
            ActionTile(
              icon: Icons.videocam_rounded,
              title: tr('Drone view'),
              subtitle: tr('Watch the runners who finished around you, in 3D'),
              onTap: () => openRace3D(context, Race3DMode.drone, focusParticipantId: pid),
            ),
            const SizedBox(height: 10),
            ActionTile(
              icon: Icons.threed_rotation_rounded,
              color: RL.teal,
              title: tr('3D race replay'),
              subtitle: tr('Replay the whole race on a 3D map of KL'),
              onTap: () => openRace3D(context, Race3DMode.replay, focusParticipantId: pid),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- pace

  Widget _paceCard(BuildContext context, InsightsSnapshot s, Participant p, Units units, Phase phase) {
    double? pace;
    var soFar = false;
    if (phase == Phase.finished) {
      pace = s.result(p.id).avgPaceSPerKm;
    } else {
      final last = lastCheckpoint(s, p.id);
      if (last != null && last > 0) {
        pace = (crossAt(s, p.id, last)! - crossAt(s, p.id, 0)!) / (s.race.checkpoints[last].distanceM / 1000);
        soFar = true;
      }
    }
    final quarters = s.sections(p.id, SectionSet.quarters);
    SectionResult? best;
    var bestIdx = 0;
    for (var i = 0; i < quarters.length; i++) {
      if (best == null || quarters[i].speedKph > best.speedKph) {
        best = quarters[i];
        bestIdx = s.sectionSets[SectionSet.quarters]!.bounds.indexWhere((b) => b.$1 == quarters[i].fromIndex);
      }
    }
    final kph = pace == null || pace <= 0 ? 0.0 : 3600 / pace;
    Widget stat(String value, String unit, String label, {double from = 0}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value, style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: ink(context), height: 1, fontFeatures: tabular)),
                  const SizedBox(width: 4),
                  Text(unit, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: muted(context))),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: muted(context))),
          ],
        );
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(soFar ? tr('Average so far') : tr('Average')),
          Row(
            children: [
              Expanded(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 600, end: pace ?? 600),
                  duration: const Duration(milliseconds: 1200),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => stat(fmtPace(pace == null ? null : v, units, withUnit: false), paceUnit(units), tr('avg pace')),
                ),
              ),
              Container(width: 1, height: 52, color: Theme.of(context).dividerTheme.color),
              const SizedBox(width: 16),
              Expanded(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: kph),
                  duration: const Duration(milliseconds: 1200),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => stat(fmtSpeed(v, units, withUnit: false), speedUnit(units), tr('avg speed')),
                ),
              ),
            ],
          ),
          if (best != null && quarters.length > 1) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: RL.amber.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: RL.amber, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr('Fastest quarter: Q{q} at {speed}', {'q': bestIdx + 1, 'speed': fmtSpeed(best.speedKph, units)}),
                      style: TextStyle(fontWeight: FontWeight.w800, color: ink(context)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------- section speed

  List<_Bar> _bars(InsightsSnapshot s, RaceSim sim, Participant p, Units units) {
    final cps = s.race.checkpoints;
    if (_mode == _SectionMode.perUnit) {
      final unitM = units == Units.km ? 1000.0 : kMetresPerMile;
      final total = s.race.distanceM;
      final n = (total / unitM).floor();
      final out = <_Bar>[];
      for (var k = 1; k <= n; k++) {
        final from = (k - 1) * unitM;
        final to = k == n ? total : k * unitM;
        final ta = sim.crossingTime(p.id, from), tb = sim.crossingTime(p.id, to);
        final done = ta != null && tb != null && tb <= s.asOf && tb > ta;
        out.add(_Bar(
          label: '$k',
          range: '${fmtDistance(from, units, withUnit: false)}–${fmtDistance(to, units)}',
          distanceM: to - from,
          durationS: done ? tb - ta : null,
        ));
      }
      return out;
    }
    final set = _mode == _SectionMode.quarters ? SectionSet.quarters : SectionSet.checkpoints;
    final data = s.sectionSets[set]!;
    final done = {for (final sr in s.sections(p.id, set)) sr.fromIndex: sr};
    return [
      for (var i = 0; i < data.bounds.length; i++)
        () {
          final (a, b) = data.bounds[i];
          final sr = done[a];
          return _Bar(
            label: _mode == _SectionMode.quarters ? 'Q${i + 1}' : cpAxisLabel(cps[b], units),
            range: '${cpAxisLabel(cps[a], units)}–${fmtDistance(cps[b].distanceM, units)}',
            distanceM: cps[b].distanceM - cps[a].distanceM,
            durationS: sr?.durationS,
            passed: sr?.passed,
            passedBy: sr?.passedBy,
          );
        }(),
    ];
  }

  Widget _sectionCard(BuildContext context, InsightsSnapshot s, RaceSim sim, Participant p, Units units) {
    if (_mode == _SectionMode.perUnit && !p.hasGps) _mode = _SectionMode.quarters;
    final bars = _bars(s, sim, p, units);
    var fastest = -1;
    for (var i = 0; i < bars.length; i++) {
      if (bars[i].kph != null && (fastest < 0 || bars[i].kph! > bars[fastest].kph!)) fastest = i;
    }
    var sel = _selected ?? fastest;
    if (sel < 0 || sel >= bars.length || bars[sel].kph == null) sel = fastest;
    final b = sel >= 0 ? bars[sel] : null;
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(tr('Section speed')),
          SegToggle<_SectionMode>(
            value: _mode,
            options: [
              (_SectionMode.quarters, tr('Quarters')),
              (_SectionMode.checkpoints, tr('Checkpoints')),
              if (p.hasGps) (_SectionMode.perUnit, units == Units.km ? tr('Per km') : tr('Per mile')),
            ],
            onChanged: (m) => setState(() {
              _mode = m;
              _selected = null;
            }),
          ),
          const SizedBox(height: 14),
          _SectionBars(
            key: ValueKey(_mode),
            bars: bars,
            selected: sel,
            fastest: fastest,
            units: units,
            showValues: bars.length <= 9,
            onSelect: (i) => setState(() => _selected = i),
          ),
          const SizedBox(height: 12),
          if (b == null)
            Text(tr('Section speeds appear once the first section is complete.'), style: TextStyle(color: muted(context)))
          else
            _SectionDetail(bar: b, units: units, fastest: sel == fastest),
          if (bars.any((x) => x.kph == null) && b != null) ...[
            const SizedBox(height: 8),
            Text(tr('Dashed bars are sections not run yet.'), style: TextStyle(fontSize: 12, color: muted(context))),
          ],
        ],
      ),
    );
  }

  // ----------------------------------------------------------- overtakes

  Widget _overtakesCard(BuildContext context, InsightsSnapshot s, RaceSim sim, Participant p, Units units) {
    final halfCp = s.race.checkpointNear(0.5);
    final halfM = s.race.checkpoints[halfCp].distanceM;
    final fromIdx = _half == 0 ? 0 : halfCp;
    SectionResult? sec;
    for (final h in s.sections(p.id, SectionSet.halves)) {
      if (h.fromIndex == fromIdx) sec = h;
    }
    int? passed, passedBy, basedOn;
    var live = false;
    if (sec != null) {
      passed = sec.passed;
      passedBy = sec.passedBy;
      basedOn = sec.basedOn;
    } else if (crossAt(s, p.id, fromIdx) != null && sim.stateAt(p.id, s.asOf) == RunnerState.running) {
      final r = _liveMemo.putIfAbsent(_half, () => sim.liveOvertakes(p.id, _half == 0 ? 0 : halfM, s.asOf));
      passed = r.passed;
      passedBy = r.passedBy;
      live = true;
    }
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(tr('Overtakes'), trailing: live ? Pill(tr('Live'), color: RL.green, icon: Icons.sensors_rounded) : null),
          SegToggle<int>(
            value: _half,
            options: [(0, tr('1st half')), (1, tr('2nd half'))],
            onChanged: (h) => setState(() => _half = h),
          ),
          const SizedBox(height: 16),
          if (passed == null)
            Row(
              children: [
                Icon(Icons.hourglass_empty_rounded, color: muted(context)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('Counts start when {name} reaches halfway ({km}).', {'name': firstNameOf(context, p), 'km': fmtDistance(halfM, units)}),
                    style: TextStyle(color: muted(context)),
                  ),
                ),
              ],
            )
          else ...[
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _OvertakeStat(key: ValueKey('p$_half'), value: passed, label: p.id == sim.youId ? tr('you passed') : tr('passed'), color: RL.green, icon: Icons.trending_up_rounded)),
                  VerticalDivider(width: 24, color: Theme.of(context).dividerTheme.color),
                  Expanded(child: _OvertakeStat(key: ValueKey('b$_half'), value: passedBy!, label: p.id == sim.youId ? tr('passed you') : tr('passed them'), color: RL.red, icon: Icons.trending_down_rounded)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(color: (passed >= passedBy ? RL.green : RL.red).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Text(
                tr('Net {n} places on the road', {'n': '${passed >= passedBy ? '+' : '−'}${fmtInt((passed - passedBy).abs())}'}),
                style: TextStyle(fontWeight: FontWeight.w800, color: passed >= passedBy ? RL.green : RL.red),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              live
                  ? tr('Live count since {from}, by distance on the road right now.', {'from': _half == 0 ? tr('the start') : tr('halfway')})
                  : tr('Based on {n} runners with timing at both ends. Counted by clock time: who was physically ahead on the road.', {'n': fmtInt(basedOn ?? 0)}),
              style: TextStyle(fontSize: 12.5, color: muted(context)),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------- place by checkpoint

  Widget _placeChartCard(BuildContext context, InsightsSnapshot s, Participant p, Units units) {
    final places = s.placesByCheckpoint(p.id);
    final cps = s.race.checkpoints;
    final spots = [for (var k = 0; k < places.length; k++) if (places[k] != null) FlSpot(k.toDouble(), -places[k]!.toDouble())];
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget body;
    if (spots.length < 2) {
      body = Text(tr('The chart fills in as {name} passes checkpoints.', {'name': firstNameOf(context, p)}), style: TextStyle(color: muted(context)));
    } else {
      final first = -spots.first.y, last = -spots.last.y;
      final hi = spots.map((e) => -e.y).reduce(math.max), lo = spots.map((e) => -e.y).reduce(math.min);
      final pad = math.max(2.0, (hi - lo) * 0.14);
      final minY = -(hi + pad), maxY = -math.max(0.0, lo - pad);
      final gained = first - last;
      final gridColor = dark ? Colors.white10 : RL.line;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Text(ordinal(first.round()), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: muted(context), fontFeatures: tabular)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.arrow_forward_rounded, size: 20, color: muted(context)),
                      ),
                      Text(ordinal(last.round()), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: ink(context), fontFeatures: tabular)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Pill(
                gained >= 0 ? tr('+{n} places', {'n': fmtInt(gained.round())}) : tr('−{n} places', {'n': fmtInt((-gained).round())}),
                color: gained >= 0 ? RL.green : RL.red,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 190,
            padding: const EdgeInsets.only(right: 12, top: 6),
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (cps.length - 1).toDouble(),
                minY: minY,
                maxY: maxY,
                clipData: const FlClipData.all(),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(color: gridColor, strokeWidth: 1, dashArray: [4, 4]),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      minIncluded: false,
                      maxIncluded: false,
                      getTitlesWidget: (v, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(fmtInt((-v).round()), style: TextStyle(fontSize: 10, color: muted(context), fontFeatures: tabular)),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: 24,
                      getTitlesWidget: (v, meta) {
                        final k = v.round();
                        if ((v - k).abs() > 0.01 || k < 0 || k >= cps.length) return const SizedBox.shrink();
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(cpAxisLabel(cps[k], units), style: TextStyle(fontSize: 9.5, color: muted(context))),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => RL.navy,
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItems: (spots) => [
                      for (final sp in spots)
                        LineTooltipItem(
                          '${cps[sp.x.round()].shortLabel}\n',
                          const TextStyle(color: Colors.white70, fontSize: 11),
                          children: [TextSpan(text: ordinal((-sp.y).round()), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13))],
                        ),
                    ],
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.22,
                    preventCurveOverShooting: true,
                    color: RL.amber,
                    barWidth: 3.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      getDotPainter: (spot, _, _, _) => FlDotCirclePainter(radius: 4.5, color: dark ? const Color(0xFF111827) : Colors.white, strokeColor: RL.amber, strokeWidth: 3),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [RL.amber.withValues(alpha: 0.28), RL.amber.withValues(alpha: 0.0)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tr('Place in clock order as {name} crossed each checkpoint ({unit}). Higher is better.', {'name': firstNameOf(context, p), 'unit': distUnit(units)}),
            style: TextStyle(fontSize: 12, color: muted(context)),
          ),
        ],
      );
    }
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [SectionLabel(tr('Place by checkpoint')), body],
      ),
    );
  }

  // ----------------------------------------------------------- who's who

  Widget _whosWhoCard(BuildContext context, InsightsSnapshot s, Participant p, Phase phase) {
    final cat = categoryName(s.race, p);
    final scopes = [
      ('overall', tr('Everyone')),
      ('gender:${p.gender.code}', p.gender == Gender.f ? tr('Women') : tr('Men')),
      ('category:${p.categoryId}', cat),
    ];
    if (!scopes.any((e) => e.$1 == _scope)) _scope = 'overall';
    final g = s.stats[_scope];
    final mine = phase == Phase.finished ? s.result(p.id).netS : null;
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(tr('Who\'s who')),
          SegToggle<String>(value: _scope, options: scopes, onChanged: (v) => setState(() => _scope = v)),
          const SizedBox(height: 16),
          if (g == null || g.finishers == 0)
            Text(tr('No finishers yet in this group.'), style: TextStyle(color: muted(context)))
          else ...[
            Row(
              children: [
                GenderDonut(key: ValueKey(_scope), female: g.female, male: g.male, size: 112),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _LegendRow(color: RL.female, label: tr('Women'), value: '${fmtInt(g.female)} · ${fmtPct(g.female / g.finishers * 100)}'),
                      const SizedBox(height: 6),
                      _LegendRow(
                        color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF6FA3D8) : RL.male,
                        label: tr('Men'),
                        value: '${fmtInt(g.male)} · ${fmtPct(g.male / g.finishers * 100)}',
                      ),
                      const SizedBox(height: 12),
                      Text(tr('Median net time'), style: TextStyle(fontSize: 12, color: muted(context))),
                      Text(fmtDuration(g.medianNetS), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: ink(context), fontFeatures: tabular)),
                      if (g.fastestNetS != null)
                        Text(tr('Fastest {t}', {'t': fmtDuration(g.fastestNetS)}), style: TextStyle(fontSize: 12, color: muted(context))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FinishHistogram(key: ValueKey('h$_scope'), stats: g, mine: mine),
            const SizedBox(height: 8),
            Text(
              s.provisional ? tr('Finish times of {n} finishers so far, in 10-minute bins.', {'n': fmtInt(g.finishers)}) : tr('Finish times of all {n} finishers, in 10-minute bins.', {'n': fmtInt(g.finishers)}),
              style: TextStyle(fontSize: 12, color: muted(context)),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ pieces

class _Bar {
  _Bar({required this.label, required this.range, required this.distanceM, this.durationS, this.passed, this.passedBy});
  final String label;
  final String range;
  final double distanceM;
  final double? durationS;
  final int? passed;
  final int? passedBy;
  double? get kph => durationS == null || durationS! <= 0 ? null : distanceM / durationS! * 3.6;
}

/// Animated vertical speed bars. Fastest in amber, unrun sections dashed.
class _SectionBars extends StatelessWidget {
  const _SectionBars({
    super.key,
    required this.bars,
    required this.selected,
    required this.fastest,
    required this.units,
    required this.onSelect,
    this.showValues = true,
  });
  final List<_Bar> bars;
  final int selected;
  final int fastest;
  final Units units;
  final ValueChanged<int> onSelect;
  final bool showValues;

  @override
  Widget build(BuildContext context) {
    final list = bars;
    final speeds = [for (final b in list) if (b.kph != null) b.kph!];
    final maxV = speeds.isEmpty ? 1.0 : speeds.reduce(math.max);
    final minV = speeds.isEmpty ? 0.0 : speeds.reduce(math.min);
    final floor = speeds.length < 2 ? 0.0 : math.max(0.0, minV - (maxV - minV) * 1.2 - 0.5);
    final primary = Theme.of(context).colorScheme.primary;
    const chartH = 128.0;
    final dense = list.length > 9;
    return SizedBox(
      height: chartH * 1.06 + 46,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < list.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: list[i].kph == null ? null : () => onSelect(i),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: dense ? 1.5 : 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        height: 18,
                        child: (list[i].kph != null && (showValues || i == selected))
                            ? FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  fmtSpeed(list[i].kph!, units, withUnit: false),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: i == selected ? FontWeight.w900 : FontWeight.w700,
                                    color: i == fastest ? RL.amber : (i == selected ? ink(context) : muted(context)),
                                    fontFeatures: tabular,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 4),
                      if (list[i].kph == null)
                        Container(
                          height: chartH * 0.3,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(dense ? 3 : 8),
                            border: Border.all(color: muted(context).withValues(alpha: 0.35), width: 1.2, strokeAlign: BorderSide.strokeAlignInside),
                          ),
                        )
                      else
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: maxV == floor ? 0.8 : 0.12 + 0.88 * (list[i].kph! - floor) / (maxV - floor)),
                          duration: Duration(milliseconds: 700 + 45 * i),
                          curve: Interval(math.min(0.6, 0.045 * i), 1, curve: Curves.easeOutBack),
                          builder: (_, v, _) => Container(
                            height: chartH * v.clamp(0.0, 1.05),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(dense ? 3 : 8), bottom: Radius.circular(dense ? 1 : 3)),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: i == fastest
                                    ? [const Color(0xFFFFB547), RL.amber]
                                    : i == selected
                                        ? [primary, primary.withValues(alpha: 0.8)]
                                        : [primary.withValues(alpha: 0.62), primary.withValues(alpha: 0.4)],
                              ),
                              boxShadow: i == selected ? [BoxShadow(color: (i == fastest ? RL.amber : primary).withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))] : null,
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 16,
                        child: (!dense || i == 0 || (i + 1) % 5 == 0 || i == list.length - 1 || i == selected)
                            ? FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  list[i].label,
                                  style: TextStyle(fontSize: 11, fontWeight: i == selected ? FontWeight.w900 : FontWeight.w600, color: i == selected ? ink(context) : muted(context)),
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionDetail extends StatelessWidget {
  const _SectionDetail({required this.bar, required this.units, required this.fastest});
  final _Bar bar;
  final Units units;
  final bool fastest;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget chip(String v, String l) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: ink(context), fontFeatures: tabular))),
            Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: muted(context))),
          ],
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: dark ? Colors.white.withValues(alpha: 0.04) : RL.bg, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(bar.label, style: TextStyle(fontWeight: FontWeight.w900, color: fastest ? RL.amber : ink(context))),
              const SizedBox(width: 8),
              Expanded(child: Text(bar.range, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: muted(context)))),
              if (fastest) Pill(tr('Fastest'), icon: Icons.bolt_rounded),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: chip(fmtDuration(bar.durationS), tr('time'))),
              Expanded(child: chip(fmtPace(bar.durationS! / (bar.distanceM / 1000), units), tr('pace'))),
              Expanded(child: chip(fmtSpeed(bar.kph!, units), tr('speed'))),
            ],
          ),
          if (bar.passed != null) ...[
            const SizedBox(height: 8),
            Text(
              tr('Passed {a} · passed by {b}', {'a': fmtInt(bar.passed!), 'b': fmtInt(bar.passedBy ?? 0)}),
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ink(context)),
            ),
          ],
        ],
      ),
    );
  }
}

class _OvertakeStat extends StatelessWidget {
  const _OvertakeStat({super.key, required this.value, required this.label, required this.color, required this.icon});
  final int value;
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 4),
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: muted(context)))),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: CountUp(
              value: value.toDouble(),
              duration: const Duration(milliseconds: 1400),
              format: (v) => fmtInt(v.round()),
              style: TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: color, height: 1.05, fontFeatures: tabular),
            ),
          ),
        ],
      );
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.color, required this.label, required this.value});
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: ink(context))),
          const SizedBox(width: 6),
          Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: muted(context), fontFeatures: tabular))),
        ],
      );
}

/// Female / male donut with the finisher count in the middle.
class GenderDonut extends StatelessWidget {
  const GenderDonut({super.key, required this.female, required this.male, this.size = 112});
  final int female;
  final int male;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final total = female + male;
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1300),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => CustomPaint(
          painter: _DonutPainter(
            progress: v,
            female: total == 0 ? 0 : female / total,
            maleColor: dark ? const Color(0xFF6FA3D8) : RL.male,
            track: dark ? Colors.white10 : RL.line,
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(size * 0.2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(fmtInt((total * v).round()), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: ink(context), fontFeatures: tabular)),
                    Text(tr('finishers'), style: TextStyle(fontSize: 11, color: muted(context))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.progress, required this.female, required this.maleColor, required this.track});
  final double progress;
  final double female;
  final Color maleColor;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.14;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, 0, math.pi * 2, false, p..color = track);
    const start = -math.pi / 2;
    final sweep = math.pi * 2 * progress;
    const gap = 0.04;
    final fs = sweep * female;
    final ms = sweep * (1 - female);
    if (fs > gap) canvas.drawArc(rect, start, fs - gap, false, p..color = RL.female);
    if (ms > gap) canvas.drawArc(rect, start + fs, ms - gap, false, p..color = maleColor);
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.progress != progress || old.female != female || old.maleColor != maleColor;
}

/// Finish-time histogram with "you" highlighted and the median marked.
class FinishHistogram extends StatelessWidget {
  const FinishHistogram({super.key, required this.stats, this.mine});
  final GroupStats stats;
  final double? mine;

  @override
  Widget build(BuildContext context) {
    final g = stats;
    final bins = g.histogram;
    final n = bins.length;
    final maxC = math.max(1, bins.reduce(math.max));
    final span = n * g.histBinS;
    final myBin = mine == null ? null : ((mine! - g.histStartS) / g.histBinS).floor().clamp(0, n - 1);
    final medFrac = g.medianNetS.isNaN ? null : ((g.medianNetS - g.histStartS) / span).clamp(0.0, 1.0);
    final primary = Theme.of(context).colorScheme.primary;
    String hm(double s) => '${s ~/ 3600}:${((s % 3600) ~/ 60).toInt().toString().padLeft(2, '0')}';
    const barsH = 116.0;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final bw = w / n;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 22,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (myBin != null)
                    Positioned(
                      left: ((myBin + 0.5) * bw - 24).clamp(0.0, w - 48),
                      width: 48,
                      top: 0,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: RL.amber, borderRadius: BorderRadius.circular(6)),
                            child: Text(tr('You'), maxLines: 1, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10.5)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: barsH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < n; i++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: bins[i] / maxC),
                              duration: Duration(milliseconds: 600 + 30 * i),
                              curve: Curves.easeOutCubic,
                              builder: (_, v, _) => Container(
                                height: math.max(bins[i] > 0 ? 2.0 : 0.0, (barsH - 18) * v),
                                decoration: BoxDecoration(
                                  color: i == myBin ? RL.amber : primary.withValues(alpha: 0.32),
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (medFrac != null)
                    Positioned(
                      left: medFrac * w - 1,
                      top: 0,
                      bottom: 0,
                      child: CustomPaint(size: const Size(2, barsH), painter: _DashPainter(color: ink(context).withValues(alpha: 0.7))),
                    ),
                  if (medFrac != null)
                    Positioned(
                      left: medFrac > 0.6 ? null : medFrac * w + 5,
                      right: medFrac > 0.6 ? w - medFrac * w + 5 : null,
                      top: 0,
                      child: Text(
                        tr('median {t}', {'t': fmtDuration(g.medianNetS)}),
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: ink(context), fontFeatures: tabular),
                      ),
                    ),
                ],
              ),
            ),
            Container(height: 1, color: Theme.of(context).dividerTheme.color),
            const SizedBox(height: 4),
            SizedBox(
              height: 14,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i <= n; i += 3)
                    Positioned(
                      left: (i * bw - 16).clamp(0.0, w - 32),
                      width: 32,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(hm(g.histStartS + i * g.histBinS), style: TextStyle(fontSize: 10, color: muted(context), fontFeatures: tabular)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    for (var y = 14.0; y < size.height; y += 6) {
      canvas.drawLine(Offset(1, y), Offset(1, math.min(size.height, y + 3)), p);
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter old) => old.color != color;
}
