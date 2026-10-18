import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../core/geo.dart';
import '../core/l10n/i18n.dart';
import '../data/activity_store.dart';
import '../data/app_state.dart';
import 'points_sink.dart';
import 'voice_service.dart';

enum TrackingState { idle, starting, running, paused }

/// Location readiness for the pre-race check (PRD: "permission set to Always").
enum LocationReadiness { always, whileInUse, denied, deniedForever, serviceOff, unsupported }

/// GPS tracking for free runs (PRD F07–F10).
///
/// * Real GPS through geolocator at [SettingsController.gpsIntervalS]
///   (5 s, or 15 s in battery saver), with an Android foreground-service
///   notification and iOS background updates so it keeps running with the
///   screen off.
/// * Simulated GPS (a jog around KLCC Park at about 6:00/km) on web and
///   desktop, in tests, when permission is denied, or when switched on by
///   hand, so the demo always works.
/// * Every fix goes into the persisted offline queue in [ActivityStore];
///   an uploader drains it every 15 s in batches of ≤500 (PRD 15.3) when
///   the device is online.
class TrackingService extends ChangeNotifier {
  TrackingService(this.settings, this.store, this.voice, {PointsSink? sink}) : sink = sink ?? PointsSink.fromEnvironment() {
    _preferSimulated = settings.prefs.getBool(_kSimPref) ?? !hasNativeGps;
    _lastInterval = settings.gpsIntervalS;
    settings.addListener(_onSettings);
  }

  final SettingsController settings;
  final ActivityStore store;
  final VoiceService voice;
  final PointsSink sink;

  static const _kSimPref = 'run.simulatedGps';

  /// Simulated runner's target pace (s/km).
  static const simulatedPaceS = 360.0;
  static const simSpeeds = [1.0, 10.0, 30.0];

  // ------------------------------------------------------------- platform

  /// Phone platforms with background GPS. Web and desktop default to simulated.
  static bool get hasNativeGps => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// battery_plus and connectivity_plus have Linux implementations that
  /// talk to D-Bus; inside widget tests we skip them so no real I/O or
  /// timers leak into the fake clock.
  static bool get _inWidgetTest {
    try {
      return WidgetsBinding.instance.runtimeType.toString().contains('TestWidgetsFlutterBinding');
    } catch (_) {
      return false;
    }
  }

  /// Location permission + service state. Never throws.
  Future<LocationReadiness> locationReadiness({bool request = false}) async {
    // Status checks answer instantly on a phone; a platform without the
    // plugin may never answer, so they time out. Permission prompts don't.
    const quick = Duration(seconds: 4);
    try {
      if (!kIsWeb && !await Geolocator.isLocationServiceEnabled().timeout(quick)) return LocationReadiness.serviceOff;
      var p = await Geolocator.checkPermission().timeout(quick);
      if (request && p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (request && p == LocationPermission.whileInUse && !kIsWeb) {
        // Second request asks to upgrade to "Always" (Android 10+ / iOS).
        p = await Geolocator.requestPermission();
      }
      return switch (p) {
        LocationPermission.always => LocationReadiness.always,
        LocationPermission.whileInUse => LocationReadiness.whileInUse,
        LocationPermission.denied => LocationReadiness.denied,
        LocationPermission.deniedForever => LocationReadiness.deniedForever,
        LocationPermission.unableToDetermine => LocationReadiness.unsupported,
      };
    } catch (_) {
      return LocationReadiness.unsupported;
    }
  }

  Future<void> openLocationSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (_) {}
  }

  /// Battery percentage, or null when unknown.
  Future<int?> batteryLevel() async {
    if (_inWidgetTest) return null;
    try {
      return await Battery().batteryLevel;
    } catch (_) {
      return null;
    }
  }

