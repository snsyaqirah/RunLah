import 'dart:math' as math;

import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import 'race3d_mode.dart';

/// Builds the `init` message for the three.js scene
/// (`assets/three/race3d.html`, source in `three_src/`).
///
/// Everything is in local metres from the start line (x east, y north).
/// Runners carry just enough to be moved exactly like [RaceSim.distanceAt]:
/// start delay, the net time at each distance mark, and an optional DNF
/// distance. The km marks most runners share are sent once.
class Race3DPayload {
  Race3DPayload._();

  /// Most runners sent to the scene (the full field is ~11,760).
  static const maxRunners = 3000;

  /// Drone view plays the focus runner's finish ± this many seconds.
  static const droneHalfWindowS = 60.0;

  /// Everyone finishing within ± this many seconds of the focus runner is
  /// always sent, so the drone view shows the real crowd around them.
  static const droneIncludeS = 90.0;

  /// Route sample spacing in metres.
  static const routeStepM = 20.0;

  /// One flyover loop, in seconds (matches the JS scene).
  static const flyoverDurationS = 52.0;

  /// Kuala Lumpur sunrise in early October, as seconds of the day (07:10).
  static const sunriseSod = 7 * 3600 + 10 * 60;

  /// Default playback speed for each mode.
  static double defaultSpeed(Race3DMode mode) => switch (mode) {
        Race3DMode.replay => 60,
        Race3DMode.drone => 2,
        Race3DMode.flyover => 1,
      };

  /// Speed choices shown for each mode.
  static List<double> speeds(Race3DMode mode) => switch (mode) {
        Race3DMode.replay => const [30, 60, 120, 240],
        Race3DMode.drone => const [1, 2, 5, 10],
        Race3DMode.flyover => const [1],
      };

  /// Race time a runner crosses the finish (null for a DNF).
  static double? finishTime(RaceSim sim, int id) => sim.crossingTime(id, sim.race.distanceM);

  /// Playback window of the drone view: focus finish ± [droneHalfWindowS].
  static ({double start, double end}) droneWindow(RaceSim sim, int focusId) {
    final f = finishTime(sim, focusId) ?? _fallbackFinish(sim, focusId);
    return (start: math.max(0, f - droneHalfWindowS), end: f + droneHalfWindowS);
  }

  /// Timeline range for a mode (race time, or flyover seconds).
  static ({double start, double end}) range(RaceSim sim, Race3DMode mode, int focusId) => switch (mode) {
        Race3DMode.replay => (start: 0, end: sim.race.cutoffS.toDouble()),
        Race3DMode.drone => droneWindow(sim, focusId),
        Race3DMode.flyover => (start: 0, end: flyoverDurationS),
      };

  /// Where playback starts when the screen opens.
  ///
  /// Replay: [atRaceTime], else the live sim clock while the race is on,
  /// else 20 minutes before the focus runner finishes. Drone: focus finish
  /// − 60 s. Flyover: from the start line.
  static double initialTime(RaceSim sim, Race3DMode mode, {required int focusId, double? atRaceTime}) {
    final r = range(sim, mode, focusId);
    switch (mode) {
      case Race3DMode.flyover:
        return 0;
      case Race3DMode.drone:
        return (atRaceTime ?? r.start).clamp(r.start, r.end).toDouble();
      case Race3DMode.replay:
        if (atRaceTime != null) return atRaceTime.clamp(r.start, r.end).toDouble();
        if (sim.status == RaceStatus.live && sim.raceTime > 0) return sim.raceTime.clamp(r.start, r.end).toDouble();
        final f = finishTime(sim, focusId) ?? _fallbackFinish(sim, focusId);
        return (f - 20 * 60).clamp(r.start, r.end).toDouble();
    }
  }

  static double _fallbackFinish(RaceSim sim, int id) {
    // DNF: centre on the moment they stopped.
    final p = sim.plan(id);
    return p.startDelayS + (sim.netToDistance(id, p.dnfAtM ?? 0) ?? p.netS);
  }

  /// Picks which runners go to the scene: you, friends and the focus runner,
  /// everyone finishing within ±[droneIncludeS] of the focus runner, then an
  /// even sample of the rest of the field up to [cap].
  static List<int> sampleIds(RaceSim sim, {required int focusId, List<int>? friendIds, int cap = maxRunners}) {
    final friends = friendIds ?? sim.friendIds;
    final table = sim.crossingTable;
    final finish = table.times.last;
    final must = <int>[];
    final seen = <int>{};
    void add(int id) {
      if (seen.add(id)) must.add(id);
    }

    add(sim.youId);
    for (final f in friends) {
      add(f);
    }
    add(focusId);

    final focusFinish = finishTime(sim, focusId);
    if (focusFinish != null) {
      final near = <(int, double)>[];
      for (var i = 0; i < table.length; i++) {
        final t = finish[i];
        if (t.isNaN) continue;
        final gap = (t - focusFinish).abs();
        if (gap <= droneIncludeS) near.add((table.runners[i].id, gap));
      }
      near.sort((a, b) => a.$2.compareTo(b.$2));
      for (final n in near) {
        add(n.$1);
      }
    }

    if (must.length >= cap) return must.take(cap).toList();

    final rest = [for (final p in sim.participants) if (!seen.contains(p.id)) p.id];
    final slots = cap - must.length;
    final out = <int>[];
    if (rest.length <= slots) {
      out.addAll(rest);
    } else {
      final stride = rest.length / slots;
      for (var k = 0; k < slots; k++) {
        out.add(rest[(k * stride).floor()]);
      }
    }
    // Field first, special runners last (drawn on top).
    return [...out, ...must];
  }

