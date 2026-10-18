import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart' show ChangeNotifier, ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/format.dart';
import '../core/l10n/i18n.dart';
import 'activity_store.dart';
import 'app_state.dart';
import 'insights/insights_engine.dart';
import 'models.dart';
import 'sim/race_sim.dart';

// ------------------------------------------------------------------ distances

/// Distances we keep personal bests for.
enum PbDistance { k5, k10, half, full }

extension PbDistanceX on PbDistance {
  double get metres => switch (this) {
        PbDistance.k5 => 5000,
        PbDistance.k10 => 10000,
        PbDistance.half => 21097.5,
        PbDistance.full => 42195,
      };

  String get label => switch (this) {
        PbDistance.k5 => '5K',
        PbDistance.k10 => '10K',
        PbDistance.half => '21.1K',
        PbDistance.full => '42.2K',
      };
}

/// The PB distance a race counts for (within 2 %), or null.
PbDistance? pbDistanceFor(double metres) {
  for (final d in PbDistance.values) {
    if ((metres - d.metres).abs() <= d.metres * 0.02) return d;
  }
  return null;
}

// ------------------------------------------------------------------ passport

enum EntrySource {
  /// Imported from an organiser's published results (before RunLah).
  imported,

  /// Tracked live with RunLah.
  runlah,
}

/// One stamp in the race passport.
class PassportEntry {
  const PassportEntry({
    required this.id,
    required this.name,
    required this.date,
    required this.distanceM,
    this.subtitle,
    this.city,
    this.netS,
    this.place,
    this.of,
    this.source = EntrySource.imported,
    this.demo = false,
    this.status,
    this.official = false,
    this.participantId,
  });

  final String id;
  final String name;

  /// "Half Marathon", "21K", "10K"...
  final String? subtitle;
  final String? city;
  final DateTime date;
  final double distanceM;
  final double? netS;
  final int? place;
  final int? of;
  final EntrySource source;
  final bool demo;

  /// Only for the race tracked with RunLah.
  final ResultStatus? status;
  final bool official;
  final int? participantId;

  bool get isCurrent => source == EntrySource.runlah;
  bool get finished => netS != null;
  PbDistance? get pbDistance => pbDistanceFor(distanceM);
  double? get topPct => (place != null && of != null && of! > 0) ? (place! - 1) / of! * 100 : null;
  double? get paceSPerKm => netS == null ? null : netS! / (distanceM / 1000);

  Map<String, Object?> toJson() => {
        'name': name,
        'subtitle': ?subtitle,
        'city': ?city,
        'date': date.toIso8601String().substring(0, 10),
        'distance_m': distanceM,
        'net_s': ?netS,
        'net': ?(netS == null ? null : fmtDuration(netS)),
        'place': ?place,
        'of': ?of,
        'source': source.name,
        if (isCurrent) 'status': status?.name,
        if (isCurrent) 'official': official,
        if (demo) 'demo': true,
      };
}

/// Arep's races before RunLah — imported results. DEMO DATA: believable
/// times for the demo story, not real published results.
final List<PassportEntry> demoHistory = [
  PassportEntry(
    id: 'bj5k-2026',
    name: 'Bukit Jalil 5K 2026',
    subtitle: '5K',
    city: 'Kuala Lumpur',
    date: DateTime(2026, 3, 8),
    distanceM: 5000,
    netS: 20 * 60 + 47,
    place: 58,
    of: 2140,
    demo: true,
  ),
  PassportEntry(
    id: 'pbim-2025',
    name: 'Penang Bridge International Marathon 2025',
    subtitle: '21K',
    city: 'Penang',
    date: DateTime(2025, 11, 30),
    distanceM: 21097.5,
    netS: 1 * 3600 + 44 * 60 + 30,
    place: 702,
    of: 9860,
    demo: true,
  ),
  PassportEntry(
    id: 'klscm-2025',
    name: 'KL Standard Chartered Marathon 2025',
    subtitle: 'Half Marathon',
    city: 'Kuala Lumpur',
    date: DateTime(2025, 10, 5),
    distanceM: 21097.5,
    netS: 1 * 3600 + 41 * 60 + 2,
    place: 486,
    of: 10212,
    demo: true,
  ),
  PassportEntry(
    id: 'ptj-night-2025',
    name: 'Putrajaya Night Run 2025',
    subtitle: '10K',
    city: 'Putrajaya',
    date: DateTime(2025, 7, 12),
    distanceM: 10000,
    netS: 44 * 60 + 12,
    place: 131,
    of: 4380,
    demo: true,
  ),
  PassportEntry(
    id: 'twincity-2024',
    name: 'Twincity Half Marathon 2024',
    subtitle: 'Half Marathon',
    date: DateTime(2024, 6, 9),
    distanceM: 21097.5,
    netS: 1 * 3600 + 48 * 60 + 55,
    place: 864,
    of: 6150,
    demo: true,
  ),
];