  /// One GPS fix for the "GPS lock" check, or null.
  Future<Position?> gpsFix() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 15)),
      );
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------- session

  TrackingState _state = TrackingState.idle;
  TrackingState get state => _state;
  bool get active => _state != TrackingState.idle;

  late bool _preferSimulated;

  /// The user's GPS choice for the next run (switch on the free-run card).
  bool get preferSimulated => _preferSimulated;
  set preferSimulated(bool v) {
    if (v == _preferSimulated) return;
    _preferSimulated = v;
    settings.prefs.setBool(_kSimPref, v);
    notifyListeners();
  }

  bool _simulatedSession = false;

  /// The current (or last) session uses simulated GPS.
  bool get simulated => _simulatedSession;

  /// Why we fell back to simulated GPS, if we did.
  String? get sourceNote => _sourceNote;
  String? _sourceNote;

  double _simSpeed = 1;
  double get simSpeed => _simSpeed;
  set simSpeed(double v) {
    _simSpeed = v;
    notifyListeners();
  }

  String? _activityId;
  String? get activityId => _activityId;
  DateTime? _startedAt;
  DateTime? get startedAt => _startedAt;
  String _shareToken = '';
  String get shareUrl => 'https://runlah.app/s/$_shareToken';

  final List<TrackPoint> _track = [];
  List<TrackPoint> get track => _track;
  LatLng? get position => _track.isEmpty ? null : _track.last.latLng;

  double _distanceM = 0;
  double get distanceM => _distanceM;
  double _movingS = 0;

  /// Moving time in seconds (pauses excluded).
  double get movingS => _movingS;
  double get avgPaceSPerKm => _distanceM < 30 ? 0 : _movingS / (_distanceM / 1000);

  final List<double> _splits = [];

  /// Completed kilometre durations (s).
  List<double> get splitsS => _splits;
  double _lastSplitAt = 0;
  double _prevMovingS = 0;

  final ListQueue<(double, double)> _paceWindow = ListQueue();
  double? _currentPace;

  /// Pace over roughly the last 30 s (s/km).
  double? get currentPaceSPerKm => _currentPace;

  /// Last fix had poor accuracy (shown as "weak GPS").
  bool get weakSignal => _weakSignal;
  bool _weakSignal = false;

  StreamSubscription<Position>? _posSub;
  final Stopwatch _moving = Stopwatch();
  Timer? _uiTimer;
  Timer? _simTimer;
  TrackPoint? _lastAccepted;
  double _simT = 0, _simD = 0, _simNextPoint = 0;
  int _seed = 1;
  final _rng = math.Random();
  int _lastInterval = 5;

  /// Start a free run. Tries real GPS unless [preferSimulated], and falls
  /// back to simulated GPS when it isn't available.
  Future<void> start() async {
    if (_state != TrackingState.idle) return;
    _resetSession();
    _state = TrackingState.starting;
    _activityId = ActivityStore.newId();
    _startedAt = DateTime.now();
    _shareToken = ActivityStore.newShareToken();
    notifyListeners();

    var simulate = _preferSimulated;
    if (!simulate) simulate = !await _startRealGps();
    if (_state != TrackingState.starting) return; // stopped while asking for permission
    _state = TrackingState.running;
    if (simulate) _startSimulated();
    _startUploader();
    if (settings.voiceCoach) voice.speak(tr('Run started. Have a good one!'));
    notifyListeners();
  }

  void pause() {
    if (_state != TrackingState.running) return;
    _state = TrackingState.paused;
    _moving.stop();
    _posSub?.cancel();
    _posSub = null;
    _simTimer?.cancel();
    _simTimer = null;
    notifyListeners();
  }

  void resume() {
    if (_state != TrackingState.paused) return;
    _state = TrackingState.running;
    _lastAccepted = null; // no straight line across the pause
    _paceWindow.clear();
    if (_simulatedSession) {
      _simTimer = Timer.periodic(const Duration(seconds: 1), (_) => _simTick());
    } else {
      _moving.start();
      _subscribe();
    }
    notifyListeners();
  }

  /// Stop and save. Returns the saved activity (null if nothing recorded).
  Activity? stop() {
    if (_state == TrackingState.idle) return null;
    _cancelSources();
    _stopUploader();
    store.persistQueue();
    final id = _activityId!;
    Activity? saved;
    if (_track.length >= 2) {
      final a = Activity(
        id: id,
        mode: ActivityMode.free,
        title: _titleFor(_startedAt!, _simulatedSession),
        startedAt: _startedAt!,
        endedAt: DateTime.now(),
        distanceM: _distanceM,
        movingS: _movingS,
        points: List.of(_track),
        splitsS: List.of(_splits),
        privacy: settings.privacy,
        shareToken: _shareToken,
        simulated: _simulatedSession,
      );
      store.save(a);
      saved = a;
      if (settings.voiceCoach) {
        voice.speak(tr('Run saved. {dist} kilometres in {time}.', {
          'dist': (_distanceM / 1000).toStringAsFixed(2),
          'time': sayDuration(_movingS),
        }));
      }
    } else {
      store.dropQueued(id);
    }
    _state = TrackingState.idle;
    notifyListeners();
    // Last upload attempt; anything left stays queued for next time.
    unawaited(flush());
    return saved;
  }

  /// Throw the run away (nothing saved, queued points dropped).
  void discard() {
    if (_state == TrackingState.idle) return;
    _cancelSources();
    _stopUploader();
    if (_activityId != null) store.dropQueued(_activityId!);
    _state = TrackingState.idle;
    notifyListeners();
  }

  void _resetSession() {
    _track.clear();
    _splits.clear();
    _paceWindow.clear();
    _distanceM = 0;
    _movingS = 0;
    _prevMovingS = 0;
    _lastSplitAt = 0;
    _currentPace = null;
    _lastAccepted = null;
    _weakSignal = false;
    _sourceNote = null;
    _simulatedSession = false;
    _moving
      ..stop()
      ..reset();
  }

  void _cancelSources() {
    _posSub?.cancel();
    _posSub = null;
    _simTimer?.cancel();
    _simTimer = null;
    _uiTimer?.cancel();
    _uiTimer = null;
    _moving.stop();
  }

  static String _titleFor(DateTime t, bool simulated) {
    final h = t.hour;
    final part = h < 5
        ? tr('Night run')
        : h < 12
            ? tr('Morning run')
            : h < 17
                ? tr('Afternoon run')
                : h < 21
                    ? tr('Evening run')
                    : tr('Night run');
    return simulated ? '$part · KLCC Park' : part;
  }

  // ------------------------------------------------------------- real GPS

  Future<bool> _startRealGps() async {
    final ready = await locationReadiness(request: true);
    switch (ready) {
      case LocationReadiness.always || LocationReadiness.whileInUse:
        break;
      case LocationReadiness.serviceOff:
        _sourceNote = tr('Location services are off, so this run uses simulated GPS.');
        return false;
      case LocationReadiness.denied || LocationReadiness.deniedForever:
        _sourceNote = tr('Location permission denied, so this run uses simulated GPS.');
        return false;
      case LocationReadiness.unsupported:
        _sourceNote = tr('GPS isn\'t available here, so this run uses simulated GPS.');
        return false;
    }
    if (!_subscribe()) {
      _sourceNote = tr('GPS isn\'t available here, so this run uses simulated GPS.');
      return false;
    }
    _simulatedSession = false;
    _moving.start();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_state != TrackingState.running) return;
      _movingS = _moving.elapsedMilliseconds / 1000;
      notifyListeners();
    });
    return true;
  }

  LocationSettings _locationSettings() {
    final saver = settings.batterySaver;
    final interval = Duration(seconds: settings.gpsIntervalS);
    if (kIsWeb) return WebSettings(accuracy: LocationAccuracy.best, maximumAge: Duration.zero);
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: saver ? LocationAccuracy.high : LocationAccuracy.best,
          distanceFilter: 0,
          intervalDuration: interval,
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationTitle: tr('RunLah is tracking your run'),
            notificationText: tr('Distance and pace keep updating with the screen off.'),
            notificationChannelName: tr('Run tracking'),
            enableWakeLock: true,
            setOngoing: true,
            color: const Color(0xFFE8930C),
          ),
        );
      case TargetPlatform.iOS || TargetPlatform.macOS:
        return AppleSettings(
          accuracy: saver ? LocationAccuracy.medium : LocationAccuracy.best,
          activityType: ActivityType.fitness,
          distanceFilter: saver ? 10 : 3,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
          allowBackgroundLocationUpdates: true,
        );
      default:
        return LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 0);
    }
  }

  bool _subscribe() {
    try {
      _posSub?.cancel();
      _posSub = Geolocator.getPositionStream(locationSettings: _locationSettings()).listen(
        _onPosition,
        onError: (Object _) {
          _weakSignal = true;
          notifyListeners();
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  void _onSettings() {
    final i = settings.gpsIntervalS;
    if (i == _lastInterval) return;
    _lastInterval = i;
    // Battery saver toggled mid-run: re-subscribe with the new interval.
    if (_state == TrackingState.running && !_simulatedSession && _posSub != null) _subscribe();
  }

  void _onPosition(Position p) {
    if (_state != TrackingState.running) return;
    if (p.accuracy > 35) {
      _weakSignal = true;
      notifyListeners();
      return;
    }
    _weakSignal = false;
    final t = p.timestamp.toUtc();
    final prev = _lastAccepted;
    // Downsample to the chosen interval (iOS has no time-based interval).
    if (prev != null && t.difference(prev.t).inMilliseconds < settings.gpsIntervalS * 1000 - 600) return;
    _movingS = _moving.elapsedMilliseconds / 1000;
    final pt = TrackPoint(t: t, lat: p.latitude, lng: p.longitude, acc: p.accuracy, spd: math.max(0, p.speed));
    if (prev != null) {
      final step = haversine(prev.latLng, pt.latLng);
      final dt = math.max(1, t.difference(prev.t).inMilliseconds / 1000);
      // Ignore jitter while standing still and impossible jumps.
      if (step > math.max(3, p.accuracy * 0.5) && step / dt < 12) _addDistance(step);
    }
    _prevMovingS = _movingS;
    _accept(pt);
  }

  // -------------------------------------------------------- simulated GPS

  void _startSimulated() {
    _simulatedSession = true;
    _seed = _rng.nextInt(1000);
    _simT = 0;
    _simD = 0;
    _simNextPoint = 0;
    _emitSimPoint(DemoTracks.speedAt(simulatedPaceS, 0, _seed));
    _simNextPoint = settings.gpsIntervalS.toDouble();
    _simTimer = Timer.periodic(const Duration(seconds: 1), (_) => _simTick());
  }

  void _simTick() {
    if (_state != TrackingState.running) return;
    var remaining = _simSpeed;
    while (remaining > 0) {
      final dt = math.min(1.0, remaining);
      remaining -= dt;
      final v = DemoTracks.speedAt(simulatedPaceS, _simT, _seed);
      _prevMovingS = _movingS;
      _simT += dt;
      _simD += v * dt;
      _movingS = _simT;
      _addDistance(v * dt);
      if (_simT >= _simNextPoint) {
        _emitSimPoint(v);
        _simNextPoint += settings.gpsIntervalS;
      }
    }
    notifyListeners();
  }

  void _emitSimPoint(double v) {
    final p = DemoTracks.onLoop(DemoTracks.klccPark, _simD);
    _accept(TrackPoint(
      t: _startedAt!.toUtc().add(Duration(milliseconds: (_simT * 1000).round())),
      lat: p.latitude + (_rng.nextDouble() - 0.5) * 0.00001,
      lng: p.longitude + (_rng.nextDouble() - 0.5) * 0.00001,
      acc: 4 + _rng.nextDouble() * 4,
      spd: v,
    ));
  }

  // ----------------------------------------------------- shared bookkeeping

  void _accept(TrackPoint pt) {
    _track.add(pt);
    _lastAccepted = pt;
    store.enqueue(_activityId!, [pt]);
    _paceWindow.add((_movingS, _distanceM));
    final window = math.max(30.0, settings.gpsIntervalS * 3.0);
    while (_paceWindow.length > 2 && _movingS - _paceWindow.first.$1 > window) {
      _paceWindow.removeFirst();
    }
    final (t0, d0) = _paceWindow.first;
    final dd = _distanceM - d0;
    _currentPace = dd > 25 ? (_movingS - t0) / (dd / 1000) : _currentPace;
    if (!_simulatedSession) notifyListeners();
  }

  void _addDistance(double step) {
    final before = _distanceM;
    _distanceM += step;
    while (_distanceM >= (_splits.length + 1) * 1000) {
      final mark = (_splits.length + 1) * 1000.0;
      final f = (mark - before) / (_distanceM - before);
      final cross = _prevMovingS + (_movingS - _prevMovingS) * f;
      _splits.add(cross - _lastSplitAt);
      _lastSplitAt = cross;
      _announceKm();
    }
  }

  DateTime _lastSpoken = DateTime.fromMillisecondsSinceEpoch(0);

  void _announceKm() {
    if (!settings.voiceCoach) return;
    final now = DateTime.now();
    // At high demo speeds kilometres fly by: at most one line every 3 s.
    if (now.difference(_lastSpoken) < const Duration(seconds: 3)) return;
    _lastSpoken = now;
    voice.speak(tr('{km} kilometres. Last kilometre {split}. Average pace {pace} per kilometre.', {
      'km': _splits.length,
      'split': sayDuration(_splits.last),
      'pace': sayDuration(avgPaceSPerKm),
    }));
  }

  // ------------------------------------------------------------- uploader

  Timer? _uploadTimer;
  bool _flushing = false;
  bool _deviceOnline = true;
  bool _simulateOffline = false;
  int _uploaded = 0;
  int _batches = 0;
  DateTime? _lastUploadAt;
  String? _lastUploadError;

  /// Device has a network and the demo "airplane mode" is off.
  bool get online => _deviceOnline && !_simulateOffline;
  bool get uploading => _flushing;
  int get uploadedPoints => _uploaded;
  int get uploadedBatches => _batches;
  DateTime? get lastUploadAt => _lastUploadAt;
  String? get lastUploadError => _lastUploadError;
  ValueListenable<int> get queued => store.queueSize;

  /// Demo switch: pretend the phone lost signal so points queue up.
  bool get simulateOffline => _simulateOffline;
  set simulateOffline(bool v) {
    if (v == _simulateOffline) return;
    _simulateOffline = v;
    notifyListeners();
    if (!v) unawaited(flush());
  }

  void _startUploader() {
    _uploadTimer?.cancel();
    _uploadTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _refreshConnectivity();
      flush();
    });
    _refreshConnectivity();
  }

  void _stopUploader() {
    _uploadTimer?.cancel();
    _uploadTimer = null;
  }

  Future<void> _refreshConnectivity() async {
    if (_inWidgetTest) return;
    try {
      final r = await Connectivity().checkConnectivity();
      final on = !r.contains(ConnectivityResult.none);
      if (on != _deviceOnline) {
        _deviceOnline = on;
        notifyListeners();
        if (on) unawaited(flush());
      }
    } catch (_) {
      // Unknown: keep the last state.
    }
  }

  /// Upload queued points now (batches of ≤500) while online.
  Future<void> flush() async {
    if (_flushing || !online || store.queuedCount == 0) return;
    _flushing = true;
    notifyListeners();
    try {
      for (var i = 0; i < 20 && online; i++) {
        final b = store.nextBatch(max: PointsSink.maxBatch);
        if (b == null) break;
        final ack = await sink.upload(b.activityId, b.points);
        store.ack(b.activityId, ack.lastT ?? b.points.last.t);
        _uploaded += ack.accepted;
        _batches++;
        _lastUploadAt = DateTime.now();
        _lastUploadError = null;
      }
    } catch (e) {
      _lastUploadError = '$e';
    } finally {
      _flushing = false;
      notifyListeners();
    }
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    settings.removeListener(_onSettings);
    _cancelSources();
    _stopUploader();
    super.dispose();
  }
}

/// "1 hour 36 minutes 15 seconds" for the voice coach.
String sayDuration(num? seconds) {
  if (seconds == null || seconds.isNaN || seconds.isInfinite || seconds <= 0) return '';
  final s = seconds.round();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  return [
    if (h > 0) h == 1 ? tr('1 hour') : tr('{n} hours', {'n': h}),
    if (m > 0) m == 1 ? tr('1 minute') : tr('{n} minutes', {'n': m}),
    if (sec > 0 && h == 0) sec == 1 ? tr('1 second') : tr('{n} seconds', {'n': sec}),
  ].join(' ');
}