  /// The full `init` message data.
  static Map<String, Object?> build(
    RaceSim sim, {
    required Race3DMode mode,
    int? focusId,
    List<int>? friendIds,
    double? t0,
    double? speed,
    int? followId,
    int cap = maxRunners,
    Map<String, String> labels = const {},
    Map<String, String> strings = const {},
  }) {
    final race = sim.race;
    final route = race.route;
    final focus = focusId ?? sim.youId;
    final friends = friendIds ?? sim.friendIds;
    final focusCat = sim.participant(focus).categoryId;
    final defaultMarks = RunnerPlan.kmMarks(race.distanceM);

    // Route, sampled every ~20 m of race distance.
    final n = (race.distanceM / routeStepM).ceil();
    final rx = <num>[], ry = <num>[], rd = <num>[];
    for (var i = 0; i <= n; i++) {
      final d = race.distanceM * i / n;
      final p = route.toLocal(route.at(d));
      rx.add(_r1(p.x));
      ry.add(_r1(p.y));
      rd.add(_r1(d));
    }

    final ids = sampleIds(sim, focusId: focus, friendIds: friends, cap: cap);
    final finishTimes = sim.crossingTable.times.last;
    final focusFinish = finishTime(sim, focus);
    final runners = <Map<String, Object?>>[];
    for (final id in ids) {
      final p = sim.participant(id);
      final plan = sim.plan(id);
      final cls = id == sim.youId
          ? 'you'
          : friends.contains(id)
              ? 'friend'
              : p.categoryId == focusCat
                  ? 'cat'
                  : 'field';
      // Runners near the focus finish (drone view) keep 0.1 s precision,
      // the rest of the field rounds to whole seconds to keep the payload small.
      final idx = sim.crossingTable.indexOf[id];
      final ft = idx == null ? double.nan : finishTimes[idx];
      final precise = cls != 'field' || (focusFinish != null && !ft.isNaN && (ft - focusFinish).abs() <= droneIncludeS + 30);
      final sameMarks = _sameList(plan.marksM, defaultMarks);
      runners.add({
        'id': id,
        'startDelay': _r1(plan.startDelayS),
        if (!sameMarks) 'marks': [for (final m in plan.marksM) _r1(m)],
        'cum': [for (final c in plan.cumS) precise ? _r1(c) : c.round()],
        'g': p.gender.code,
        'cls': cls,
        if (plan.dnfAtM != null) 'dnf': _r1(plan.dnfAtM!),
      });
    }

    final window = droneWindow(sim, focus);
    final gun = race.scheduledStart;
    return {
      'v': 1,
      'mode': mode.name,
      't0': _r1(t0 ?? initialTime(sim, mode, focusId: focus)),
      'speed': speed ?? defaultSpeed(mode),
      'distance': race.distanceM,
      'cutoff': race.cutoffS,
      'gunSod': gun.hour * 3600 + gun.minute * 60 + gun.second,
      'sunriseSod': sunriseSod,
      'flyDuration': flyoverDurationS,
      'youId': sim.youId,
      'friendIds': friends,
      'focusId': focus,
      'followId': followId,
      'finishT': focusFinish == null ? null : _r1(focusFinish),
      'window': [_r1(window.start), _r1(window.end)],
      'total': sim.participants.length,
      'route': {'x': rx, 'y': ry, 'd': rd},
      'checkpoints': [
        for (final c in race.checkpoints)
          () {
            final p = route.toLocal(c.location);
            return {
              'd': _r1(c.distanceM),
              'x': _r1(p.x),
              'y': _r1(p.y),
              'name': c.name,
              'type': c.type.name,
              'label': c.shortLabel,
            };
          }(),
      ],
      'landmarks': [
        for (final l in race.landmarks)
          () {
            final p = route.toLocal(l.location);
            return {'name': l.name, 'x': _r1(p.x), 'y': _r1(p.y), 'h': _r1(l.heightM), 'kind': l.kind};
          }(),
      ],
      'marks': [for (final m in defaultMarks) _r1(m)],
      'runners': runners,
      'labels': labels,
      'strings': strings,
    };
  }

  /// Rounds to 0.1 and drops a trailing ".0" in the JSON (ints encode shorter).
  static num _r1(double v) {
    final r = (v * 10).round();
    return r % 10 == 0 ? r ~/ 10 : r / 10;
  }

  static bool _sameList(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 1e-6) return false;
    }
    return true;
  }
}