// ------------------------------------------------------------ personal bests

class PersonalBest {
  const PersonalBest({required this.distance, this.entry, this.previous, this.isNew = false, this.fromFreeRun = false});
  final PbDistance distance;

  /// The race (or free run) that holds the PB. Null = never raced this distance.
  final PassportEntry? entry;

  /// The PB that was beaten by the current race (when [isNew]).
  final PassportEntry? previous;

  /// The race tracked with RunLah just beat the stored PB.
  final bool isNew;
  final bool fromFreeRun;

  double? get timeS => entry?.netS;
  double? get improvementS => (isNew && previous?.netS != null && entry?.netS != null) ? previous!.netS! - entry!.netS! : null;
}

// --------------------------------------------------------------- free runs

/// Summary of saved free runs, read from the Run feature's [ActivityStore]
/// (see [Achievements.readStore]). Another source can be plugged in with
/// `achievements.freeRunReader = (store) => FreeRunStats(...)`.
class FreeRunStats {
  const FreeRunStats({this.runs = 0, this.totalM = 0, this.thisYearM = 0, this.best = const {}});
  static const none = FreeRunStats();

  final int runs;
  final double totalM;
  final double thisYearM;

  /// Fastest stretch of each PB distance inside a free run (from km splits).
  final Map<PbDistance, ({double s, String title, DateTime date})> best;
}

typedef FreeRunStatsReader = FreeRunStats Function(ActivityStore store);

// ------------------------------------------------------------------- badges

enum BadgeId {
  halfFinisher,
  sub140,
  top2,
  categoryTop100,
  overtaker,
  negativeSplit,
  dawnPatrol,
  cheeredOn,
  firstRunLah,
  pbBreaker,
  targetSmashed,
  fiveHalves,
  firstFreeRun,
  fiftyKmClub,
}

class BadgeState {
  const BadgeState({
    required this.id,
    required this.title,
    required this.description,
    required this.hint,
    required this.unlocked,
    this.progress = 0,
    this.isNew = false,
  });
  final BadgeId id;
  final String title;

  /// How to earn it.
  final String description;

  /// Where you stand: "Best so far 1:41:02 · 1:02 to go", "172nd of 11,103".
  final String hint;
  final bool unlocked;

  /// 0–1 towards unlocking (1 when unlocked).
  final double progress;

  /// Unlocked but the celebration hasn't been shown yet.
  final bool isNew;

  bool get freeRun => id == BadgeId.firstFreeRun || id == BadgeId.fiftyKmClub;
}

// ------------------------------------------------------------------ wrapped

class WrappedStats {
  const WrappedStats({
    required this.year,
    required this.races,
    required this.kmRacedM,
    required this.best,
    required this.runnersPassed,
    required this.passedBeforeHalf,
    required this.quarters,
    required this.fastestQuarter,
    required this.cheerFriend,
    required this.cheerCount,
    required this.cheerQuote,
    required this.totalCheers,
    required this.crew,
    required this.newPb,
    required this.currentFinished,
    this.freeRunCount = 0,
    this.freeRunM = 0,
  });
  final int year;

  /// Finished races this year, newest first.
  final List<PassportEntry> races;
  final double kmRacedM;
  final PassportEntry? best;

