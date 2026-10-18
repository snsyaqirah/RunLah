import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/geo.dart';
import 'models.dart';

/// Free run (no event) or an official event run (bib, checkpoints, ranking).
enum ActivityMode { free, event }

/// One GPS fix. Times are UTC. Serialises to the PRD 15.3 wire format
/// `{t, lat, lng, acc, spd}` for `POST /activities/{id}/points`.
@immutable
class TrackPoint {
  const TrackPoint({required this.t, required this.lat, required this.lng, this.acc = 0, this.spd = 0});

  final DateTime t;
  final double lat;
  final double lng;

  /// Horizontal accuracy in metres.
  final double acc;

  /// Speed in m/s.
  final double spd;

  LatLng get latLng => LatLng(lat, lng);

  /// PRD 15.3 point: `{ "t": "2026-12-06T22:30:05Z", "lat": .., "lng": .., "acc": .., "spd": .. }`.
  Map<String, Object> toApiJson() => {
        't': '${t.toUtc().toIso8601String().split('.').first}Z',
        'lat': _round(lat, 6),
        'lng': _round(lng, 6),
        'acc': _round(acc, 1),
        'spd': _round(spd, 2),
      };

  /// Compact storage form: [epochMs, lat, lng, acc, spd].
  List<num> toCompact() => [t.millisecondsSinceEpoch, _round(lat, 6), _round(lng, 6), _round(acc, 1), _round(spd, 2)];

  factory TrackPoint.fromCompact(List<dynamic> l) => TrackPoint(
        t: DateTime.fromMillisecondsSinceEpoch((l[0] as num).toInt(), isUtc: true),
        lat: (l[1] as num).toDouble(),
        lng: (l[2] as num).toDouble(),
        acc: (l[3] as num).toDouble(),
        spd: (l[4] as num).toDouble(),
      );

  static double _round(double v, int places) {
    final f = math.pow(10, places);
    return (v * f).round() / f;
  }
}

/// A saved run. Free runs keep their full track; event runs keep the result.
class Activity {
  Activity({
    required this.id,
    required this.mode,
    required this.title,
    required this.startedAt,
    required this.shareToken,
    this.endedAt,
    this.distanceM = 0,
    this.movingS = 0,
    List<TrackPoint>? points,
    List<double>? splitsS,
    this.privacy = Privacy.linkOnly,
    this.simulated = false,
    this.sample = false,
    this.raceId,
    this.participantId,
    this.place,
  })  : points = points ?? [],
        splitsS = splitsS ?? [];

  final String id;
  final ActivityMode mode;
  String title;
  final DateTime startedAt;
  DateTime? endedAt;
  double distanceM;

  /// Moving time (pauses excluded), seconds.
  double movingS;
  final List<TrackPoint> points;

  /// Duration of each completed kilometre, seconds.
  final List<double> splitsS;
  Privacy privacy;

  /// 128-bit random token for the share link (PRD 13: share tokens).
  final String shareToken;

  /// Recorded with simulated GPS (demo mode).
  final bool simulated;

  /// Seeded example run (shown with a "Sample" tag).
  final bool sample;
  final int? raceId;
  final int? participantId;
  final int? place;

  String get shareUrl => 'https://runlah.app/s/$shareToken';
  double get avgPaceSPerKm => distanceM < 20 ? 0 : movingS / (distanceM / 1000);
  double get avgKph => movingS <= 0 ? 0 : distanceM / movingS * 3.6;
  double? get bestKmS => splitsS.isEmpty ? null : splitsS.reduce(math.min);

  Map<String, Object?> toJson() => {
        'id': id,
        'mode': mode.name,
        'title': title,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'endedAt': endedAt?.toUtc().toIso8601String(),
        'distanceM': distanceM,
        'movingS': movingS,
        'points': [for (final p in points) p.toCompact()],
        'splitsS': splitsS,
        'privacy': privacy.name,
        'shareToken': shareToken,
        'simulated': simulated,
        'sample': sample,
        'raceId': raceId,
        'participantId': participantId,
        'place': place,
      };

  factory Activity.fromJson(Map<String, dynamic> j) => Activity(
        id: j['id'] as String,
        mode: ActivityMode.values.byName(j['mode'] as String? ?? 'free'),
        title: j['title'] as String? ?? '',
        startedAt: DateTime.parse(j['startedAt'] as String).toLocal(),
        endedAt: j['endedAt'] == null ? null : DateTime.parse(j['endedAt'] as String).toLocal(),
        distanceM: (j['distanceM'] as num? ?? 0).toDouble(),
        movingS: (j['movingS'] as num? ?? 0).toDouble(),
        points: [for (final p in (j['points'] as List? ?? const [])) TrackPoint.fromCompact(p as List)],
        splitsS: [for (final s in (j['splitsS'] as List? ?? const [])) (s as num).toDouble()],
        privacy: Privacy.values.byName(j['privacy'] as String? ?? 'linkOnly'),
        shareToken: j['shareToken'] as String? ?? ActivityStore.newShareToken(),
        simulated: j['simulated'] as bool? ?? false,
        sample: j['sample'] as bool? ?? false,
        raceId: j['raceId'] as int?,
        participantId: j['participantId'] as int?,
        place: j['place'] as int?,
      );
}

