import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/l10n/i18n.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/course_map.dart';
import '../../../data/app_state.dart';
import '../../../data/models.dart';
import '../../../data/sim/race_sim.dart';
import '../../home/widgets/motion.dart';
import '../../home/widgets/route_painter.dart';
import '../organizer_session.dart';

const _reasons = ['Twisted ankle', 'Chest pain', 'Fainted near water station', 'Cramp, cannot continue', 'Feeling dizzy (heat)'];

/// SOS queue: alerts from runners' SOS button with location, newest first.
class SosTab extends StatelessWidget {
  const SosTab({super.key});

  @override
  Widget build(BuildContext context) {
    final sim = context.watch<RaceSim>();
    final session = context.watch<OrganizerSession>();
    final alerts = sim.sosAlerts;
    int count(String s) => alerts.where((a) => a.status == s).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Row(
          children: [
            Expanded(child: _CountChip(n: count('open'), label: tr('Open'), color: RL.red)),
            const SizedBox(width: 8),
            Expanded(child: _CountChip(n: count('acknowledged'), label: tr('Acknowledged'), color: RL.amber)),
            const SizedBox(width: 8),
            Expanded(child: _CountChip(n: count('closed'), label: tr('Closed'), color: RL.green)),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: sim.status == RaceStatus.live ? () => _simulate(context, sim) : null,
          icon: const Icon(Icons.add_alert_rounded),
          label: Text(tr('Simulate an SOS')),
        ),
        const SizedBox(height: 14),
        if (alerts.isEmpty)
          const _Empty()
        else
          for (final a in alerts)
            Padding(
              key: ValueKey('sos-${a.id}'),
              padding: const EdgeInsets.only(bottom: 12),
              child: FadeSlideIn(offset: const Offset(0, -0.12), child: _SosCard(alert: a, medicTeam: session.dispatched[a.id])),
            ),
      ],
    );
  }

  void _simulate(BuildContext context, RaceSim sim) {
    final rng = math.Random();
    final t = sim.raceTime;
    for (var tries = 0; tries < 200; tries++) {
      final p = sim.participants[rng.nextInt(sim.participants.length)];
      if (sim.stateAt(p.id, t) == RunnerState.running) {
        sim.raiseSos(p.id, _reasons[rng.nextInt(_reasons.length)]);
        return;
      }
    }
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.n, required this.label, required this.color});
  final int n;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            CountUpText(n, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => RLCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: RL.green.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.health_and_safety_rounded, color: RL.green, size: 32),
            ),
            const SizedBox(height: 12),
            Text(tr('No SOS alerts'), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: ink(context))),
            const SizedBox(height: 6),
            Text(
              tr('A runner\'s SOS button sends their live location here. In the demo, alerts arrive at 45:00 and 1:41:40 race time.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: muted(context), height: 1.35),
            ),
          ],
        ),
      );
}

class _SosCard extends StatelessWidget {
  const _SosCard({required this.alert, required this.medicTeam});
  final SosAlert alert;
  final int? medicTeam;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final session = context.read<OrganizerSession>();
    final units = context.select<SettingsController, Units>((s) => s.units);
    final p = sim.participant(alert.participantId);
    final race = sim.race;
    final d = sim.distanceAt(p.id, alert.raceTimeS);
    final cp = race.checkpoints.reduce((a, c) => (c.distanceM - d).abs() < (a.distanceM - d).abs() ? c : a);
    final (label, color) = switch (alert.status) {
      'open' => (tr('Open'), RL.red),
      'acknowledged' => (tr('Acknowledged'), RL.amber),
      _ => (tr('Closed'), RL.green),
    };
    final closed = alert.status == 'closed';
    return RLCard(
      color: alert.status == 'open' ? RL.red.withValues(alpha: 0.06) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _showMap(context, race, alert, p),
                child: Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(color: RL.navy, borderRadius: BorderRadius.circular(14)),
                  child: RouteSilhouette(
                    route: race.route,
                    color: Colors.white.withValues(alpha: 0.55),
                    strokeWidth: 1.6,
                    padding: 9,
                    pins: [RoutePin(alert.location, closed ? RL.green : RL.red, radius: 5, halo: !closed)],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Pill(label, color: color, filled: alert.status == 'open', icon: Icons.sos_rounded),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ValueListenableBuilder<double>(
                            valueListenable: sim.clock,
                            builder: (_, t, _) => Text(
                              tr('{m} min ago', {'m': math.max(0, ((t - alert.raceTimeS) / 60).floor())}),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 11.5, color: muted(context), fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5, color: ink(context))),
                    Text(
                      tr('Bib {bib} · {cat}', {'bib': p.bib, 'cat': race.categoryById(p.categoryId).name}),
                      style: TextStyle(fontSize: 12.5, color: muted(context), fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.report_rounded, size: 16, color: RL.red),
                        const SizedBox(width: 4),
                        Expanded(child: Text(tr(alert.reason), style: TextStyle(fontWeight: FontWeight.w800, color: ink(context), fontSize: 13))),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _Meta(Icons.place_rounded, tr('{d} · near {cp}', {'d': fmtDistance(d, units), 'cp': cp.name})),
              _Meta(Icons.schedule_rounded, tr('{wall} · race {t}', {'wall': fmtClockSec(sim.wallClockAt(alert.raceTimeS)), 't': fmtDuration(alert.raceTimeS, forceHours: true)})),
              if (medicTeam != null) _Meta(Icons.medical_services_rounded, tr('Medic team {n} dispatched', {'n': medicTeam}), color: RL.teal),
            ],
          ),
          if (!closed) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (alert.status == 'open') ...[
                  Expanded(
                    child: OutlinedButton(
                      key: Key('sos-ack-${alert.id}'),
                      onPressed: () => sim.updateSos(alert, 'acknowledged'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 6)),
                      child: Text(tr('Acknowledge'), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (medicTeam == null) ...[
                  Expanded(
                    child: FilledButton(
                      key: Key('sos-medic-${alert.id}'),
                      onPressed: () {
                        session.dispatchMedic(alert);
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
                          content: Text(tr('Medic team {n} on the way to bib {bib}', {'n': session.dispatched[alert.id], 'bib': p.bib})),
                          behavior: SnackBarBehavior.floating,
                        ));
                      },
                      style: FilledButton.styleFrom(backgroundColor: RL.red, minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 6)),
                      child: Text(tr('Dispatch medic'), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton(
                    key: Key('sos-close-${alert.id}'),
                    onPressed: () => sim.updateSos(alert, 'closed'),
                    style: OutlinedButton.styleFrom(foregroundColor: RL.green, minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 6)),
                    child: Text(tr('Close'), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static void _showMap(BuildContext context, Race race, SosAlert alert, Participant p) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RL.radius)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 360,
              child: CourseMap(
                race: race,
                showLandmarks: false,
                dots: [MapDot(point: alert.location, color: RL.red, label: 'SOS · ${p.bib}', icon: Icons.sos_rounded, size: 22, pulse: alert.status == 'open')],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
              child: Row(
                children: [
                  Expanded(child: Text('${p.name} · ${tr(alert.reason)}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: ink(context)))),
                  TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Close'))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text, {this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color ?? muted(context)),
          const SizedBox(width: 4),
          Flexible(child: Text(text, style: TextStyle(fontSize: 12, color: color ?? muted(context), fontWeight: FontWeight.w600))),
        ],
      );
}