  /// Overtakes in the race tracked with RunLah (null until you finish).
  final int? runnersPassed;
  final int? passedBeforeHalf;
  final List<SectionResult> quarters;

  /// Index into [quarters] of the fastest one.
  final int? fastestQuarter;
  final String? cheerFriend;
  final int cheerCount;
  final String? cheerQuote;
  final int totalCheers;

  /// Friends you follow (fallback when nobody has cheered yet).
  final List<String> crew;
  final PersonalBest? newPb;
  final bool currentFinished;

  /// Free runs saved this year (Run tab) and their distance.
  final int freeRunCount;
  final double freeRunM;
}

// -------------------------------------------------------------- profile view

/// Everything the Me tab shows, computed from the Insights snapshot,
/// settings, the demo history and (later) saved free runs.
class ProfileView {
  const ProfileView({
    required this.passport,
    required this.current,
    required this.bests,
    required this.badges,
    required this.wrapped,
    required this.racesTotal,
    required this.kmThisYearM,
    required this.year,
  });

  /// Newest first; the race tracked with RunLah is always first.
  final List<PassportEntry> passport;
  final PassportEntry current;
  final Map<PbDistance, PersonalBest> bests;
  final List<BadgeState> badges;
  final WrappedStats wrapped;
  final int racesTotal;
  final double kmThisYearM;
  final int year;

  int get unlockedCount => badges.where((b) => b.unlocked).length;
  List<BadgeState> get unseen => [for (final b in badges) if (b.isNew) b];
  PersonalBest get halfPb => bests[PbDistance.half]!;
}

// ------------------------------------------------------------- achievements

/// Race passport, personal bests, badges and Race Wrapped for the user.
///
/// Stateless maths over the Insights snapshot plus a little persisted
/// state: which badge unlocks were already celebrated, and the club name.
class Achievements extends ChangeNotifier {
  Achievements(this.prefs, this.sim, this.store) {
    final seen = prefs.getStringList(_seenKey);
    _seen = seen == null ? _dayOneSeen() : seen.toSet();
    if (seen == null) prefs.setStringList(_seenKey, _seen.toList());
    _club = prefs.getString(_clubKey) ?? defaultClub;
    // Keep the simulated "you" in step with the saved results-name setting.
    final rn = prefs.getString('resultsName');
    for (final v in ResultsName.values) {
      if (v.name == rn) sim.you.resultsName = v;
    }
    store.addListener(_onStoreChanged);
  }

  final SharedPreferences prefs;
  final RaceSim sim;
  final ActivityStore store;

  static const appVersion = '0.1.0';
  static const defaultClub = 'RunLah Crew KL';
  static const _seenKey = 'ach.seenBadges';
  static const _clubKey = 'profile.club';

  /// Badges already earned on day one (imported history, sample runs):
  /// no fireworks for those.
  Set<String> _dayOneSeen() {
    final free = freeRuns;
    return {
      BadgeId.halfFinisher.name,
      if (free.runs >= 1) BadgeId.firstFreeRun.name,
      if (free.totalM >= 50000) BadgeId.fiftyKmClub.name,
    };
  }

  late Set<String> _seen;
  late String _club;
  int _version = 0;

  String get club => _club;
  set club(String v) {
    final c = v.trim();
    _club = c.isEmpty ? defaultClub : c;
    prefs.setString(_clubKey, _club);
    _changed();
  }

  /// Link people scan to follow you live.
  String get followLink => 'runlah://follow/${sim.you.bib}';

  FreeRunStatsReader? _freeRunReader;

  /// Plug point for the Run feature: summarise [ActivityStore]'s saved runs.
  set freeRunReader(FreeRunStatsReader? reader) {
    _freeRunReader = reader;
    _changed();
  }

  FreeRunStats get freeRuns {
    try {
      return (_freeRunReader ?? readStore)(store);
    } catch (_) {
      return FreeRunStats.none;
    }
  }

