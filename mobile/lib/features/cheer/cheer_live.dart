import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:latlong2/latlong.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import '../../services/notification_center.dart';

/// Supporter preference: also show "You" (the runner on this phone) next to
/// the people you follow.
bool cheerShowMe(SettingsController s) => s.prefs.getBool('cheerShowMe') ?? true;
void setCheerShowMe(SettingsController s, bool v) => s.prefs.setBool('cheerShowMe', v);

/// Runners shown on cheer cards and maps: followed, then you.
List<int> cheerIds(RaceSim sim, List<int> followed, {required bool showMe}) => [
      for (final id in followed)
        if (id != sim.youId) id,
      if (showMe) sim.youId,
    ];

/// Heavy per-runner numbers, refreshed at most once a second.
class LiveCounts {
  const LiveCounts({required this.lastCp, required this.passed, required this.passedBy, required this.roadPlace});

  /// Index of the last checkpoint crossed (-1 = not across the start yet).
  final int lastCp;

  /// Runners overtaken / overtaken by since [lastCp].
  final int passed;
  final int passedBy;

  /// Place on the road right now (1 = leading). 0 when not started.
  final int roadPlace;

  static const empty = LiveCounts(lastCp: -1, passed: 0, passedBy: 0, roadPlace: 0);
}

/// Leading runner of one gender who is still out on the course.
class LeaderOnCourse {
  const LeaderOnCourse({required this.id, required this.distanceM});
  final int id;
  final double distanceM;
}

/// One dot of the "show field" crowd layer.
class FieldDot {
  const FieldDot(this.point, this.gender);
  final LatLng point;
  final Gender gender;
}

enum SpotKind { start, checkpoint, landmark, custom, finish }

/// A place on the course where a supporter stands to cheer.
class CheerSpot {
  const CheerSpot({required this.name, required this.distanceM, required this.kind});
  final String name;
  final double distanceM;
  final SpotKind kind;

  LatLng point(Race race) => race.route.at(distanceM);

  bool sameAs(CheerSpot? o) => o != null && o.name == name && (o.distanceM - distanceM).abs() < 1;

  /// Spots worth suggesting: checkpoints plus well-known places near the
  /// course (KLCC, Bukit Bintang, Merdeka 118...), sorted by km.
  static List<CheerSpot> suggested(Race race) {
    final out = <CheerSpot>[
      for (final c in race.checkpoints)
        CheerSpot(
          name: c.name,
          distanceM: c.distanceM,
          kind: switch (c.type) {
            CheckpointType.start => SpotKind.start,
            CheckpointType.finish => SpotKind.finish,
            CheckpointType.split => SpotKind.checkpoint,
          },
        ),
    ];
    // The start and finish share Dataran Merdeka: keep only the finish.
    out.removeWhere((s) => s.kind == SpotKind.start);
    final places = <(String, LatLng)>[
      for (final l in race.landmarks)
        if (l.kind != 'park') (l.kind == 'twin' ? 'KLCC' : l.name, l.location),
      ('Bukit Bintang', const LatLng(3.1466, 101.7110)),
    ];
    for (final (name, loc) in places) {
      final snap = race.route.snap(loc);
      if (snap.offCourse > 600) continue;
      if (out.any((s) => (s.distanceM - snap.distance).abs() < 350)) continue;
      out.add(CheerSpot(name: name, distanceM: snap.distance, kind: SpotKind.landmark));
    }
    out.sort((a, b) => a.distanceM.compareTo(b.distanceM));
    return out;
  }
}

/// "Tell me when to leave" for one runner and one spot.
class SpotAlarm {
  SpotAlarm({required this.spot, required this.participantId, required this.center});
  final CheerSpot spot;
  final int participantId;
  final NotificationCenter center;
  bool fired = false;
}

/// Shared live state for the Cheer feature.
///
/// Does the expensive whole-field work (live overtakes since the last
/// checkpoint, road place, leaders on course, the crowd sample) in one pass
/// over all 11,760 runners, at most once per second of real time. Also
/// owns the cheer-spot selection and the "leave now" alarms so they survive
/// navigating between screens.
///
/// One instance per [RaceSim] ([of]). It only listens to the race clock while
/// something listens to it, so it costs nothing when the Cheer tab is gone.
class CheerLive extends ChangeNotifier {
  CheerLive._(this.sim);

