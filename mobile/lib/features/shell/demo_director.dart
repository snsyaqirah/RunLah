import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';

/// Floating race clock. Tap it to open the demo director: fire the gun,
/// change speed, jump to the interesting moments, publish results.
/// Only exists because there's no real race happening while you demo.
class DemoDirectorButton extends StatelessWidget {
  const DemoDirectorButton({super.key});

  @override
  Widget build(BuildContext context) {
    final sim = context.watch<RaceSim>();
    return Positioned(
      right: 12,
      bottom: 12,
      child: SafeArea(
        child: Material(
          color: RL.navy,
          elevation: 6,
          shadowColor: Colors.black45,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => showDemoDirector(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StatusDot(status: sim.status, playing: sim.playing),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<double>(
                    valueListenable: sim.clock,
                    builder: (_, t, _) => Text(
                      sim.status == RaceStatus.preRace ? '${tr('Gun in')} ${fmtDuration(-t)}' : fmtDuration(t, forceHours: true),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                  ),
                  if (sim.status != RaceStatus.preRace) ...[
                    const SizedBox(width: 6),
                    Text('${sim.speed.round()}×', style: const TextStyle(color: RL.amber, fontWeight: FontWeight.w800, fontSize: 12)),
                  ],
                  const SizedBox(width: 6),
                  const Icon(Icons.tune_rounded, color: Colors.white70, size: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status, required this.playing});
  final RaceStatus status;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      RaceStatus.preRace => RL.amber,
      RaceStatus.live => playing ? const Color(0xFF34D399) : Colors.white54,
      RaceStatus.closed => Colors.white54,
    };
    return Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
  }
}

Future<void> showDemoDirector(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _DirectorSheet(),
    );

class _DirectorSheet extends StatelessWidget {
  const _DirectorSheet();

  @override
  Widget build(BuildContext context) {
    final sim = context.watch<RaceSim>();
    final race = sim.race;
    final you = sim.youId;
    final half = race.checkpoints[race.checkpointNear(0.5)].distanceM;

    double firstFinish(Gender g) {
      var best = double.infinity;
      final table = sim.crossingTable;
      for (var i = 0; i < table.length; i++) {
        final f = table.times.last[i];
        if (!f.isNaN && table.runners[i].gender == g && f < best) best = f;
      }
      return best;
    }

    final jumps = <(String, IconData, double)>[
      (tr('Gun'), Icons.flag_rounded, 0),
      (tr('You at 5K'), Icons.directions_run_rounded, sim.crossingTime(you, 5000)!),
      (tr('You at halfway'), Icons.directions_run_rounded, sim.crossingTime(you, half)!),
      (tr('Male winner finishes'), Icons.emoji_events_rounded, firstFinish(Gender.m) + 1),
      (tr('Female winner finishes'), Icons.emoji_events_rounded, firstFinish(Gender.f) + 1),
      (tr('You finish'), Icons.sports_score_rounded, sim.crossingTime(you, race.distanceM)! + 1),
      (tr('{name} finishes', {'name': sim.participant(sim.friendIds[1]).firstName}), Icons.sports_score_rounded, sim.crossingTime(sim.friendIds[1], race.distanceM)! + 1),
      (tr('{name} finishes', {'name': sim.participant(sim.friendIds[0]).firstName}), Icons.sports_score_rounded, sim.crossingTime(sim.friendIds[0], race.distanceM)! + 1),
      (tr('Cutoff'), Icons.lock_clock_rounded, race.cutoffS.toDouble()),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Demo director'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink(context))),
                      Text(tr('Simulated race day: 11,760 runners on the KL course'), style: TextStyle(color: muted(context), fontSize: 12.5)),
                    ],
                  ),
                ),
                Pill(
                  switch (sim.status) {
                    RaceStatus.preRace => tr('Pre-race'),
                    RaceStatus.live => tr('Live'),
                    RaceStatus.closed => sim.official ? tr('Official') : tr('Closed'),
                  },
                  color: sim.status == RaceStatus.live ? RL.green : RL.amber,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<double>(
              valueListenable: sim.clock,
              builder: (_, t, _) => Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  Text(
                    sim.status == RaceStatus.preRace ? '−${fmtDuration(-t, forceHours: true)}' : fmtDuration(t, forceHours: true),
                    style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: ink(context), fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, top: 4),
                    child: Text('${tr('race time')} · ${fmtClockSec(sim.now)}', style: TextStyle(color: muted(context))),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (sim.status == RaceStatus.preRace)
              FilledButton.icon(
                onPressed: sim.fireGun,
                icon: const Icon(Icons.flag_rounded),
                label: Text(tr('Fire the gun')),
              )
            else
              Row(
                children: [
                  IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: RL.navy, minimumSize: const Size(52, 52)),
                    onPressed: sim.playing ? sim.pause : sim.play,
                    icon: Icon(sim.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SegmentedButton<double>(
                      showSelectedIcon: false,
                      segments: [for (final s in RaceSim.speeds) ButtonSegment(value: s, label: Text('${s.round()}×'))],
                      selected: {sim.speed},
                      onSelectionChanged: (v) => sim.setSpeed(v.first),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            SectionLabel(tr('Jump to')),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, icon, t) in jumps)
                  ActionChip(
                    avatar: Icon(icon, size: 16),
                    label: Text(label),
                    onPressed: () => sim.jumpTo(t),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      openOrganizer(context);
                    },
                    icon: const Icon(Icons.admin_panel_settings_rounded),
                    label: Text(tr('Organizer')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: sim.official ? null : () => sim.publishOfficial(),
                    icon: const Icon(Icons.verified_rounded),
                    label: Text(tr('Publish results')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: sim.reset,
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(tr('Reset demo')),
            ),
          ],
        ),
      ),
    );
  }
}