  /// Default free-run source: the free runs saved in [ActivityStore].
  FreeRunStats readStore(ActivityStore store) {
    final year = sim.event.date.year;
    var total = 0.0, thisYear = 0.0;
    final best = <PbDistance, ({double s, String title, DateTime date})>{};
    final runs = store.freeRuns;
    for (final a in runs) {
      total += a.distanceM;
      if (a.startedAt.year == year) thisYear += a.distanceM;
      final splits = a.splitsS;
      for (final d in PbDistance.values) {
        // Fastest run of k consecutive whole-km splits, scaled to the exact distance.
        final k = (d.metres / 1000).floor();
        if (splits.length < k) continue;
        var sum = 0.0;
        for (var i = 0; i < k; i++) {
          sum += splits[i];
        }
        var fastest = sum;
        for (var i = k; i < splits.length; i++) {
          sum += splits[i] - splits[i - k];
          fastest = math.min(fastest, sum);
        }
        final t = fastest * d.metres / (k * 1000);
        final prev = best[d];
        if (prev == null || t < prev.s) best[d] = (s: t, title: a.title, date: a.startedAt);
      }
    }
    return FreeRunStats(runs: runs.length, totalM: total, thisYearM: thisYear, best: best);
  }

  bool isSeen(BadgeId id) => _seen.contains(id.name);

  /// Record that the unlock celebration for [ids] has been shown.
  void markSeen(Iterable<BadgeId> ids) {
    final before = _seen.length;
    _seen.addAll(ids.map((b) => b.name));
    if (_seen.length == before) return;
    prefs.setStringList(_seenKey, _seen.toList());
    _changed();
  }

  void _onStoreChanged() => _changed();

  void _changed() {
    _version++;
    _cache = null;
    notifyListeners();
  }

  // ------------------------------------------------------------ compute

  ProfileView? _cache;
  InsightsSnapshot? _cacheSnap;
  (int, int, String, int)? _cacheKey;

  /// Profile numbers for [snap]. Cheap to call on every build (memoised).
  ProfileView view(InsightsSnapshot snap, {required int targetTimeS}) {
    final key = (targetTimeS, sim.cheersFor(sim.youId).length, I18n.instance.lang, _version);
    if (_cache != null && identical(_cacheSnap, snap) && _cacheKey == key) return _cache!;
    _cacheSnap = snap;
    _cacheKey = key;
    return _cache = _compute(snap, targetTimeS);
  }

