import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import '../../services/tracking_service.dart' show sayDuration;
import '../../services/voice_service.dart';

/// Where "you" are in the race-day flow.
enum RunPhase { preRace, waitingStart, running, finished, dnf }

/// The expensive live numbers (they scan all 11,760 runners), refreshed at
/// most once a second.
@immutable
class LiveHeavy {
  const LiveHeavy({required this.place, required this.passed, required this.passedBy, required this.raceTime});
  final int place;
  final int passed;
  final int passedBy;
  final double raceTime;
}

/// Follows "you" through the simulated race (the demo stand-in for your
/// phone's GPS on race day) and drives the Race day screen:
///
/// * [phase] changes only when your state changes (pre-race → start → run → finish).
/// * [mapTick] is the race clock throttled to ~2.5 Hz for the map and the
///   projection cards, so big widgets don't rebuild on every 100 ms tick.
/// * [heavy] holds live place + overtakes, recomputed ≤1 Hz and only while
///   the Run tab is visible.
/// * The voice coach announces each km (≤1 line every 3 s of real time at
///   high demo speeds) and reads cheers aloud.
/// * [celebrate] flips on when you cross the finish while the app is open.
class RaceRunController extends ChangeNotifier {
  RaceRunController({required this.sim, required this.settings, required this.voice}) {
    final t = sim.raceTime;
    _lastT = t;
    phase = ValueNotifier(_phaseAt(t));
    mapTick = ValueNotifier(t);
    _announcedKm = _kmAt(t);
    kmDone = ValueNotifier(_announcedKm);
    sim.clock.addListener(_onClock);
    sim.addListener(_onSim);
    _sub = sim.events.listen(_onEvent);
  }

  final RaceSim sim;
  final SettingsController settings;
  final VoiceService voice;
  late final StreamSubscription<SimEvent> _sub;

  int get you => sim.youId;

  late final ValueNotifier<RunPhase> phase;
  late final ValueNotifier<double> mapTick;
  late final ValueNotifier<int> kmDone;
  final ValueNotifier<LiveHeavy?> heavy = ValueNotifier(null);
  final ValueNotifier<bool> celebrate = ValueNotifier(false);

  /// Cheer that just arrived (for the pop-in animation).
  final ValueNotifier<CheerMessage?> latestCheer = ValueNotifier(null);

  double _lastT = 0;
  int _announcedKm = 0;
  RaceStatus _lastStatus = RaceStatus.preRace;
  DateTime _lastHeavyAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastMapAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSpoken = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _heavyTimer;
  Timer? _mapTimer;
  bool _visible = false;
  bool _heavyDirty = true;
  bool? _wasBehind;
  bool _disposed = false;

  /// Set by the screen from `Visibility.of(context)` (IndexedStack tabs).
  set visible(bool v) {
    if (v == _visible) return;
    _visible = v;
    if (v && _heavyDirty) scheduleMicrotask(() => _scheduleHeavy(force: true));
  }

  double get finishRaceTime => sim.crossingTime(you, sim.race.distanceM) ?? double.infinity;
  double get startDelayS => sim.plan(you).startDelayS;

  /// Distance covered at race time [t] (metres).
  double distanceAt(double t) => sim.status == RaceStatus.preRace ? 0 : sim.distanceAt(you, t);

  /// Completed km durations up to race time [t].
  List<double> splitsAt(double t) {
    final out = <double>[];
    final full = (sim.race.distanceM / 1000).floor();
    for (var k = 1; k <= full; k++) {
      final a = sim.crossingTime(you, (k - 1) * 1000.0), b = sim.crossingTime(you, k * 1000.0);
      if (a == null || b == null || b > t) break;
      out.add(b - a);
    }
    return out;
  }

  /// Next checkpoint after distance [d] (null past the last one).
  Checkpoint? nextCheckpoint(double d) {
    for (final c in sim.race.checkpoints) {
      if (c.distanceM > d + 1) return c;
    }
    return null;
  }

  RunPhase _phaseAt(double t) {
    if (sim.status == RaceStatus.preRace) return RunPhase.preRace;
    return switch (sim.stateAt(you, t)) {
      RunnerState.notStarted => RunPhase.waitingStart,
      RunnerState.running => RunPhase.running,
      RunnerState.finished => RunPhase.finished,
      RunnerState.dnf => RunPhase.dnf,
    };
  }

  int _kmAt(double t) => sim.status == RaceStatus.preRace ? 0 : (sim.distanceAt(you, t) / 1000).floor();

  void _onSim() {
    if (sim.status != _lastStatus) {
      _lastStatus = sim.status;
      _onClock();
    }
  }

