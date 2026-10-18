import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../data/activity_store.dart';
import '../../data/app_state.dart';
import 'run_widgets.dart';

/// A saved free run (PRD F17): map of the track, stats, pace chart, km
/// splits, the share link and upload status.
class ActivityDetailScreen extends StatelessWidget {
  const ActivityDetailScreen({super.key, required this.activityId, this.justFinished = false});
  final String activityId;
  final bool justFinished;

  Future<void> _delete(BuildContext context, Activity a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Delete this run?')),
        content: Text(tr('The track and its share link are removed. This can\'t be undone.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: RL.red, minimumSize: const Size(64, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      context.read<ActivityStore>().delete(a.id);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ActivityStore>();
    final a = store.byId(activityId);
    final units = context.select<SettingsController, Units>((s) => s.units);
    if (a == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(tr('This run was deleted.'))));
    }
    final pts = [for (final p in a.points) p.latLng];
    final series = TrackMath.paceSeries(a.points);
    return Scaffold(
      appBar: AppBar(
        title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _delete(context, a);
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'delete', child: Row(children: [const Icon(Icons.delete_outline_rounded, color: RL.red), const SizedBox(width: 10), Text(tr('Delete run'))])),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [
          if (justFinished)
            FadeSlideIn(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: RLCard(
                  color: RL.green.withValues(alpha: 0.12),
                  child: InfoRow(icon: Icons.check_circle_rounded, color: RL.green, title: tr('Run saved'), subtitle: tr('Nice work! Here are your stats.')),
                ),
              ),
            ),
          FadeSlideIn(
            index: 0,
            child: SizedBox(height: 260, child: TrackMap(points: pts, interactive: true)),
          ),
          const SizedBox(height: 12),
          FadeSlideIn(
            index: 1,
            child: HeroPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${fmtDate(a.startedAt)} · ${fmtClock(a.startedAt)}',
                          style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12.5),
                        ),
                      ),
                      if (a.sample) Pill(tr('Sample'), color: Colors.white),
                      if (a.simulated && !a.sample) Pill(tr('Simulated GPS'), color: Colors.white),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Metric(
                    value: fmtDistance(a.distanceM, units, decimals: 2, withUnit: false),
                    unit: distUnit(units),
                    label: tr('Distance'),
                    size: 56,
                    color: Colors.white,
                    labelColor: Colors.white60,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: Metric(value: fmtDuration(a.movingS), label: tr('Moving time'), size: 20, color: Colors.white, labelColor: Colors.white60)),
                      Expanded(
                        child: Metric(
                          value: fmtPace(a.avgPaceSPerKm, units, withUnit: false),
                          unit: paceUnit(units),
                          label: tr('Avg pace'),
                          size: 20,
                          color: RL.amber,
                          labelColor: Colors.white60,
                        ),
                      ),
                      Expanded(
                        child: Metric(
                          value: a.bestKmS == null ? '–' : fmtPace(a.bestKmS, Units.km, withUnit: false),
                          label: tr('Best km'),
                          size: 20,
                          color: Colors.white,
                          labelColor: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr('{speed} average · {n} GPS points', {'speed': fmtSpeed(a.avgKph, units), 'n': fmtInt(a.points.length)}),
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FadeSlideIn(
            index: 2,
            child: RLCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionLabel(tr('Pace'), trailing: Text(tr('dashed = average'), style: TextStyle(fontSize: 11, color: muted(context)))),
                  PaceChart(series: series, units: units),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FadeSlideIn(
            index: 3,
            child: RLCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionLabel(tr('Km splits')),
                  KmSplitsList(splitsS: a.splitsS, units: units),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FadeSlideIn(
            index: 4,
            child: ShareLinkCard(
              url: a.shareUrl,
              privacy: a.privacy,
              message: tr('My run on RunLah: {dist} in {time}', {'dist': fmtDistance(a.distanceM, units), 'time': fmtDuration(a.movingS)}),
              onPrivacy: (p) {
                a.privacy = p;
                store.save(a);
              },
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<int>(
            valueListenable: store.queueSize,
            builder: (context, _, _) {
              final q = store.queuedFor(a.id);
              return InfoRow(
                icon: q == 0 ? Icons.cloud_done_rounded : Icons.cloud_upload_rounded,
                color: q == 0 ? RL.green : RL.amber,
                title: q == 0 ? tr('Synced') : tr('{n} points still queued', {'n': fmtInt(q)}),
                subtitle: q == 0 ? tr('Every point reached the server.') : tr('They upload automatically next time you\'re online.'),
              );
            },
          ),
        ],
      ),
    );
  }
}