  ProfileView _compute(InsightsSnapshot snap, int targetTimeS) {
    final race = sim.race;
    final event = sim.event;
    final you = sim.youId;
    final r = snap.result(you);
    final finished = r.status == ResultStatus.finished && r.netS != null;
    final started = r.status != ResultStatus.dns;
    final current = PassportEntry(
      id: 'runlah-${race.id}',
      name: event.name,
      subtitle: race.name,
      city: event.city,
      date: event.date,
      distanceM: race.distanceM,
      netS: finished ? r.netS : null,
      place: finished ? r.overall?.place : null,
      of: finished ? r.overall?.of : null,
      source: EntrySource.runlah,
      demo: event.isDemo,
      status: r.status,
      official: snap.official,
      participantId: you,
    );
    final free = freeRuns;

    // ---- personal bests
    final bests = <PbDistance, PersonalBest>{};
    for (final d in PbDistance.values) {
      PassportEntry? prev;
      for (final e in demoHistory) {
        if (e.pbDistance == d && e.netS != null && (prev == null || e.netS! < prev.netS!)) prev = e;
      }
      var fromFree = false;
      final fr = free.best[d];
      if (fr != null && (prev == null || fr.s < prev.netS!)) {
        prev = PassportEntry(id: 'free-${d.name}', name: fr.title.isEmpty ? tr('Free run') : fr.title, subtitle: tr('Free run'), date: fr.date, distanceM: d.metres, netS: fr.s);
        fromFree = true;
      }
      if (finished && current.pbDistance == d && (prev == null || current.netS! < prev.netS!)) {
        bests[d] = PersonalBest(distance: d, entry: current, previous: prev, isNew: prev != null);
      } else {
        bests[d] = PersonalBest(distance: d, entry: prev, fromFreeRun: fromFree);
      }
    }

    // ---- sections of the race tracked with RunLah
    final halves = finished ? snap.sections(you, SectionSet.halves) : const <SectionResult>[];
    final quarters = finished ? snap.sections(you, SectionSet.quarters) : const <SectionResult>[];
    final halfIndex = race.checkpointNear(0.5);
    int? passedBeforeHalf;
    if (halves.isNotEmpty && halves.first.toIndex == halfIndex) {
      passedBeforeHalf = halves.first.passed;
    } else if (started) {
      // Live: add up the checkpoint sections done so far in the first half.
      var n = 0;
      for (final s in snap.sections(you)) {
        if (s.toIndex <= halfIndex) n += s.passed;
      }
      passedBeforeHalf = n;
    }

    // ---- cheers
    final cheers = sim.cheersFor(you);
    final byFriend = <String, int>{};
    for (final c in cheers) {
      byFriend[c.from] = (byFriend[c.from] ?? 0) + 1;
    }
    String? topFriend;
    for (final e in byFriend.entries) {
      if (topFriend == null || e.value > byFriend[topFriend]!) topFriend = e.key;
    }
    final quote = topFriend == null ? null : cheers.firstWhere((c) => c.from == topFriend).body;

    // ---- badges
    final halfTimes = [
      for (final e in demoHistory)
        if (e.pbDistance == PbDistance.half && e.netS != null) e.netS!,
      if (finished && current.pbDistance == PbDistance.half) current.netS!,
    ];
    final bestHalf = halfTimes.isEmpty ? null : halfTimes.reduce(math.min);
    final halfPb = bests[PbDistance.half]!;
    final currentPb = current.pbDistance == null ? null : bests[current.pbDistance!];
    final newPb = (currentPb != null && currentPb.isNew) ? currentPb : null;

    BadgeState badge(BadgeId id, String title, String description, {required bool unlocked, required String hint, double progress = 0}) =>
        BadgeState(
          id: id,
          title: title,
          description: description,
          hint: hint,
          unlocked: unlocked,
          progress: unlocked ? 1 : progress.clamp(0.0, 0.99),
          isNew: unlocked && !_seen.contains(id.name),
        );

    final gun = fmtClock(race.scheduledStart);
    final cat = race.categoryById(sim.you.categoryId).name;
    final badges = <BadgeState>[
      badge(
        BadgeId.halfFinisher,
        tr('Half-marathon finisher'),
        tr('Finish a 21.1 km race.'),
        unlocked: halfTimes.isNotEmpty,
        hint: halfTimes.isEmpty ? tr('No half marathons yet') : tr('{n} halves finished', {'n': halfTimes.length}),
      ),
      badge(
        BadgeId.sub140,
        tr('Sub-1:40 half'),
        tr('Run a half marathon in under 1 hour 40 minutes.'),
        unlocked: bestHalf != null && bestHalf < 6000,
        hint: bestHalf == null
            ? tr('No half marathons yet')
            : bestHalf < 6000
                ? tr('Best: {time}', {'time': fmtDuration(bestHalf)})
                : tr('Best so far {time} · {gap} to go', {'time': fmtDuration(bestHalf), 'gap': fmtDuration(bestHalf - 5999)}),
        progress: bestHalf == null ? 0 : 6000 / bestHalf,
      ),
      badge(
        BadgeId.top2,
        tr('Top 2% overall'),
        tr('Finish in the top 2% of a race tracked with RunLah.'),
        unlocked: finished && r.overall!.topPct < 2,
        hint: finished
            ? tr('{place} of {n} · Top {pct}', {'place': ordinal(r.overall!.place), 'n': fmtInt(r.overall!.of), 'pct': fmtPct(r.overall!.topPct)})
            : tr('Waiting for your finish'),
      ),
      badge(
        BadgeId.categoryTop100,
        tr('Category top 100'),
        tr('Place in the top 100 of your age category.'),
        unlocked: finished && r.category!.place <= 100,
        hint: finished ? tr('{place} in {cat}', {'place': ordinal(r.category!.place), 'cat': cat}) : tr('Your category: {cat}', {'cat': cat}),
      ),
      badge(
        BadgeId.overtaker,
        tr('Overtaker'),
        tr('Pass 1,000+ runners before halfway.'),
        unlocked: (passedBeforeHalf ?? 0) >= 1000,
        hint: passedBeforeHalf == null
            ? tr('Counts runners you pass from the start line')
            : tr('Passed {n} before halfway', {'n': fmtInt(passedBeforeHalf)}),
        progress: (passedBeforeHalf ?? 0) / 1000,
      ),
      badge(
        BadgeId.negativeSplit,
        tr('Negative split'),
        tr('Run the second half faster than the first.'),
        unlocked: halves.length == 2 && halves[1].durationS < halves[0].durationS,
        hint: halves.length == 2
            ? (halves[1].durationS < halves[0].durationS
                ? tr('2nd half {gap} faster', {'gap': fmtDuration(halves[0].durationS - halves[1].durationS)})
                : tr('2nd half was {gap} slower', {'gap': fmtDuration(halves[1].durationS - halves[0].durationS)}))
            : tr('Pace yourself: start easy, finish strong'),
      ),
      badge(
        BadgeId.dawnPatrol,
        tr('Dawn patrol'),
        tr('Start a race with a gun before 5 am.'),
        unlocked: started && race.scheduledStart.hour < 5,
        hint: tr('Gun at {time}', {'time': gun}),
      ),
      badge(
        BadgeId.cheeredOn,
        tr('Cheered on'),
        tr('Receive 3 or more cheers during a race.'),
        unlocked: cheers.length >= 3,
        hint: tr('{n} of 3 cheers', {'n': math.min(cheers.length, 3)}),
        progress: cheers.length / 3,
      ),
      badge(
        BadgeId.firstRunLah,
        tr('First RunLah race'),
        tr('Finish your first race tracked live with RunLah.'),
        unlocked: finished,
        hint: finished ? event.name : tr('Cross the finish at {race}', {'race': event.name}),
      ),
      badge(
        BadgeId.pbBreaker,
        tr('PB breaker'),
        tr('Beat your personal best in a race.'),
        unlocked: newPb != null,
        hint: newPb != null
            ? tr('{old} → {new}', {'old': fmtDuration(newPb.previous!.netS), 'new': fmtDuration(newPb.entry!.netS)})
            : tr('Half PB to beat: {time}', {'time': fmtDuration(halfPb.timeS)}),
      ),
      badge(
        BadgeId.targetSmashed,
        tr('Target smashed'),
        tr('Finish faster than your target time.'),
        unlocked: finished && r.netS! <= targetTimeS,
        hint: finished
            ? (r.netS! <= targetTimeS
                ? tr('Beat {target} by {gap}', {'target': fmtDuration(targetTimeS), 'gap': fmtDuration(targetTimeS - r.netS!)})
                : tr('Missed {target} by {gap}', {'target': fmtDuration(targetTimeS), 'gap': fmtDuration(r.netS! - targetTimeS)}))
            : tr('Target: {target}', {'target': fmtDuration(targetTimeS)}),
      ),
      badge(
        BadgeId.fiveHalves,
        tr('Five halves'),
        tr('Finish five half marathons.'),
        unlocked: halfTimes.length >= 5,
        hint: tr('{n} of 5 halves', {'n': math.min(halfTimes.length, 5)}),
        progress: halfTimes.length / 5,
      ),
      badge(
        BadgeId.firstFreeRun,
        tr('First free run'),
        tr('Record a free run on the Run tab.'),
        unlocked: free.runs >= 1,
        hint: free.runs >= 1 ? tr('{n} free runs logged', {'n': free.runs}) : tr('No free runs yet'),
      ),
      badge(
        BadgeId.fiftyKmClub,
        tr('50 km club'),
        tr('Log 50 km of free runs.'),
        unlocked: free.totalM >= 50000,
        hint: tr('{km} of 50 km', {'km': (free.totalM / 1000).toStringAsFixed(1)}),
        progress: free.totalM / 50000,
      ),
    ];

    // ---- wrapped + headline numbers
    final year = event.date.year;
    final yearRaces = [
      if (finished) current,
      for (final e in demoHistory)
        if (e.date.year == year && e.finished) e,
    ];
    PassportEntry? best;
    for (final e in yearRaces) {
      if (best == null || (e.topPct ?? 100) < (best.topPct ?? 100)) best = e;
    }
    int? fastest;
    for (var i = 0; i < quarters.length; i++) {
      if (fastest == null || quarters[i].speedKph > quarters[fastest].speedKph) fastest = i;
    }
    final wrapped = WrappedStats(
      year: year,
      races: yearRaces,
      kmRacedM: yearRaces.fold(0.0, (a, e) => a + e.distanceM),
      best: best,
      runnersPassed: halves.isEmpty ? null : halves.fold<int>(0, (a, s) => a + s.passed),
      passedBeforeHalf: finished ? passedBeforeHalf : null,
      quarters: quarters,
      fastestQuarter: fastest,
      cheerFriend: topFriend,
      cheerCount: topFriend == null ? 0 : byFriend[topFriend]!,
      cheerQuote: quote,
      totalCheers: cheers.length,
      crew: [for (final id in sim.friendIds) sim.participant(id).firstName],
      newPb: newPb,
      currentFinished: finished,
      freeRunCount: free.runs,
      freeRunM: free.thisYearM,
    );

    return ProfileView(
      passport: [current, ...demoHistory],
      current: current,
      bests: bests,
      badges: badges,
      wrapped: wrapped,
      racesTotal: demoHistory.length + (finished ? 1 : 0),
      kmThisYearM: wrapped.kmRacedM,
      year: year,
    );
  }

