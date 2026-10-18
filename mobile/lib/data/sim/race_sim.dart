import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../demo/field_generator.dart';
import '../insights/insights_engine.dart';
import '../models.dart';

/// Things that happen during the simulated race. Screens listen to
/// [RaceSim.events] to show toasts and push notifications.
sealed class SimEvent {
  const SimEvent(this.raceTimeS);
  final double raceTimeS;
}

class GunFired extends SimEvent {
  const GunFired(super.raceTimeS);
}

class CheckpointPassed extends SimEvent {
  const CheckpointPassed(super.raceTimeS, this.participantId, this.checkpointIndex);
  final int participantId;
  final int checkpointIndex;
}

class RunnerFinished extends SimEvent {
  const RunnerFinished(super.raceTimeS, this.participantId);
  final int participantId;
}

class CheerReceived extends SimEvent {
  const CheerReceived(super.raceTimeS, this.message);
  final CheerMessage message;
}

class SosRaised extends SimEvent {
  const SosRaised(super.raceTimeS, this.alert);
  final SosAlert alert;
}

class RaceStatusChanged extends SimEvent {
  const RaceStatusChanged(super.raceTimeS, this.status);
  final RaceStatus status;
}

class ResultsPublished extends SimEvent {
  const ResultsPublished(super.raceTimeS);
}

enum RunnerState { notStarted, running, finished, dnf }

/// One recorded checkpoint read (OCR camera or manual entry in organizer).
class StaffRead {
  StaffRead({required this.bib, required this.checkpointIndex, required this.raceTimeS, required this.source, required this.confidence, this.participantId});
  final String bib;
  final int checkpointIndex;
  final double raceTimeS;
  final PassSource source;
  final double confidence;

  /// null when the bib isn't in the start list (goes to review).
  final int? participantId;
}

/// Simulated race day. Stands in for the Laravel backend + Reverb in demo
/// mode: it owns the race clock, moves every runner along the course, and
/// emits the same kinds of events the real API would broadcast.
///
/// Clock: [clock] holds race time in seconds since the gun (negative before
/// the gun). It advances at [speed]× real time while [playing].
class RaceSim extends ChangeNotifier {
  RaceSim({required this.event, required this.field}) {
    _byId = {for (final p in field.participants) p.id: p};
    _byBib = {for (final p in field.participants) p.bib: p};
    _buildCrossingTable();
    _scheduleDemoMoments();
  }

  final RaceEvent event;
  final DemoField field;
  Race get race => event.races.first;
  List<Participant> get participants => field.participants;
  late final Map<int, Participant> _byId;
  late final Map<String, Participant> _byBib;
  late final CrossingTable crossingTable;

  Participant participant(int id) => _byId[id]!;
  Participant? byBib(String bib) => _byBib[bib.trim()];
  int get youId => field.youId;
  Participant get you => _byId[field.youId]!;
  List<int> get friendIds => field.friendIds;
  RunnerPlan plan(int id) => field.plans[id]!;

