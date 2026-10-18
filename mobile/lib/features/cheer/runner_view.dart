import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../data/insights/insights_engine.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';

/// Everything a cheer card needs about one runner at race time [t]. Cheap
/// (a few binary searches), so it is fine to build on every clock tick.
class RunnerNow {
  RunnerNow._({
    required this.participant,
    required this.state,
    required this.distanceM,
    required this.estimated,
    required this.paceSPerKm,
    required this.finishEta,
    required this.elapsedS,
    required this.lastCp,
    required this.lastCpTime,
    required this.finishNetS,
    required this.position,
    required this.raceDistanceM,
  });

  final Participant participant;
  final RunnerState state;

  /// Race distance covered: live GPS, or estimated from checkpoint passes
  /// for runners without a phone/watch.
  final double distanceM;
  final bool estimated;
  final double? paceSPerKm;

  /// Race time (since gun) of the predicted / actual finish.
  final double? finishEta;

  /// Net seconds since crossing the start mat.
  final double elapsedS;

  /// Last checkpoint crossed (-1 = none) and the race time of that crossing.
  final int lastCp;
  final double? lastCpTime;
  final double? finishNetS;
  final LatLng position;
  final double raceDistanceM;

  double get fraction => (distanceM / raceDistanceM).clamp(0.0, 1.0);
  bool get onCourse => state == RunnerState.running;

  static RunnerNow of(RaceSim sim, InsightsSnapshot snap, int id, double t) {
    final p = sim.participant(id);
    final race = sim.race;
    final state = sim.stateAt(id, t);
    final table = sim.crossingTable;
    final i = table.indexOf[id]!;
    var k = -1;
    for (var c = 0; c < race.checkpoints.length; c++) {
      final x = table.times[c][i];
      if (x.isNaN || x > t) break;
      k = c;
    }
    final estimated = !p.hasGps;
    double d;
    switch (state) {
      case RunnerState.notStarted:
        d = 0;
      case RunnerState.finished:
        d = race.distanceM;
      case RunnerState.running || RunnerState.dnf:
        d = estimated ? snap.estimatedDistanceAt(id, t) : sim.distanceAt(id, t);
        if (estimated && k >= 0) {
          // Never behind the last checkpoint they were seen at.
          d = d < race.checkpoints[k].distanceM ? race.checkpoints[k].distanceM : d;
        }
    }
    double? pace;
    if (state == RunnerState.running) {
      if (!estimated) {
        pace = sim.paceAt(id, t);
      } else if (k >= 1) {
        final a = race.checkpoints[k - 1], b = race.checkpoints[k];
        pace = (table.times[k][i] - table.times[k - 1][i]) / ((b.distanceM - a.distanceM) / 1000);
      }
    } else if (state == RunnerState.finished) {
      pace = sim.plan(id).netS / (race.distanceM / 1000);
    }
    final finished = state == RunnerState.finished;
    return RunnerNow._(
      participant: p,
      state: state,
      distanceM: d,
      estimated: estimated && state == RunnerState.running,
      paceSPerKm: pace,
      finishEta: switch (state) {
        RunnerState.dnf => null,
        RunnerState.finished => sim.crossingTime(id, race.distanceM),
        _ => sim.etaToDistance(id, race.distanceM, t),
      },
      elapsedS: sim.elapsedAt(id, t),
      lastCp: k,
      lastCpTime: k >= 0 ? table.times[k][i] : null,
      finishNetS: finished ? sim.plan(id).netS : null,
      position: race.route.at(d),
      raceDistanceM: race.distanceM,
    );
  }
}

String stateLabel(RunnerState s) => switch (s) {
      RunnerState.notStarted => tr('Not started'),
      RunnerState.running => tr('Running'),
      RunnerState.finished => tr('Finished'),
      RunnerState.dnf => tr('DNF'),
    };

Color stateColor(RunnerState s) => switch (s) {
      RunnerState.notStarted => RL.slate,
      RunnerState.running => RL.green,
      RunnerState.finished => RL.amber,
      RunnerState.dnf => RL.red,
    };

IconData stateIcon(RunnerState s) => switch (s) {
      RunnerState.notStarted => Icons.hourglass_top_rounded,
      RunnerState.running => Icons.directions_run_rounded,
      RunnerState.finished => Icons.sports_score_rounded,
      RunnerState.dnf => Icons.do_not_disturb_on_rounded,
    };

/// Checkpoint label with translated Start / Finish.
String cpLabel(Checkpoint c) => switch (c.type) {
      CheckpointType.start => tr('Start'),
      CheckpointType.finish => tr('Finish'),
      CheckpointType.split => c.shortLabel,
    };

/// Friendly short name ("Syaqirah"), or "#20417" for bib-only runners.
String shortName(Participant p) => p.resultsName == ResultsName.bibOnly ? '#${p.bib}' : p.firstName;

String initials(Participant p) {
  if (p.resultsName == ResultsName.bibOnly) return '#';
  final words = p.name.split(' ').where((w) => w.isNotEmpty && !const {'bin', 'binti', 'a/l', 'a/p'}.contains(w.toLowerCase())).toList();
  final first = p.firstName;
  final last = words.length > 1 && words.last != first ? words.last : '';
  return (first.isEmpty ? '?' : first[0]).toUpperCase() + (last.isEmpty ? '' : last[0].toUpperCase());
}

/// Stable colour per runner: you = amber, followed friends get the series
/// colours in follow order, everyone else a colour from their id.
Color runnerColor(RaceSim sim, List<int> followed, int id) {
  if (id == sim.youId) return RL.series[0];
  final i = followed.indexOf(id);
  if (i >= 0) return RL.series[1 + i % (RL.series.length - 1)];
  return RL.series[1 + id % (RL.series.length - 1)];
}

/// Where a finished runner meets their supporters, near the finish.
class MeetingPoint {
  const MeetingPoint(this.code, this.name, this.location);
  final String code;
  final String name;
  final LatLng location;

  static const all = [
    MeetingPoint('A', 'Sultan Abdul Samad clock tower', LatLng(3.14855, 101.69465)),
    MeetingPoint('B', 'Dataran Merdeka fountain', LatLng(3.14745, 101.69410)),
    MeetingPoint('C', 'Royal Selangor Club steps', LatLng(3.14905, 101.69300)),
    MeetingPoint('D', 'KL City Gallery', LatLng(3.14790, 101.69505)),
  ];

  /// Demo: pick one per runner. In production the runner picks it in the app.
  static MeetingPoint forRunner(Participant p) => all[(int.tryParse(p.bib) ?? p.id) % all.length];
}