/// Saved activities and the offline GPS points queue (PRD F09).
///
/// * Activities are stored as JSON in SharedPreferences, newest first.
/// * Points waiting to be uploaded sit in a persisted FIFO queue keyed by
///   activity. The tracking service drains it in batches of up to 500
///   (PRD 15.3) and acknowledges with the server's `last_t`.
/// * The queue keeps at most 6 hours of points (PRD 10: offline target);
///   older points are dropped first.
class ActivityStore extends ChangeNotifier {
  ActivityStore(this.prefs) {
    _load();
  }

  final SharedPreferences prefs;

  static const _kActivities = 'activities.v1';
  static const _kQueue = 'pointsQueue.v1';
  static const _kSeeded = 'activities.seeded.v1';

  /// 6 hours at the 5 s interval.
  static const maxQueuedPoints = 6 * 3600 ~/ 5;

  final List<Activity> _activities = [];
  final LinkedHashMap<String, List<TrackPoint>> _queue = LinkedHashMap();
  final ValueNotifier<int> _queueSize = ValueNotifier(0);
  int _dropped = 0;

  /// Newest first.
  List<Activity> get activities => List.unmodifiable(_activities);
  List<Activity> get freeRuns => [for (final a in _activities) if (a.mode == ActivityMode.free) a];
  int get count => _activities.length;
  double get totalDistanceM => _activities.fold(0, (s, a) => s + a.distanceM);
  double get totalMovingS => _activities.fold(0, (s, a) => s + a.movingS);

  /// Fastest single kilometre across all saved runs (seconds).
  double? get fastestKmS {
    double? best;
    for (final a in _activities) {
      final b = a.bestKmS;
      if (b != null && (best == null || b < best)) best = b;
    }
    return best;
  }

  Activity? byId(String id) {
    for (final a in _activities) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Adds or replaces (same id) an activity.
  void save(Activity a) {
    _activities.removeWhere((x) => x.id == a.id);
    _activities.add(a);
    _activities.sort((x, y) => y.startedAt.compareTo(x.startedAt));
    _persistActivities();
    notifyListeners();
  }

  void delete(String id) {
    _activities.removeWhere((a) => a.id == id);
    _persistActivities();
    notifyListeners();
  }

  // ------------------------------------------------------------ the queue

  /// Number of points waiting for upload. Listen to this instead of the
  /// store so a growing queue doesn't rebuild activity lists.
  ValueListenable<int> get queueSize => _queueSize;
  int get queuedCount => _queueSize.value;
  int queuedFor(String activityId) => _queue[activityId]?.length ?? 0;

  /// Points dropped because the queue hit [maxQueuedPoints].
  int get droppedCount => _dropped;

  void enqueue(String activityId, Iterable<TrackPoint> points) {
    final list = _queue.putIfAbsent(activityId, () => []);
    list.addAll(points);
    var over = _queueSize.value + points.length - maxQueuedPoints;
    // Drop the oldest points first.
    while (over > 0 && _queue.isNotEmpty) {
      final key = _queue.keys.first;
      final l = _queue[key]!;
      final n = math.min(over, l.length);
      l.removeRange(0, n);
      over -= n;
      _dropped += n;
      if (l.isEmpty) _queue.remove(key);
    }
    _recount();
    _persistQueue(force: false);
  }

  /// The oldest batch waiting for upload (one activity, up to [max] points).
  ({String activityId, List<TrackPoint> points})? nextBatch({int max = 500}) {
    for (final e in _queue.entries) {
      if (e.value.isEmpty) continue;
      return (activityId: e.key, points: List.unmodifiable(e.value.take(max)));
    }
    return null;
  }

  /// Server accepted everything up to and including [lastT]. The wire
  /// format has whole seconds, so points within that second count too.
  void ack(String activityId, DateTime lastT) {
    final l = _queue[activityId];
    if (l == null) return;
    final cutoff = lastT.add(const Duration(milliseconds: 999));
    l.removeWhere((p) => !p.t.isAfter(cutoff));
    if (l.isEmpty) _queue.remove(activityId);
    _recount();
    _persistQueue();
  }

  /// Forget queued points of a discarded run.
  void dropQueued(String activityId) {
    if (_queue.remove(activityId) == null) return;
    _recount();
    _persistQueue();
  }

  void _recount() => _queueSize.value = _queue.values.fold(0, (s, l) => s + l.length);

  // ---------------------------------------------------------- persistence

  void _load() {
    try {
      final raw = prefs.getString(_kActivities);
      if (raw != null) {
        for (final j in jsonDecode(raw) as List) {
          _activities.add(Activity.fromJson(j as Map<String, dynamic>));
        }
      }
    } catch (_) {
      // Corrupt data shouldn't brick the app; start fresh.
      _activities.clear();
    }
    try {
      final raw = prefs.getString(_kQueue);
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        m.forEach((k, v) => _queue[k] = [for (final p in v as List) TrackPoint.fromCompact(p as List)]);
      }
    } catch (_) {
      _queue.clear();
    }
    _recount();
    if (prefs.getBool(_kSeeded) != true) {
      _activities.addAll(DemoTracks.sampleActivities(DateTime.now()));
      prefs.setBool(_kSeeded, true);
      _persistActivities();
    }
    _activities.sort((x, y) => y.startedAt.compareTo(x.startedAt));
  }

