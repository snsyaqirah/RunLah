import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/l10n/i18n.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/course_map.dart';
import '../../../data/app_state.dart';
import '../../../data/models.dart';
import '../../../data/sim/race_sim.dart';
import '../../home/home_data.dart';
import '../field_ticker.dart';
import '../organizer_widgets.dart';

/// Course heatmap (idea pool): runner density per 500 m painted on the
/// route, the busiest stretches called out, and the field along the course.
class HeatmapTab extends StatelessWidget {
  const HeatmapTab({super.key, required this.ticker});
  final FieldTicker ticker;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ticker,
      builder: (context, _) {
        final s = ticker.snapshot;
        return OrgTabList(
          children: [
            _MapCard(snap: s),
            _Hotspots(snap: s),
            _Distribution(snap: s),
          ],
        );
      },
    );
  }
}

class _MapCard extends StatelessWidget {
  const _MapCard({required this.snap});
  final FieldSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final race = context.read<RaceSim>().race;
    final maxD = snap.maxDensity;
    const bin = FieldTicker.binM;
    final lines = <Polyline>[
      for (var b = 0; b < snap.density.length; b++)
        if (snap.density[b] > 0)
          Polyline(
            points: race.route.slice(b * bin, math.min((b + 1) * bin, race.distanceM), step: 60),
            strokeWidth: 8,
            color: densityColor(maxD == 0 ? 0 : snap.density[b] / maxD),
          ),
    ];
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(
            tr('Course heatmap'),
            trailing: Text(
              snap.status == RaceStatus.preRace ? tr('Waiting for the gun') : tr('Runners per 500 m · live'),
              style: TextStyle(fontSize: 11.5, color: muted(context), fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(
            height: 300,
            child: Stack(
              children: [
                Positioned.fill(child: CourseMap(race: race, extraPolylines: lines, showLandmarks: false, interactive: false, padding: const EdgeInsets.all(20))),
                if (snap.running == 0)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: RL.navy.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(12)),
                      child: Text(
                        snap.status == RaceStatus.preRace
                            ? tr('All {n} runners are in the start corrals. The heatmap comes alive after the gun.', {'n': fmtInt(snap.notStarted)})
                            : tr('Nobody is on the course right now.'),
                        style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 10,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: LinearGradient(colors: [densityColor(0), densityColor(0.5), densityColor(1)]),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: Text(tr('Quiet'), style: TextStyle(fontSize: 11.5, color: muted(context)))),
              Expanded(child: Text(tr('Busy'), textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: muted(context)))),
              Expanded(
                child: Text(
                  tr('Congested ({n})', {'n': fmtInt(maxD)}),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: muted(context)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Hotspots extends StatelessWidget {
  const _Hotspots({required this.snap});
  final FieldSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final race = context.read<RaceSim>().race;
    final units = context.select<SettingsController, Units>((s) => s.units);
    final order = List<int>.generate(snap.density.length, (i) => i)..sort((a, b) => snap.density[b].compareTo(snap.density[a]));
    final top = order.where((b) => snap.density[b] > 0).take(3).toList();
    final maxD = snap.maxDensity;
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(tr('Congestion hotspots')),
          if (top.isEmpty)
            Text(tr('Hotspots appear once runners are on the course.'), style: TextStyle(color: muted(context)))
          else
            for (var r = 0; r < top.length; r++) _hotspot(context, race, units, r, top[r], maxD),
        ],
      ),
    );
  }

  Widget _hotspot(BuildContext context, Race race, Units units, int rank, int b, int maxD) {
    const bin = FieldTicker.binM;
    final from = b * bin, to = math.min((b + 1) * bin, race.distanceM);
    final mid = (from + to) / 2;
    final cp = race.checkpoints.reduce((a, c) => (c.distanceM - mid).abs() < (a.distanceM - mid).abs() ? c : a);
    final v = maxD == 0 ? 0.0 : snap.density[b] / maxD;
    final color = densityColor(v);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
            child: Text('${rank + 1}', style: TextStyle(fontWeight: FontWeight.w900, color: color)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${fmtDistance(from, units, withUnit: false)}–${fmtDistance(to, units)}',
                  style: TextStyle(fontWeight: FontWeight.w900, color: ink(context), fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                Text(
                  tr('near {cp} ({label})', {'cp': cp.name, 'label': cpLabel(cp)}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: muted(context)),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(value: v, minHeight: 5, color: color, backgroundColor: color.withValues(alpha: 0.14)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(fmtInt(snap.density[b]), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: ink(context), fontFeatures: const [FontFeature.tabularFigures()])),
              Text(tr('runners'), style: TextStyle(fontSize: 11, color: muted(context))),
            ],
          ),
        ],
      ),
    );
  }
}

class _Distribution extends StatelessWidget {
  const _Distribution({required this.snap});
  final FieldSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final race = context.read<RaceSim>().race;
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(tr('Field along the course')),
          SizedBox(
            height: 110,
            child: CustomPaint(
              painter: _DistributionPainter(
                snap.density,
                [for (final c in race.checkpoints) c.distanceM / race.distanceM],
                Theme.of(context).dividerColor,
                muted(context),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(tr('Start'), style: TextStyle(fontSize: 11.5, color: muted(context))),
              const Spacer(),
              Text(tr('Finish'), style: TextStyle(fontSize: 11.5, color: muted(context))),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tr('{run} on course · {fin} finished · {ns} still to start', {'run': fmtInt(snap.running), 'fin': fmtInt(snap.finished), 'ns': fmtInt(snap.notStarted)}),
            style: TextStyle(fontSize: 12, color: muted(context)),
          ),
        ],
      ),
    );
  }
}

class _DistributionPainter extends CustomPainter {
  _DistributionPainter(this.density, this.cpFractions, this.grid, this.tick);
  final List<int> density;
  final List<double> cpFractions;
  final Color grid;
  final Color tick;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height - 8;
    canvas.drawLine(Offset(0, h), Offset(size.width, h), Paint()..color = grid);
    for (final f in cpFractions) {
      final x = f * size.width;
      canvas.drawLine(Offset(x, h), Offset(x, h + 6), Paint()
        ..color = tick
        ..strokeWidth = 1.2);
    }
    if (density.isEmpty) return;
    final maxD = density.reduce(math.max);
    if (maxD == 0) return;
    final w = size.width / density.length;
    for (var i = 0; i < density.length; i++) {
      if (density[i] == 0) continue;
      final v = density[i] / maxD;
      final bh = math.max(2.0, v * (h - 4));
      canvas.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTWH(i * w + 0.8, h - bh, w - 1.6, bh), topLeft: const Radius.circular(2), topRight: const Radius.circular(2)),
        Paint()..color = densityColor(v),
      );
    }
  }

  @override
  bool shouldRepaint(_DistributionPainter old) => old.density != density || old.grid != grid;
}