  static final Expando<CheerLive> _cache = Expando('CheerLive');
  static CheerLive of(RaceSim sim) => _cache[sim] ??= CheerLive._(sim);

  final RaceSim sim;

  // ------------------------------------------------------------ outputs

  Map<int, LiveCounts> _counts = const {};
  LiveCounts counts(int id) {
    final c = _counts[id];
    if (c == null && !_requested.contains(id)) {
      _requested.add(id);
      scheduleMicrotask(_refreshSoon);
    }
    return c ?? LiveCounts.empty;
  }

  /// Runners someone asked about that aren't followed (kept, it's tiny).
  final Set<int> _requested = {};

  LeaderOnCourse? leaderMen;
  LeaderOnCourse? leaderWomen;
  int notStarted = 0, running = 0, finished = 0, dnf = 0;
  List<FieldDot> field = const [];

  /// Race time the numbers above were computed at.
  double computedAt = double.nan;

  // ------------------------------------------------- extra subscriptions

  final Map<int, int> _extra = {};
  int _fieldRefs = 0;

  /// Also compute counts for [id] (e.g. a runner opened from the ranking).
  void track(int id) {
    _extra[id] = (_extra[id] ?? 0) + 1;
    if (!_counts.containsKey(id)) scheduleMicrotask(_refreshSoon);
  }

  void untrack(int id) {
    final n = (_extra[id] ?? 1) - 1;
    n <= 0 ? _extra.remove(id) : _extra[id] = n;
  }

  /// The crowd layer is only sampled while some map shows it.
  void wantField(bool on) {
    _fieldRefs = math.max(0, _fieldRefs + (on ? 1 : -1));
    if (on) scheduleMicrotask(_refreshSoon);
  }

  bool get fieldOn => _fieldRefs > 0;

  // ------------------------------------------------------- cheer spots

  CheerSpot? _spot;
  CheerSpot? get spot => _spot;
  set spot(CheerSpot? s) {
    _spot = s;
    notifyListeners();
  }

  /// Sets the spot only if none is chosen yet, without notifying.
  void initSpot(CheerSpot s) => _spot ??= s;

  int _walkMinutes = 10;

  /// How long the supporter needs to walk to the spot.
  int get walkMinutes => _walkMinutes;
  set walkMinutes(int v) {
    _walkMinutes = v.clamp(1, 60);
    notifyListeners();
  }

  final List<SpotAlarm> alarms = [];

  SpotAlarm? alarmFor(CheerSpot spot, int participantId) {
    for (final a in alarms) {
      if (a.participantId == participantId && a.spot.sameAs(spot)) return a;
    }
    return null;
  }

  void setAlarm(CheerSpot spot, int participantId, NotificationCenter center, bool on) {
    alarms.removeWhere((a) => a.participantId == participantId && a.spot.sameAs(spot));
    if (on) alarms.add(SpotAlarm(spot: spot, participantId: participantId, center: center));
    _checkAlarms(sim.raceTime, deferPost: true);
    notifyListeners();
  }

  // ---------------------------------------------------------- lifecycle

