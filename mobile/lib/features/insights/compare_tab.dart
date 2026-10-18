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
import 'common.dart';
import 'finish_tab.dart' show WaitingCard;

/// Compare tab (F25): up to 4 runners side by side plus a gap chart.
class CompareTab extends StatefulWidget {
  const CompareTab({super.key, required this.participantId});
  final int participantId;

  @override
  State<CompareTab> createState() => _CompareTabState();
}

class _CompareTabState extends State<CompareTab> with AutomaticKeepAliveClientMixin {
  late List<int> _ids;

  static const maxRunners = 4;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final sim = context.read<RaceSim>();
    final follows = context.read<FollowsController>();
    final pid = widget.participantId;
    final others = <int>{if (pid != sim.youId) sim.youId, ...follows.ids}..remove(pid);
    _ids = [pid, ...others.take(maxRunners - 1)];
  }

  Future<void> _add() async {
    final sim = context.read<RaceSim>();
    final s = context.read<InsightsController>().snapshot;
    final g = s.ghosts(widget.participantId);
    final id = await pickRunner(
      context,
      exclude: _ids.toSet(),
      suggestions: {sim.youId, ...context.read<FollowsController>().ids, ?g.ahead, ?g.behind}.toList(),
    );
    if (id != null && mounted && !_ids.contains(id) && _ids.length < maxRunners) setState(() => _ids.add(id));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = context.watch<InsightsController>().snapshot;
    final sim = context.watch<RaceSim>();
    final units = context.watch<SettingsController>().units;
    final pid = widget.participantId;
    if (sim.status == RaceStatus.preRace) {
      return TabScroll(storageKey: 'compare-$pid', children: [WaitingCard(phase: Phase.preRace, participantId: pid)]);
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    return TabScroll(
      storageKey: 'compare-$pid',
      children: [
        RLCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionLabel(tr('Runners')),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _ids.length; i++)
                    InputChip(
                      avatar: CircleAvatar(backgroundColor: RL.series[i], radius: 9),
                      label: Text(_chipName(context, sim, _ids[i]), maxLines: 1, overflow: TextOverflow.ellipsis),
                      labelStyle: TextStyle(fontWeight: FontWeight.w700, color: ink(context)),
                      backgroundColor: RL.series[i].withValues(alpha: dark ? 0.18 : 0.10),
                      onPressed: () => openInsights(context, _ids[i]),
                      onDeleted: i == 0 ? null : () => setState(() => _ids.removeAt(i)),
                    ),
                  if (_ids.length < maxRunners)
                    ActionChip(
                      avatar: const Icon(Icons.person_add_alt_1_rounded, size: 18, color: RL.amber),
                      label: Text(tr('Add runner')),
                      labelStyle: const TextStyle(fontWeight: FontWeight.w800, color: RL.amber),
                      onPressed: _add,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(tr('Compare up to 4 runners by name or bib. Gaps are measured against the first runner.'), style: TextStyle(fontSize: 12.5, color: muted(context))),
            ],
          ),
        ),
        _table(context, s, sim, units),
        _gapChart(context, s, sim, units),
      ],
    );
  }

  String _chipName(BuildContext context, RaceSim sim, int id) {
    final p = sim.participant(id);
    return id == sim.youId ? '${firstNameOf(context, p)} (${tr('You')})' : firstNameOf(context, p);
  }

  Widget _table(BuildContext context, InsightsSnapshot s, RaceSim sim, Units units) {
    final quarterBounds = s.sectionSets[SectionSet.quarters]!.bounds;
    final cols = [
      for (final id in _ids)
        (
          p: sim.participant(id),
          phase: phaseOf(sim, s, id),
          r: s.result(id),
          q: {for (final sec in s.sections(id, SectionSet.quarters)) sec.fromIndex: sec},
        ),
    ];
    // (label, value per column, formatter)
    final rows = <(String, List<double?>, String Function(double))>[
      (tr('Net time'), [for (final c in cols) c.r.netS], fmtDuration),
      (tr('Gun time'), [for (final c in cols) c.r.gunS], fmtDuration),
      (tr('Overall'), [for (final c in cols) c.r.overall?.place.toDouble()], (v) => ordinal(v.round())),
      (tr('Gender'), [for (final c in cols) c.r.gender?.place.toDouble()], (v) => ordinal(v.round())),
      (tr('Category'), [for (final c in cols) c.r.category?.place.toDouble()], (v) => ordinal(v.round())),
      (tr('Avg pace'), [for (final c in cols) c.r.avgPaceSPerKm], (v) => fmtPace(v, units)),
      for (var qi = 0; qi < quarterBounds.length; qi++)
        (tr('Quarter {n}', {'n': qi + 1}), [for (final c in cols) c.q[quarterBounds[qi].$1]?.durationS], fmtDuration),
    ];
    String placeholder(Phase ph) => switch (ph) {
          Phase.onCourse => tr('On course'),
          Phase.dnf => tr('DNF'),
          Phase.dns => tr('DNS'),
          _ => '–',
        };
    const labelW = 86.0, rowH = 38.0, headH = 56.0;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final stripe = dark ? Colors.white.withValues(alpha: 0.03) : RL.bg.withValues(alpha: 0.7);
    return RLCard(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: SectionLabel(tr('Side by side'))),
          LayoutBuilder(
            builder: (context, c) {
              final colW = math.max(80.0, (c.maxWidth - labelW) / cols.length);
              Widget cell(Widget child, int row, {double h = rowH}) => Container(
                    height: h,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    color: row.isOdd ? stripe : null,
                    child: child,
                  );
              final labels = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: headH),
                  for (var r = 0; r < rows.length; r++)
                    cell(Text(rows[r].$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: muted(context))), r),
                ],
              );
              final values = Row(
                children: [
                  for (var ci = 0; ci < cols.length; ci++)
                    SizedBox(
                      width: colW,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: headH,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Container(height: 4, width: 28, decoration: BoxDecoration(color: RL.series[ci], borderRadius: BorderRadius.circular(99))),
                                  const SizedBox(height: 6),
                                  Text(firstNameOf(context, cols[ci].p), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, color: ink(context))),
                                  Text('#${cols[ci].p.bib}', maxLines: 1, style: TextStyle(fontSize: 11.5, color: muted(context))),
                                ],
                              ),
                            ),
                          ),
                          for (var r = 0; r < rows.length; r++)
                            () {
                              final v = rows[r].$2[ci];
                              final known = [for (final x in rows[r].$2) ?x];
                              final best = known.length > 1 && v != null && v == known.reduce(math.min);
                              final text = v == null ? (r == 0 ? placeholder(cols[ci].phase) : '–') : rows[r].$3(v);
                              return cell(
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    text,
                                    style: TextStyle(
                                      fontWeight: best ? FontWeight.w900 : FontWeight.w700,
                                      color: best ? RL.amber : (v == null ? muted(context) : ink(context)),
                                      fontFeatures: tabular,
                                    ),
                                  ),
                                ),
                                r,
                              );
                            }(),
                        ],
                      ),
                    ),
                ],
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: labelW, child: labels),
                  Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: values)),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(tr('Best in each row in amber. Places use the {basis} time.', {'basis': s.basis == RankBasis.net ? tr('net') : tr('gun')}), style: TextStyle(fontSize: 12, color: muted(context))),
          ),
        ],
      ),
    );
  }

  Widget _gapChart(BuildContext context, InsightsSnapshot s, RaceSim sim, Units units) {
    final cps = s.race.checkpoints;
    final base = _ids.first;
    double? netAt(int id, int k) {
      final a = crossAt(s, id, 0), b = crossAt(s, id, k);
      return a == null || b == null ? null : b - a;
    }

    final lines = <LineChartBarData>[];
    var lo = 0.0, hi = 0.0;
    var anyOther = false;
    for (var i = 0; i < _ids.length; i++) {
      final spots = <FlSpot>[];
      for (var k = 0; k < cps.length; k++) {
        final nb = netAt(base, k), nr = netAt(_ids[i], k);
        if (nb == null || nr == null) continue;
        final y = -(nr - nb);
        lo = math.min(lo, y);
        hi = math.max(hi, y);
        spots.add(FlSpot(k.toDouble(), y));
      }
      if (i > 0 && spots.length > 1) anyOther = true;
      lines.add(LineChartBarData(
        spots: spots,
        color: RL.series[i],
        barWidth: i == 0 ? 2 : 3.5,
        dashArray: i == 0 ? [6, 4] : null,
        isCurved: true,
        curveSmoothness: 0.2,
        preventCurveOverShooting: true,
        isStrokeCapRound: true,
        dotData: FlDotData(show: i > 0, getDotPainter: (_, _, bar, _) => FlDotCirclePainter(radius: 3.5, color: bar.color ?? RL.amber, strokeColor: Colors.white, strokeWidth: 1.5)),
      ));
    }
    final baseName = firstNameOf(context, sim.participant(base));
    Widget body;
    if (!anyOther) {
      body = Text(
        _ids.length < 2 ? tr('Add a runner to see the gap chart.') : tr('The gap chart fills in as runners pass checkpoints.'),
        style: TextStyle(color: muted(context)),
      );
    } else {
      final range = math.max(60.0, hi - lo);
      const steps = <double>[10, 15, 30, 60, 120, 300, 600, 900, 1200, 1800, 3600, 5400];
      final step = steps.firstWhere((x) => range / x <= 4, orElse: () => 7200);
      final minY = (lo / step).floor() * step - (lo % step == 0 ? step * 0.25 : 0);
      final maxY = (hi / step).ceil() * step + (hi % step == 0 ? step * 0.25 : 0);
      final dark = Theme.of(context).brightness == Brightness.dark;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 210,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (cps.length - 1).toDouble(),
                minY: minY,
                maxY: maxY,
                clipData: const FlClipData.all(),
                lineBarsData: lines,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: step,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: v == 0 ? ink(context).withValues(alpha: 0.35) : (dark ? Colors.white10 : RL.line),
                    strokeWidth: v == 0 ? 1.4 : 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: step,
                      reservedSize: 46,
                      getTitlesWidget: (v, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(
                          v.abs() < 0.5 ? '0' : fmtDuration(-v, signed: true),
                          style: TextStyle(fontSize: 10, color: muted(context), fontFeatures: tabular),
                        ),
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
                        return SideTitleWidget(meta: meta, child: Text(cpAxisLabel(cps[k], units), style: TextStyle(fontSize: 9.5, color: muted(context))));
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
                          '${firstNameOf(context, sim.participant(_ids[sp.barIndex]))} ${sp.y.abs() < 0.5 ? '±0' : fmtDuration(-sp.y, signed: true)}',
                          TextStyle(color: RL.series[sp.barIndex], fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr('Net-time gap to {name} at each checkpoint ({unit}). Above the line = ahead, below = behind.', {'name': baseName, 'unit': distUnit(units)}),
            style: TextStyle(fontSize: 12, color: muted(context)),
          ),
        ],
      );
    }
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [SectionLabel(tr('Gap chart')), body],
      ),
    );
  }
}