  /// Search by name or bib (case-insensitive, contains).
  List<Participant> search(String q, {int limit = 30}) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return const [];
    final exact = _byBib[s];
    final out = <Participant>[?exact];
    for (final p in participants) {
      if (out.length >= limit) break;
      if (p == exact) continue;
      if (p.bib.startsWith(s) || p.name.toLowerCase().contains(s)) out.add(p);
    }
    return out;
  }

  // ---------------------------------------------------------------- clock

  final ValueNotifier<double> clock = ValueNotifier(-300);
  double get raceTime => clock.value;
  RaceStatus status = RaceStatus.preRace;
  bool playing = false;
  double speed = 30;
  bool official = false;
  bool timingImported = false;
  static const speeds = [1.0, 10.0, 30.0, 60.0, 120.0];

  Timer? _timer;
  DateTime? _lastTick;

  /// Wall-clock time of the gun. Before the gun this is the planned start.
  DateTime get gunWallClock => race.scheduledStart;
  DateTime wallClockAt(double raceTimeS) => gunWallClock.add(Duration(milliseconds: (raceTimeS * 1000).round()));
  DateTime get now => wallClockAt(raceTime);

  final _events = StreamController<SimEvent>.broadcast();
  Stream<SimEvent> get events => _events.stream;

  /// Runners whose checkpoint/finish events are emitted (you + follows).
  final Set<int> watched = {};

  void setWatched(Iterable<int> ids) {
    watched
      ..clear()
      ..addAll(ids)
      ..add(youId);
  }

  void play() {
    if (playing) return;
    playing = true;
    _lastTick = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    notifyListeners();
  }

  void pause() {
    playing = false;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  void setSpeed(double x) {
    speed = x;
    notifyListeners();
  }

  /// Organizer taps "Gun". Starts the race clock at 0.
  void fireGun() {
    if (status != RaceStatus.preRace) return;
    status = RaceStatus.live;
    clock.value = 0;
    _emit(const GunFired(0));
    _emit(const RaceStatusChanged(0, RaceStatus.live));
    play();
    notifyListeners();
  }

  /// Jump the race clock (demo director). Events in between are skipped.
  void jumpTo(double t) {
    if (status == RaceStatus.preRace && t >= 0) fireGun();
    final target = t.clamp(-600.0, race.cutoffS.toDouble() + 600);
    final from = clock.value;
    clock.value = target;
    if (target > from) _emitBetween(from, target, quiet: target - from > 600);
    if (target >= race.cutoffS && status == RaceStatus.live) closeRace();
    notifyListeners();
  }

  void closeRace() {
    if (status == RaceStatus.closed) return;
    status = RaceStatus.closed;
    _emit(RaceStatusChanged(raceTime, RaceStatus.closed));
    notifyListeners();
  }

  /// Organizer publishes official results (after an optional timing import).
  void publishOfficial({bool fromImport = false}) {
    official = true;
    timingImported = timingImported || fromImport;
    if (status != RaceStatus.closed) {
      if (raceTime < race.cutoffS) clock.value = race.cutoffS.toDouble();
      closeRace();
    }
    _emit(ResultsPublished(raceTime));
    notifyListeners();
  }

  /// Back to before the gun, everything cleared.
  void reset() {
    pause();
    status = RaceStatus.preRace;
    official = false;
    timingImported = false;
    clock.value = -300;
    sosAlerts.clear();
    staffReads.clear();
    cheers.clear();
    _firedMoments.clear();
    notifyListeners();
  }

  void _tick() {
    final nowWall = DateTime.now();
    final dt = nowWall.difference(_lastTick ?? nowWall).inMicroseconds / 1e6;
    _lastTick = nowWall;
    if (status == RaceStatus.preRace) {
      // Countdown runs at real speed until someone fires the gun.
      clock.value = math.min(-1, clock.value + dt);
      return;
    }
    if (status == RaceStatus.closed && clock.value >= race.cutoffS + 600) return;
    final from = clock.value;
    final to = from + dt * speed;
    clock.value = to;
    _emitBetween(from, to);
    if (to >= race.cutoffS && status == RaceStatus.live) closeRace();
  }

  void _emit(SimEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  void _emitBetween(double from, double to, {bool quiet = false}) {
    for (final id in watched) {
      final i = crossingTable.indexOf[id];
      if (i == null) continue;
      for (var k = 0; k < race.checkpoints.length; k++) {
        final t = crossingTable.times[k][i];
        if (t.isNaN || t <= from || t > to) continue;
        if (quiet && k != race.checkpoints.length - 1) continue;
        _emit(k == race.checkpoints.length - 1 ? RunnerFinished(t, id) : CheckpointPassed(t, id, k));
      }
    }
    for (final m in _moments) {
      if (m.at > from && m.at <= to && !_firedMoments.contains(m)) {
        _firedMoments.add(m);
        if (!quiet || m.alwaysFire) m.fire();
      }
    }
  }

  // ------------------------------------------------------------ kinematics

  /// Net seconds a runner needs to reach race distance [d] (null if they DNF first).
  double? netToDistance(int id, double d) {
    final p = plan(id);
    if (p.dnfAtM != null && d > p.dnfAtM!) return null;
    final marks = p.marksM, cum = p.cumS;
    final dd = d.clamp(0.0, marks.last);
    final k = _segment(marks, dd);
    final f = (dd - marks[k]) / (marks[k + 1] - marks[k]);
    return cum[k] + (cum[k + 1] - cum[k]) * f;
  }

  /// Race time (since gun) when a runner crosses race distance [d].
  double? crossingTime(int id, double d) {
    final n = netToDistance(id, d);
    return n == null ? null : plan(id).startDelayS + n;
  }

  /// Race distance covered at race time [t].
  double distanceAt(int id, double t) {
    final p = plan(id);
    final e = t - p.startDelayS;
    if (e <= 0) return 0;
    final cum = p.cumS, marks = p.marksM;
    if (e >= cum.last) return p.dnfAtM ?? race.distanceM;
    final k = _segment(cum, e);
    final f = (e - cum[k]) / (cum[k + 1] - cum[k]);
    final d = marks[k] + (marks[k + 1] - marks[k]) * f;
    if (p.dnfAtM != null && d > p.dnfAtM!) return p.dnfAtM!;
    return d;
  }

  /// Index k with xs[k] <= v < xs[k+1] (clamped to the last segment).
  static int _segment(List<double> xs, double v) {
    var lo = 0, hi = xs.length - 1;
    while (hi - lo > 1) {
      final m = (lo + hi) >> 1;
      if (xs[m] <= v) {
        lo = m;
      } else {
        hi = m;
      }
    }
    return lo;
  }

  RunnerState stateAt(int id, double t) {
    final p = plan(id);
    if (t < p.startDelayS || status == RaceStatus.preRace) return RunnerState.notStarted;
    if (p.dnfAtM != null && distanceAt(id, t) >= p.dnfAtM!) return RunnerState.dnf;
    if (t - p.startDelayS >= p.netS) return RunnerState.finished;
    if (status == RaceStatus.closed && t >= race.cutoffS) return RunnerState.dnf;
    return RunnerState.running;
  }

  LatLng positionAt(int id, double t) => race.route.at(distanceAt(id, t));

  /// Current pace (seconds per km) over the stretch the runner is in.
  double paceAt(int id, double t) {
    final p = plan(id);
    final k = _segment(p.marksM, math.min(distanceAt(id, t), p.marksM.last - 0.001));
    return (p.cumS[k + 1] - p.cumS[k]) / ((p.marksM[k + 1] - p.marksM[k]) / 1000);
  }

  /// Net elapsed time at race time [t] (0 before the start line).
  double elapsedAt(int id, double t) => math.max(0, math.min(t - plan(id).startDelayS, plan(id).netS));

  /// Predicted race time to reach distance [d], using the current pace
  /// (what a real server would know), not the hidden plan.
  double? etaToDistance(int id, double d, double t) {
    final now = distanceAt(id, t);
    if (now >= d) return crossingTime(id, d);
    final st = stateAt(id, t);
    if (st == RunnerState.dnf) return null;
    final pace = paceAt(id, t);
    final start = st == RunnerState.notStarted ? math.max(t, plan(id).startDelayS) : t;
    return start + (d - now) / 1000 * pace;
  }

  double? projectedFinish(int id, double t) {
    final eta = etaToDistance(id, race.distanceM, t);
    return eta == null ? null : eta - plan(id).startDelayS;
  }

  /// Live overtakes since a runner crossed [fromDistance]: how many runners
  /// who crossed it earlier are now behind them, and vice versa.
  ({int passed, int passedBy}) liveOvertakes(int id, double fromDistance, double t) {
    final mine = crossingTime(id, fromDistance);
    if (mine == null || mine > t) return (passed: 0, passedBy: 0);
    final myD = distanceAt(id, t);
    var passed = 0, passedBy = 0;
    for (final p in participants) {
      if (p.id == id) continue;
      final c = crossingTime(p.id, fromDistance);
      if (c == null || c > t) continue;
      final d = distanceAt(p.id, t);
      if (c < mine && d < myD) passed++;
      if (c > mine && d > myD) passedBy++;
    }
    return (passed: passed, passedBy: passedBy);
  }

  /// Current place on the road (by distance covered), 1 = leading.
  int livePlace(int id, double t) {
    final myD = distanceAt(id, t);
    final myT = stateAt(id, t) == RunnerState.finished ? crossingTime(id, race.distanceM)! : double.infinity;
    var ahead = 0;
    for (final p in participants) {
      if (p.id == id) continue;
      final d = distanceAt(p.id, t);
      if (d > myD) {
        ahead++;
      } else if (d >= race.distanceM && myD >= race.distanceM) {
        if (crossingTime(p.id, race.distanceM)! < myT) ahead++;
      }
    }
    return ahead + 1;
  }

  /// Field overview for the organizer console.
  ({int notStarted, int running, int finished, int dnf, List<int> density}) fieldStats(double t, {double binM = 500}) {
    var ns = 0, run = 0, fin = 0, dnf = 0;
    final bins = List<int>.filled((race.distanceM / binM).ceil(), 0);
    for (final p in participants) {
      switch (stateAt(p.id, t)) {
        case RunnerState.notStarted:
          ns++;
        case RunnerState.running:
          run++;
          final b = (distanceAt(p.id, t) / binM).floor().clamp(0, bins.length - 1);
          bins[b]++;
        case RunnerState.finished:
          fin++;
        case RunnerState.dnf:
          dnf++;
      }
    }
    return (notStarted: ns, running: run, finished: fin, dnf: dnf, density: bins);
  }

  /// Positions of every [every]-th running runner, for a "field" layer.
  List<LatLng> fieldSample(double t, {int every = 15}) {
    final out = <LatLng>[];
    for (var i = 0; i < participants.length; i += every) {
      final id = participants[i].id;
      if (stateAt(id, t) == RunnerState.running) out.add(positionAt(id, t));
    }
    return out;
  }

  // -------------------------------------------------------- crossing table

  void _buildCrossingTable() {
    final cps = race.checkpoints;
    final n = participants.length;
    final times = [for (var k = 0; k < cps.length; k++) Float64List(n)];
    for (var i = 0; i < n; i++) {
      final id = participants[i].id;
      for (var k = 0; k < cps.length; k++) {
        times[k][i] = crossingTime(id, cps[k].distanceM) ?? double.nan;
      }
    }
    crossingTable = CrossingTable(runners: participants, times: times);
  }

  /// Snapshot of Race Insights at the current clock (or [asOf]).
  InsightsSnapshot insights({double? asOf, RankBasis? basis}) {
    final t = asOf ?? (status == RaceStatus.preRace ? -1 : raceTime);
    return InsightsEngine.compute(
      crossingTable,
      race,
      asOf: t,
      basis: basis ?? race.rankBasis,
      official: official,
      closed: status == RaceStatus.closed,
    );
  }

  // ---------------------------------------------- organizer + social bits

  final List<SosAlert> sosAlerts = [];
  final List<StaffRead> staffReads = [];
  final List<CheerMessage> cheers = [];
  var _sosId = 1;

  SosAlert raiseSos(int participantId, String reason) {
    final alert = SosAlert(
      id: _sosId++,
      participantId: participantId,
      location: positionAt(participantId, raceTime),
      raceTimeS: raceTime,
      reason: reason,
    );
    sosAlerts.insert(0, alert);
    _emit(SosRaised(raceTime, alert));
    notifyListeners();
    return alert;
  }

  void updateSos(SosAlert alert, String status) {
    alert.status = status;
    notifyListeners();
  }

  /// A cheer message to a runner. Messages to you trigger [CheerReceived].
  void sendCheer({required int toParticipantId, required String from, required String body}) {
    final m = CheerMessage(from: from, body: body, at: now, toParticipantId: toParticipantId);
    cheers.insert(0, m);
    if (toParticipantId == youId) _emit(CheerReceived(raceTime, m));
    notifyListeners();
  }

  List<CheerMessage> cheersFor(int id) => [for (final c in cheers) if (c.toParticipantId == id) c];

  /// Checkpoint camera / manual entry. Validates the bib against the start list.
  StaffRead recordRead(String bib, int checkpointIndex, {PassSource source = PassSource.ocr, double confidence = 1}) {
    final p = byBib(bib);
    final read = StaffRead(
      bib: bib,
      checkpointIndex: checkpointIndex,
      raceTimeS: raceTime,
      source: source,
      confidence: confidence,
      participantId: p?.id,
    );
    staffReads.insert(0, read);
    notifyListeners();
    return read;
  }

  /// Official timing CSV for the demo race, generated from the simulation
  /// (what a timing company would hand the organizer).
  String exportTimingCsv() {
    final b = StringBuffer('bib,name,gender,category,nation,gun_time,net_time\n');
    for (final i in crossingTable.indexOf.values) {
      final p = participants[i];
      final s = crossingTable.times[0][i], f = crossingTable.times.last[i];
      if (s.isNaN || f.isNaN) continue;
      b.writeln('${p.bib},"${p.name}",${p.gender.code},${race.categoryById(p.categoryId).name},${p.nation},${f.toStringAsFixed(1)},${(f - s).toStringAsFixed(1)}');
    }
    return b.toString();
  }

  // ------------------------------------------------------- scripted moments

  final List<_Moment> _moments = [];
  final Set<_Moment> _firedMoments = {};

  void _scheduleDemoMoments() {
    final qirah = field.friendIds[0];
    final hafiz = field.friendIds[1];
    void cheer(double at, int from, String body) => _moments.add(_Moment(at, () {
          sendCheer(toParticipantId: youId, from: participant(from).firstName, body: body);
        }));
    cheer(420, qirah, 'Go Arep! Steady pace, KLCC coming up 💪');
    cheer(1900, hafiz, 'Halfway soon bro, jangan slow down!');
    cheer(3300, qirah, 'You passed 1,000 people already?! Gila laju 🔥');
    cheer(5200, qirah, 'Last 1K!! Dataran is waiting for you');
    // Two random SOS calls for the organizer console.
    _moments.add(_Moment(2700, () => raiseSos(participants[777].id, 'Cramp, cannot continue'), alwaysFire: true));
    _moments.add(_Moment(6100, () => raiseSos(participants[5021].id, 'Feeling dizzy (heat)'), alwaysFire: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _events.close();
    clock.dispose();
    super.dispose();
  }
}

class _Moment {
  _Moment(this.at, this.fire, {this.alwaysFire = false});
  final double at;
  final VoidCallback fire;
  final bool alwaysFire;
}