  int _listenerCount = 0;
  bool _attached = false;
  Timer? _timer;
  DateTime _lastRun = DateTime.fromMillisecondsSinceEpoch(0);
  RaceStatus? _lastStatus;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _listenerCount++;
    if (!_attached) _attach();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _listenerCount = math.max(0, _listenerCount - 1);
    if (_listenerCount == 0) _detach();
  }

  void _attach() {
    _attached = true;
    sim.clock.addListener(_onClock);
    sim.addListener(_onSim);
    // Fill the numbers right away (no notify: the new listener reads them).
    _compute(deferPost: true);
  }

  void _detach() {
    if (!_attached) return;
    _attached = false;
    sim.clock.removeListener(_onClock);
    sim.removeListener(_onSim);
    _timer?.cancel();
    _timer = null;
  }

  void _onSim() {
    if (sim.status != _lastStatus) _run();
  }

  void _onClock() {
    final t = sim.raceTime;
    // Jumps (demo director, reset) refresh at once; normal ticking ≤ 1 Hz.
    if (computedAt.isNaN || t < computedAt || t - computedAt > 600) {
      _run();
    } else {
      _refreshSoon();
    }
  }

  void _refreshSoon() {
    if (!_attached || _timer != null) return;
    const gap = Duration(seconds: 1);
    final since = DateTime.now().difference(_lastRun);
    if (since >= gap) {
      _run();
    } else {
      _timer = Timer(gap - since, () {
        _timer = null;
        if (_attached) _run();
      });
    }
  }

  void _run() {
    _timer?.cancel();
    _timer = null;
    _compute();
    notifyListeners();
  }

  // ------------------------------------------------------------ compute

  void _compute({bool deferPost = false}) {
    _lastRun = DateTime.now();
    _lastStatus = sim.status;
    final t = sim.raceTime;
    computedAt = t;
    final race = sim.race;
    final table = sim.crossingTable;
    final times = table.times;
    final cpCount = race.checkpoints.length;

    final ids = {...sim.watched, ..._extra.keys, ..._requested};

    if (sim.status == RaceStatus.preRace) {
      _counts = {for (final id in ids) id: LiveCounts.empty};
      leaderMen = leaderWomen = null;
      notStarted = sim.participants.length;
      running = finished = dnf = 0;
      field = const [];
      for (final a in alarms) {
        a.fired = false;
      }
      return;
    }

    final tracks = <_Track>[];
    for (final id in ids) {
      final i = table.indexOf[id];
      if (i == null) continue;
      var k = -1;
      for (var c = 0; c < cpCount; c++) {
        final x = times[c][i];
        if (x.isNaN || x > t) break;
        k = c;
      }
      final fin = times[cpCount - 1][i];
      tracks.add(_Track(
        id: id,
        index: i,
        lastCp: k,
        crossed: k >= 0 ? times[k][i] : double.nan,
        distance: sim.distanceAt(id, t),
        finishedAt: (!fin.isNaN && fin <= t) ? fin : double.nan,
      ));
    }

    var ns = 0, run = 0, fin = 0, out = 0;
    var bestM = -1.0, bestF = -1.0;
    var leadM = -1, leadF = -1;
    final wantField = _fieldRefs > 0;
    final dots = <FieldDot>[];
    final closedOut = sim.status == RaceStatus.closed && t >= race.cutoffS;
    final finishTimes = times[cpCount - 1];
    final runners = table.runners;

    for (var j = 0; j < runners.length; j++) {
      final p = runners[j];
      final plan = sim.plan(p.id);
      final d = sim.distanceAt(p.id, t);
      final started = t >= plan.startDelayS;
      final isDnf = plan.dnfAtM != null && d >= plan.dnfAtM!;
      final isFin = !isDnf && d >= race.distanceM;
      if (!started) {
        ns++;
      } else if (isDnf || (!isFin && closedOut)) {
        out++;
      } else if (isFin) {
        fin++;
      } else {
        run++;
        if (p.gender == Gender.m) {
          if (d > bestM) {
            bestM = d;
            leadM = p.id;
          }
        } else if (d > bestF) {
          bestF = d;
          leadF = p.id;
        }
        if (wantField && j % 12 == 0) dots.add(FieldDot(race.route.at(d), p.gender));
      }

      for (final tr in tracks) {
        if (j == tr.index || tr.lastCp < 0) continue;
        if (!tr.finishedAt.isNaN) {
          final f = finishTimes[j];
          if (!f.isNaN && f < tr.finishedAt) tr.ahead++;
          continue;
        }
        if (d > tr.distance) tr.ahead++;
        final c = times[tr.lastCp][j];
        if (c.isNaN || c > t) continue;
        if (c < tr.crossed && d < tr.distance) {
          tr.passed++;
        } else if (c > tr.crossed && d > tr.distance) {
          tr.passedBy++;
        }
      }
    }

    _counts = {
      for (final tr in tracks)
        tr.id: LiveCounts(
          lastCp: tr.lastCp,
          passed: tr.passed,
          passedBy: tr.passedBy,
          roadPlace: tr.lastCp < 0 ? 0 : tr.ahead + 1,
        ),
    };
    notStarted = ns;
    running = run;
    finished = fin;
    dnf = out;
    leaderMen = leadM < 0 ? null : LeaderOnCourse(id: leadM, distanceM: bestM);
    leaderWomen = leadF < 0 ? null : LeaderOnCourse(id: leadF, distanceM: bestF);
    field = wantField ? dots : const [];
    _checkAlarms(t, deferPost: deferPost);
  }

  void _checkAlarms(double t, {bool deferPost = false}) {
    if (sim.status == RaceStatus.preRace) return;
    for (final a in alarms) {
      if (a.fired) continue;
      final id = a.participantId;
      if (sim.distanceAt(id, t) >= a.spot.distanceM) {
        // Already went past (e.g. after a jump): nothing to warn about.
        a.fired = true;
        continue;
      }
      final eta = sim.etaToDistance(id, a.spot.distanceM, t);
      if (eta == null) continue;
      if (eta - t > _walkMinutes * 60) continue;
      a.fired = true;
      final p = sim.participant(id);
      final mins = math.max(1, ((eta - t) / 60).round());
      final notice = AppNotice(
        kind: NoticeKind.checkpoint,
        participantId: id,
        title: tr('Leave now for {spot}', {'spot': a.spot.name}),
        body: tr('{name} reaches {spot} in about {n} min ({time}). Start walking!', {
          'name': id == sim.youId ? tr('You') : p.firstName,
          'spot': a.spot.name,
          'n': mins,
          'time': fmtClock(sim.wallClockAt(eta)),
        }),
        at: sim.now,
      );
      // Never notify another ChangeNotifier from inside a build.
      if (deferPost) {
        scheduleMicrotask(() => a.center.post(notice));
      } else {
        a.center.post(notice);
      }
    }
  }
}