  void _persistActivities() {
    prefs.setString(_kActivities, jsonEncode([for (final a in _activities) a.toJson()]));
  }

  DateTime _lastQueueWrite = DateTime.fromMillisecondsSinceEpoch(0);
  bool _queueDirty = false;

  /// Writes the queue to disk. Point-by-point enqueues are throttled to one
  /// write every 2 s; call [persistQueue] when a run stops.
  void _persistQueue({bool force = true}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastQueueWrite) < const Duration(seconds: 2)) {
      _queueDirty = true;
      return;
    }
    _queueDirty = false;
    _lastQueueWrite = now;
    prefs.setString(_kQueue, jsonEncode({for (final e in _queue.entries) e.key: [for (final p in e.value) p.toCompact()]}));
  }

  /// Flush a throttled queue write now.
  void persistQueue() {
    if (_queueDirty) _persistQueue();
  }

  // -------------------------------------------------------------- helpers

  static final _rng = math.Random.secure();

  /// 128-bit random share token, URL-safe base64 without padding (22 chars).
  static String newShareToken() {
    final bytes = Uint8List.fromList([for (var i = 0; i < 16; i++) _rng.nextInt(256)]);
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String newId() => 'run-${DateTime.now().millisecondsSinceEpoch}-${_rng.nextInt(1 << 16)}';
}

/// Track maths shared by the tracker, the detail screen and achievements.
class TrackMath {
  /// Distance along a track (metres) at each point.
  static List<double> cumulativeDistance(List<TrackPoint> pts) {
    final out = <double>[];
    var acc = 0.0;
    for (var i = 0; i < pts.length; i++) {
      if (i > 0) acc += haversine(pts[i - 1].latLng, pts[i].latLng);
      out.add(acc);
    }
    return out;
  }

  /// Per-km durations from a track (seconds), interpolated at each km mark.
  static List<double> kmSplits(List<TrackPoint> pts) {
    if (pts.length < 2) return const [];
    final d = cumulativeDistance(pts);
    final t0 = pts.first.t;
    final out = <double>[];
    var nextKm = 1000.0;
    var lastCross = 0.0;
    for (var i = 1; i < pts.length; i++) {
      while (d[i] >= nextKm) {
        final a = pts[i - 1].t.difference(t0).inMilliseconds / 1000, b = pts[i].t.difference(t0).inMilliseconds / 1000;
        final f = d[i] == d[i - 1] ? 1.0 : (nextKm - d[i - 1]) / (d[i] - d[i - 1]);
        final cross = a + (b - a) * f;
        out.add(cross - lastCross);
        lastCross = cross;
        nextKm += 1000;
      }
    }
    return out;
  }

  /// Smoothed pace (s/km) samples along the track as (distance m, pace).
  /// Uses a sliding window of [windowM] metres.
  static List<({double d, double pace})> paceSeries(List<TrackPoint> pts, {double windowM = 250, int maxSamples = 120}) {
    if (pts.length < 3) return const [];
    final d = cumulativeDistance(pts);
    final out = <({double d, double pace})>[];
    var j = 0;
    final step = math.max(1, pts.length ~/ maxSamples);
    for (var i = 1; i < pts.length; i += step) {
      while (j < i && d[i] - d[j] > windowM) {
        j++;
      }
      final k = math.max(0, j - 1);
      final dd = d[i] - d[k];
      final dt = pts[i].t.difference(pts[k].t).inMilliseconds / 1000;
      if (dd < 30 || dt <= 0) continue;
      final pace = dt / (dd / 1000);
      if (pace < 120 || pace > 1500) continue;
      out.add((d: d[i], pace: pace));
    }
    return out;
  }
}