/// Bottom sheet to find a runner by name or bib. Returns the participant id.
Future<int?> pickRunner(BuildContext context, {Set<int> exclude = const {}, List<int> suggestions = const []}) => showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PickerSheet(exclude: exclude, suggestions: suggestions),
    );

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.exclude, required this.suggestions});
  final Set<int> exclude;
  final List<int> suggestions;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final s = context.watch<InsightsController>().snapshot;
    final units = context.read<SettingsController>().units;
    final results = _q.trim().isEmpty ? [for (final id in widget.suggestions) sim.participant(id)] : sim.search(_q, limit: 40);
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SizedBox(
        height: mq.size.height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(tr('Add a runner'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: ink(context))),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: tr('Name or bib number')),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            const SizedBox(height: 8),
            if (_q.trim().isEmpty && results.isNotEmpty)
              Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 0), child: SectionLabel(tr('Suggestions'))),
            Expanded(
              child: results.isEmpty
                  ? Center(child: Text(tr('No runners found'), style: TextStyle(color: muted(context))))
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: results.length,
                      itemBuilder: (_, i) {
                        final p = results[i];
                        final taken = widget.exclude.contains(p.id);
                        return ListTile(
                          enabled: !taken,
                          leading: RunnerAvatar(name: nameOf(context, p), color: p.id == sim.youId ? RL.amber : genderColor(p.gender)),
                          title: Text(p.id == sim.youId ? '${nameOf(context, p)} (${tr('You')})' : p.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('#${p.bib} · ${categoryName(sim.race, p)} · ${statusLine(s, sim, p.id, units)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Icon(taken ? Icons.check_rounded : Icons.add_circle_outline_rounded, color: taken ? muted(context) : RL.amber),
                          onTap: taken ? null : () => Navigator.pop(context, p.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