class _Track {
  _Track({required this.id, required this.index, required this.lastCp, required this.crossed, required this.distance, required this.finishedAt});
  final int id;
  final int index;
  final int lastCp;
  final double crossed;
  final double distance;
  final double finishedAt;
  int passed = 0;
  int passedBy = 0;
  int ahead = 0;
}

/// Race time that moves every frame instead of every 100 ms sim tick, so
/// map dots glide. Extrapolates from the last tick at the sim speed (capped
/// at 250 ms) and only ticks while the race is live and playing.
class SmoothClock extends ValueNotifier<double> {
  SmoothClock(this.sim, TickerProvider vsync) : super(sim.raceTime) {
    _ticker = vsync.createTicker(_tick);
    _base = sim.raceTime;
    sim.clock.addListener(_onClock);
    sim.addListener(_sync);
    _sync();
  }

  final RaceSim sim;
  late final Ticker _ticker;
  double _base = 0;
  Duration _now = Duration.zero;
  Duration _baseAt = Duration.zero;

  bool get _shouldRun => sim.playing && sim.status == RaceStatus.live;

  void _onClock() {
    final t = sim.raceTime;
    final jump = t < _base || t - _base > math.max(5, sim.speed * 0.6);
    _base = t;
    _baseAt = _now;
    if (!_ticker.isActive || jump || t > value) value = t;
  }

  void _tick(Duration elapsed) {
    _now = elapsed;
    final dt = math.min((elapsed - _baseAt).inMicroseconds / 1e6, 0.25);
    final v = _base + dt * sim.speed;
    if (v > value) value = v;
  }

  void _sync() {
    final run = _shouldRun;
    if (run && !_ticker.isActive) {
      _now = Duration.zero;
      _baseAt = Duration.zero;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
      value = sim.raceTime;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    sim.clock.removeListener(_onClock);
    sim.removeListener(_sync);
    super.dispose();
  }
}