  void _onClock() {
    if (_disposed) return;
    final t = sim.raceTime;
    final prev = phase.value;
    final next = _phaseAt(t);

    if (next == RunPhase.preRace && prev != RunPhase.preRace) {
      // Demo reset.
      celebrate.value = false;
      heavy.value = null;
      latestCheer.value = null;
      _wasBehind = null;
    }
    if (next != prev) {
      if (next == RunPhase.finished && (prev == RunPhase.running || prev == RunPhase.waitingStart)) {
        celebrate.value = true;
        _say(tr('You finished! Net time {time}.', {'time': sayDuration(sim.plan(you).netS)}), force: true);
      }
      if (next == RunPhase.running && prev == RunPhase.waitingStart && t - startDelayS < 30) {
        _say(tr('You crossed the start line. Your net time is running. Enjoy the race!'));
      }
      phase.value = next;
    }

    // Kilometre splits + voice coach.
    final km = _kmAt(t);
    if (km != _announcedKm) {
      final bigJump = (t - _lastT).abs() > 900 || km - _announcedKm > 2;
      if (km > _announcedKm && !bigJump && next == RunPhase.running) _announceKm(km, t);
      _announcedKm = km;
      kmDone.value = km;
    }

    _throttleMap(t);
    _scheduleHeavy();
    _lastT = t;
  }

  void _announceKm(int km, double t) {
    if (!settings.voiceCoach) return;
    final splits = splitsAt(t);
    if (splits.isEmpty) return;
    final proj = sim.projectedFinish(you, t);
    final target = settings.targetTimeS.toDouble();
    final behind = proj != null && proj > target;
    var line = tr('Kilometre {km}. Split {split}.', {'km': km, 'split': sayDuration(splits.last)});
    if (proj != null) {
      line += ' ${behind ? tr('Projected finish {time}, behind your target.', {'time': sayDuration(proj)}) : tr('Projected finish {time}, on target.', {'time': sayDuration(proj)})}';
    }
    _wasBehind = behind;
    _say(line);
  }

  void _say(String text, {bool force = false}) {
    final now = DateTime.now();
    // At 30–120× demo speed kilometres fly past: at most one line every 3 s.
    if (!force && now.difference(_lastSpoken) < const Duration(seconds: 3)) return;
    _lastSpoken = now;
    voice.speak(text);
  }

  /// Projected finish crossed the target since the last km announcement.
  bool? get wasBehindTarget => _wasBehind;

  void _onEvent(SimEvent e) {
    if (_disposed) return;
    if (e is CheerReceived) {
      latestCheer.value = e.message;
      notifyListeners();
      if (settings.readCheers && sim.status == RaceStatus.live) {
        _say(tr('Cheer from {name}: {body}', {'name': e.message.from, 'body': e.message.body}), force: true);
      }
    }
  }

  void _throttleMap(double t) {
    final now = DateTime.now();
    final since = now.difference(_lastMapAt);
    const gap = Duration(milliseconds: 400);
    if (since >= gap) {
      _lastMapAt = now;
      mapTick.value = t;
    } else {
      _mapTimer ??= Timer(gap - since, () {
        _mapTimer = null;
        if (_disposed) return;
        _lastMapAt = DateTime.now();
        mapTick.value = sim.raceTime;
      });
    }
  }

  void _scheduleHeavy({bool force = false}) {
    if (_disposed) return;
    final ph = phase.value;
    if (ph == RunPhase.preRace || ph == RunPhase.waitingStart) {
      heavy.value = null;
      _heavyDirty = false;
      return;
    }
    if (!_visible) {
      _heavyDirty = true;
      return;
    }
    final since = DateTime.now().difference(_lastHeavyAt);
    if (force || since >= const Duration(seconds: 1)) {
      _computeHeavy();
    } else {
      _heavyTimer ??= Timer(const Duration(seconds: 1) - since, () {
        _heavyTimer = null;
        _computeHeavy();
      });
    }
  }

  void _computeHeavy() {
    if (_disposed) return;
    _lastHeavyAt = DateTime.now();
    _heavyDirty = false;
    final ph = phase.value;
    if (ph == RunPhase.preRace || ph == RunPhase.waitingStart) {
      heavy.value = null;
      return;
    }
    // After the finish, freeze the numbers at your finish moment.
    final t = math.min(sim.raceTime, finishRaceTime);
    final o = sim.liveOvertakes(you, 0, t);
    heavy.value = LiveHeavy(place: sim.livePlace(you, t), passed: o.passed, passedBy: o.passedBy, raceTime: t);
  }

  /// Runners you passed formatted for the counter.
  static String passedLabel(int n) => fmtInt(n);

  @override
  void dispose() {
    _disposed = true;
    _heavyTimer?.cancel();
    _mapTimer?.cancel();
    sim.clock.removeListener(_onClock);
    sim.removeListener(_onSim);
    _sub.cancel();
    phase.dispose();
    mapTick.dispose();
    kmDone.dispose();
    heavy.dispose();
    celebrate.dispose();
    latestCheer.dispose();
    super.dispose();
  }
}