/// Demo loops for simulated GPS and the seeded sample runs.
class DemoTracks {
  /// The jogging track around KLCC Park (≈1.4 km loop).
  static final klccPark = RoutePath(const [
    LatLng(3.15712, 101.71262),
    LatLng(3.15768, 101.71350),
    LatLng(3.15770, 101.71470),
    LatLng(3.15720, 101.71580),
    LatLng(3.15625, 101.71640),
    LatLng(3.15505, 101.71645),
    LatLng(3.15395, 101.71590),
    LatLng(3.15335, 101.71480),
    LatLng(3.15345, 101.71360),
    LatLng(3.15410, 101.71270),
    LatLng(3.15510, 101.71215),
    LatLng(3.15620, 101.71220),
    LatLng(3.15712, 101.71262),
  ]);

  /// Loop through Perdana Botanical Garden (Lake Gardens, ≈2.1 km).
  static final lakeGardens = RoutePath(const [
    LatLng(3.14520, 101.68580),
    LatLng(3.14600, 101.68420),
    LatLng(3.14560, 101.68230),
    LatLng(3.14410, 101.68120),
    LatLng(3.14230, 101.68150),
    LatLng(3.14100, 101.68300),
    LatLng(3.14090, 101.68490),
    LatLng(3.14190, 101.68640),
    LatLng(3.14360, 101.68680),
    LatLng(3.14520, 101.68580),
  ]);

  /// Position on a closed loop at [d] metres (wraps around).
  static LatLng onLoop(RoutePath loop, double d) => loop.at(d % loop.geometryLength);

  /// A recorded loop run: points every [intervalS] seconds at about
  /// [paceS] s/km with natural pace drift and a little GPS noise.
  static List<TrackPoint> loopRun({
    required RoutePath loop,
    required DateTime start,
    required double distanceM,
    required double paceS,
    int intervalS = 5,
    int seed = 1,
  }) {
    final r = math.Random(seed);
    final out = <TrackPoint>[];
    var d = 0.0;
    var t = 0.0;
    while (d < distanceM) {
      final p = onLoop(loop, d);
      final mps = speedAt(paceS, t, seed);
      out.add(TrackPoint(
        t: start.toUtc().add(Duration(milliseconds: (t * 1000).round())),
        lat: p.latitude + (r.nextDouble() - 0.5) * 0.000012,
        lng: p.longitude + (r.nextDouble() - 0.5) * 0.000012,
        acc: 4 + r.nextDouble() * 4,
        spd: mps,
      ));
      t += intervalS;
      d += mps * intervalS;
    }
    final last = onLoop(loop, distanceM);
    out.add(TrackPoint(t: start.toUtc().add(Duration(milliseconds: (t * 1000).round())), lat: last.latitude, lng: last.longitude, acc: 5, spd: 0));
    return out;
  }

  /// Simulated running speed (m/s) at [t] seconds for a target pace:
  /// slow drift plus a warm-up in the first minute.
  static double speedAt(double paceS, double t, int seed) {
    final base = 1000 / paceS;
    final drift = 0.045 * math.sin(t / 70 + seed) + 0.025 * math.sin(t / 23 + seed * 2);
    final warm = t < 60 ? -0.08 * (1 - t / 60) : 0.0;
    return base * (1 + drift + warm);
  }

  /// Two example runs so history isn't empty on first launch.
  static List<Activity> sampleActivities(DateTime now) {
    Activity make(String title, RoutePath loop, DateTime start, double dist, double pace, int seed) {
      final pts = loopRun(loop: loop, start: start, distanceM: dist, paceS: pace, seed: seed);
      final d = TrackMath.cumulativeDistance(pts).last;
      final moving = pts.last.t.difference(pts.first.t).inMilliseconds / 1000;
      return Activity(
        id: 'sample-$seed',
        mode: ActivityMode.free,
        title: title,
        startedAt: start,
        endedAt: start.add(Duration(seconds: moving.round())),
        distanceM: d,
        movingS: moving,
        points: pts,
        splitsS: TrackMath.kmSplits(pts),
        shareToken: ActivityStore.newShareToken(),
        simulated: true,
        sample: true,
      );
    }

    final day = DateTime(now.year, now.month, now.day);
    return [
      make('Evening run · KLCC Park', klccPark, day.subtract(const Duration(days: 2)).add(const Duration(hours: 19, minutes: 10)), 5200, 352, 7),
      make('Long run · Lake Gardens', lakeGardens, day.subtract(const Duration(days: 6)).add(const Duration(hours: 6, minutes: 30)), 10400, 381, 11),
    ];
  }
}
