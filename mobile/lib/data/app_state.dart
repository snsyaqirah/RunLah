import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/format.dart';
import '../core/l10n/i18n.dart';
import 'insights/insights_engine.dart';
import 'models.dart';
import 'sim/race_sim.dart';

/// User settings, persisted on the device.
class SettingsController extends ChangeNotifier {
  SettingsController(this._prefs) {
    _units = Units.values.byName(_prefs.getString('units') ?? 'km');
    _themeMode = ThemeMode.values.byName(_prefs.getString('theme') ?? 'system');
    _privacy = Privacy.values.byName(_prefs.getString('privacy') ?? 'linkOnly');
    _resultsName = ResultsName.values.byName(_prefs.getString('resultsName') ?? 'full');
    _batterySaver = _prefs.getBool('batterySaver') ?? false;
    _voiceCoach = _prefs.getBool('voiceCoach') ?? true;
    _readCheers = _prefs.getBool('readCheers') ?? true;
    _targetTimeS = _prefs.getInt('targetTimeS') ?? 6000;
    _displayName = _prefs.getString('displayName') ?? 'Arep';
    I18n.instance.lang = _prefs.getString('lang') ?? 'en';
  }

  final SharedPreferences _prefs;
  SharedPreferences get prefs => _prefs;

  late Units _units;
  late ThemeMode _themeMode;
  late Privacy _privacy;
  late ResultsName _resultsName;
  late bool _batterySaver;
  late bool _voiceCoach;
  late bool _readCheers;
  late int _targetTimeS;
  late String _displayName;

  Units get units => _units;
  ThemeMode get themeMode => _themeMode;
  Privacy get privacy => _privacy;
  ResultsName get resultsName => _resultsName;
  bool get batterySaver => _batterySaver;

  /// Spoken km splits during a run.
  bool get voiceCoach => _voiceCoach;

  /// Read incoming cheer messages aloud mid-run.
  bool get readCheers => _readCheers;

  /// Goal time for the race (target time alerts).
  int get targetTimeS => _targetTimeS;
  String get displayName => _displayName;
  String get lang => I18n.instance.lang;

  /// GPS interval in seconds: 5 s normally, 15 s in battery saver (PRD 12.1).
  int get gpsIntervalS => _batterySaver ? 15 : 5;

  set units(Units v) => _set(() => _units = v, () => _prefs.setString('units', v.name));
  set themeMode(ThemeMode v) => _set(() => _themeMode = v, () => _prefs.setString('theme', v.name));
  set privacy(Privacy v) => _set(() => _privacy = v, () => _prefs.setString('privacy', v.name));
  set resultsName(ResultsName v) => _set(() => _resultsName = v, () => _prefs.setString('resultsName', v.name));
  set batterySaver(bool v) => _set(() => _batterySaver = v, () => _prefs.setBool('batterySaver', v));
  set voiceCoach(bool v) => _set(() => _voiceCoach = v, () => _prefs.setBool('voiceCoach', v));
  set readCheers(bool v) => _set(() => _readCheers = v, () => _prefs.setBool('readCheers', v));
  set targetTimeS(int v) => _set(() => _targetTimeS = v, () => _prefs.setInt('targetTimeS', v));
  set displayName(String v) => _set(() => _displayName = v, () => _prefs.setString('displayName', v));
  set lang(String v) => _set(() => I18n.instance.lang = v, () => _prefs.setString('lang', v));

  void _set(VoidCallback apply, Future<bool> Function() persist) {
    apply();
    persist();
    notifyListeners();
  }
}

/// Runners the user follows as Cheer. Feeds [RaceSim.watched] so the
/// simulator emits their checkpoint and finish events.
class FollowsController extends ChangeNotifier {
  FollowsController(this.sim, this._prefs) {
    final saved = _prefs.getStringList('follows');
    _ids = saved == null ? [...sim.friendIds] : [for (final s in saved) int.parse(s)];
    _muted = {...?_prefs.getStringList('followsMuted')?.map(int.parse)};
    sim.setWatched(_ids);
  }

  final RaceSim sim;
  final SharedPreferences _prefs;
  late List<int> _ids;
  late Set<int> _muted;

  List<int> get ids => List.unmodifiable(_ids);
  bool isFollowing(int id) => _ids.contains(id);

  /// Push notifications on for this runner.
  bool notifies(int id) => !_muted.contains(id);

  void follow(int id) {
    if (_ids.contains(id) || id == sim.youId) return;
    _ids.add(id);
    _save();
  }

  void unfollow(int id) {
    _ids.remove(id);
    _save();
  }

  /// "Delete my data": stop following everyone.
  void clearAll() {
    _ids.clear();
    _muted.clear();
    _save();
  }

  void setNotify(int id, bool on) {
    on ? _muted.remove(id) : _muted.add(id);
    _save();
  }

  void _save() {
    sim.setWatched(_ids);
    _prefs.setStringList('follows', [for (final i in _ids) '$i']);
    _prefs.setStringList('followsMuted', [for (final i in _muted) '$i']);
    notifyListeners();
  }
}

/// Keeps an up-to-date [InsightsSnapshot] for the current race clock.
///
/// While the race is live it recomputes at most every 1.5 s of real time
/// and only after 30 s of race time have passed (provisional results, like
/// the server's results job). Status changes and jumps recompute at once.
class InsightsController extends ChangeNotifier {
  InsightsController(this.sim) {
    sim.addListener(_onSimChanged);
    sim.clock.addListener(_onClock);
    _recompute();
  }

  final RaceSim sim;
  late InsightsSnapshot _snapshot;
  InsightsSnapshot get snapshot => _snapshot;

  RankBasis _basis = RankBasis.net;
  RankBasis get basis => _basis;
  set basis(RankBasis b) {
    if (b == _basis) return;
    _basis = b;
    _recompute();
  }

  DateTime _lastRun = DateTime.fromMillisecondsSinceEpoch(0);
  double _lastRaceTime = double.negativeInfinity;
  Timer? _pending;
  RaceStatus _lastStatus = RaceStatus.preRace;
  bool _lastOfficial = false;

  void _onSimChanged() {
    if (sim.status != _lastStatus || sim.official != _lastOfficial || (sim.raceTime - _lastRaceTime).abs() > 120) {
      _recompute();
    }
  }

  void _onClock() {
    if (sim.status == RaceStatus.preRace) return;
    if ((sim.raceTime - _lastRaceTime).abs() < 30) return;
    final since = DateTime.now().difference(_lastRun);
    if (since >= const Duration(milliseconds: 1500)) {
      _recompute();
    } else {
      _pending ??= Timer(const Duration(milliseconds: 1500) - since, () {
        _pending = null;
        _recompute();
      });
    }
  }

  void _recompute() {
    _pending?.cancel();
    _pending = null;
    _snapshot = sim.insights(basis: _basis);
    _lastRun = DateTime.now();
    _lastRaceTime = sim.raceTime;
    _lastStatus = sim.status;
    _lastOfficial = sim.official;
    notifyListeners();
  }

  @override
  void dispose() {
    _pending?.cancel();
    sim.removeListener(_onSimChanged);
    sim.clock.removeListener(_onClock);
    super.dispose();
  }
}

/// Which bottom-nav tab is showing.
enum AppTab { home, run, cheer, results, me }

class ShellController extends ChangeNotifier {
  AppTab _tab = AppTab.home;
  AppTab get tab => _tab;
  set tab(AppTab t) {
    if (t == _tab) return;
    _tab = t;
    notifyListeners();
  }
}
