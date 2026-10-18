import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models.dart';
import '../../data/sim/race_sim.dart';

/// One look at the whole field at race time [t].
class FieldSnapshot {
  const FieldSnapshot({
    required this.t,
    required this.status,
    required this.notStarted,
    required this.running,
    required this.finished,
    required this.dnf,
    required this.density,
    this.yourPlace,
    this.finishersPerMin = const [],
  });

  final double t;
  final RaceStatus status;
  final int notStarted, running, finished, dnf;

  /// Runners on course per [FieldTicker.binM] metres of course.
  final List<int> density;

  /// "You" by distance covered (1 = leading), when requested.
  final int? yourPlace;

  /// Finishers per minute for the last [FieldTicker.rateWindowMin] minutes.
  final List<int> finishersPerMin;

  int get total => notStarted + running + finished + dnf;
  int get maxDensity => density.isEmpty ? 0 : density.reduce((a, b) => a > b ? a : b);
}

/// Throttled field statistics. [RaceSim.fieldStats] scans all 11,760
/// runners, so this recomputes at most once per [minInterval] of real time
/// (status changes recompute at once), never per frame.
class FieldTicker extends ChangeNotifier {
  FieldTicker(this.sim, {this.withPlace = false, this.withFinishRate = false, this.minInterval = const Duration(seconds: 1)}) {
    if (withFinishRate) {
      final f = sim.crossingTable.times.last;
      final list = <double>[for (final v in f) if (!v.isNaN) v]..sort();
      _finishSorted = Float64List.fromList(list);
    }
    _compute();
    sim.clock.addListener(_onClock);
    sim.addListener(_onSim);
  }

  static const double binM = 500;
  static const int rateWindowMin = 40;

  final RaceSim sim;
  final bool withPlace;
  final bool withFinishRate;
  final Duration minInterval;

  late FieldSnapshot _snap;
  FieldSnapshot get snapshot => _snap;

  Float64List _finishSorted = Float64List(0);
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _pending;
  bool _disposed = false;

  bool _active = true;

  /// Pause recomputing while the owner isn't visible (e.g. another tab).
  /// Re-activating refreshes on the next microtask (never during a build).
  set active(bool v) {
    if (v == _active) return;
    _active = v;
    if (v) {
      Future.microtask(() {
        if (!_disposed && _active) _request();
      });
    }
  }

  void _onClock() {
    if (!_active) return;
    if ((sim.raceTime - _snap.t).abs() < 0.5 && sim.status == _snap.status) return;
    _request();
  }

  void _onSim() {
    if (!_active) return;
    if (sim.status != _snap.status) {
      _pending?.cancel();
      _pending = null;
      _compute();
    } else if ((sim.raceTime - _snap.t).abs() > 1) {
      _request();
    }
  }

  void _request() {
    final since = DateTime.now().difference(_last);
    if (since >= minInterval) {
      _compute();
    } else {
      _pending ??= Timer(minInterval - since, () {
        _pending = null;
        if (!_disposed) _compute();
      });
    }
  }

  /// Count of finish times <= [t] (binary search).
  int _finishedBy(double t) {
    var lo = 0, hi = _finishSorted.length;
    while (lo < hi) {
      final m = (lo + hi) >> 1;
      if (_finishSorted[m] <= t) {
        lo = m + 1;
      } else {
        hi = m;
      }
    }
    return lo;
  }

  void _compute() {
    final t = sim.raceTime;
    final s = sim.fieldStats(t, binM: binM);
    int? place;
    if (withPlace && sim.status != RaceStatus.preRace && sim.stateAt(sim.youId, t) != RunnerState.notStarted) {
      place = sim.livePlace(sim.youId, t);
    }
    var rate = const <int>[];
    if (withFinishRate && sim.status != RaceStatus.preRace) {
      rate = [
        for (var m = rateWindowMin; m > 0; m--) _finishedBy(t - (m - 1) * 60) - _finishedBy(t - m * 60),
      ];
    }
    _snap = FieldSnapshot(
      t: t,
      status: sim.status,
      notStarted: s.notStarted,
      running: s.running,
      finished: s.finished,
      dnf: s.dnf,
      density: s.density,
      yourPlace: place,
      finishersPerMin: rate,
    );
    _last = DateTime.now();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pending?.cancel();
    sim.clock.removeListener(_onClock);
    sim.removeListener(_onSim);
    super.dispose();
  }
}