  // ------------------------------------------------------------ PDPA

  /// Everything RunLah keeps about you on this device, as pretty JSON.
  String exportJson(ProfileView view, SettingsController settings) {
    final you = sim.you;
    final stored = <String, Object?>{};
    for (final k in prefs.getKeys().toList()..sort()) {
      stored[k] = prefs.get(k);
    }
    final data = <String, Object?>{
      'format': 'runlah-export/1',
      'app_version': appVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'demo_mode': sim.event.isDemo,
      'profile': {
        'display_name': settings.displayName,
        'club': club,
        'bib': you.bib,
        'category': sim.race.categoryById(you.categoryId).name,
        'nation': you.nation,
        'follow_link': followLink,
      },
      'settings': {
        'language': settings.lang,
        'units': settings.units.name,
        'theme': settings.themeMode.name,
        'default_privacy': settings.privacy.name,
        'results_name': settings.resultsName.name,
        'battery_saver': settings.batterySaver,
        'voice_coach': settings.voiceCoach,
        'read_cheers_aloud': settings.readCheers,
        'target_time_s': settings.targetTimeS,
      },
      'race_passport': [for (final e in view.passport) e.toJson()],
      'personal_bests': {
        for (final b in view.bests.values)
          if (b.timeS != null) b.distance.label: {'time': fmtDuration(b.timeS), 'race': b.entry!.name},
      },
      'badges_unlocked': [for (final b in view.badges) if (b.unlocked) b.id.name],
      'cheers_received': [
        for (final c in sim.cheersFor(sim.youId)) {'from': c.from, 'message': c.body, 'at': c.at.toIso8601String()},
      ],
      'stored_on_device': stored,
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// "Delete my data": wipe everything stored on this device and put the
  /// settings back to their defaults. The language is kept so the app
  /// doesn't switch under the user's feet.
  Future<void> deleteAllData(SettingsController settings) async {
    final lang = settings.lang;
    await prefs.clear();
    settings
      ..units = Units.km
      ..themeMode = ThemeMode.system
      ..privacy = Privacy.linkOnly
      ..resultsName = ResultsName.full
      ..batterySaver = false
      ..voiceCoach = true
      ..readCheers = true
      ..targetTimeS = 6000
      ..displayName = 'Arep';
    await prefs.setString('lang', lang);
    store.clearAll();
    sim.you.resultsName = ResultsName.full;
    sim.notifyResultsChanged();
    _seen = _dayOneSeen();
    await prefs.setStringList(_seenKey, _seen.toList());
    _club = defaultClub;
    _changed();
  }

  @override
  void dispose() {
    store.removeListener(_onStoreChanged);
    super.dispose();
  }
}
