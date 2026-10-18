import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../data/activity_store.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import 'activity_detail_screen.dart';
import 'race_run_controller.dart';
import 'run_widgets.dart';

/// "Your runs": the race-day result (once you finish) plus saved free runs.
class RunHistorySection extends StatelessWidget {
  const RunHistorySection({super.key, required this.phase});
  final ValueListenable<RunPhase> phase;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ActivityStore>();
    final units = context.select<SettingsController, Units>((s) => s.units);
    final runs = store.activities;
    return ValueListenableBuilder<RunPhase>(
      valueListenable: phase,
      builder: (context, ph, _) {
        final raceDone = ph == RunPhase.finished;
        final total = runs.length + (raceDone ? 1 : 0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionLabel(
              tr('Your runs'),
              trailing: total == 0
                  ? null
                  : Text(
                      tr('{n} runs · {dist}', {'n': total, 'dist': fmtDistance(store.totalDistanceM + (raceDone ? context.read<RaceSim>().race.distanceM : 0), units)}),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: muted(context)),
                    ),
            ),
            if (raceDone) ...[const _EventRunTile(), const SizedBox(height: 10)],
            if (total == 0)
              RLCard(
                child: InfoRow(icon: Icons.directions_run_rounded, color: RL.amber, title: tr('No runs yet'), subtitle: tr('Start a free run and it shows up here.')),
              ),
            for (final (i, a) in runs.indexed) ...[
              FadeSlideIn(key: ValueKey(a.id), index: i.clamp(0, 6), child: _ActivityTile(activity: a, units: units)),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _EventRunTile extends StatelessWidget {
  const _EventRunTile();

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final row = context.select<InsightsController, ResultRow>((c) => c.snapshot.result(sim.youId));
    final net = sim.plan(sim.youId).netS;
    return RLCard(
      onTap: () => openInsights(context, sim.youId),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFF5B342), RL.amber], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(sim.event.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: ink(context))),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    tr('Half marathon'),
                    fmtDuration(net),
                    if (row.overall != null) ordinal(row.overall!.place),
                  ].join(' · '),
                  style: TextStyle(fontSize: 12.5, color: muted(context), fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Pill(tr('Race Insights'), color: RL.amber, icon: Icons.insights_rounded),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: muted(context)),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity, required this.units});
  final Activity activity;
  final Units units;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    return RLCard(
      padding: const EdgeInsets.all(12),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ActivityDetailScreen(activityId: a.id))),
      child: Row(
        children: [
          RouteThumb(points: a.points),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: ink(context))),
                const SizedBox(height: 2),
                Text(
                  '${fmtDate(a.startedAt)} · ${fmtClock(a.startedAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: muted(context)),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Stat(fmtDistance(a.distanceM, units, decimals: 2)),
                    _Stat(fmtDuration(a.movingS)),
                    _Stat(fmtPace(a.avgPaceSPerKm, units)),
                    if (a.sample) Pill(tr('Sample'), color: RL.slate),
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: muted(context)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: ink(context), fontFeatures: const [FontFeature.tabularFigures()]),
      );
}
