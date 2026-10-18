import 'dart:math' as math;
import 'dart:typed_data';

import '../models.dart';

/// Race Insights maths. Implements "6.2 Metric definitions" of the PRD v2.
///
/// Input is a crossing table: for every checkpoint, the race time (seconds
/// since the gun) each runner crossed it, or NaN if they didn't (yet).
/// Everything is computed for the whole field at once in O(N log N) per
/// checkpoint/section, so a 12,000-runner race takes well under a second.
class CrossingTable {
  CrossingTable({required this.runners, required this.times}) : indexOf = {for (var i = 0; i < runners.length; i++) runners[i].id: i};

  /// Index-aligned with every Float64List in [times].
  final List<Participant> runners;

  /// `times[checkpointIndex][runnerIndex]`, NaN = no crossing.
  final List<Float64List> times;
  final Map<int, int> indexOf;

  int get length => runners.length;
}

enum SectionSet { checkpoints, halves, quarters }

class InsightsSnapshot {
  InsightsSnapshot._({
    required this.table,
    required this.race,
    required this.asOf,
    required this.basis,
    required this.official,
    required this.closed,
    required this.net,
    required this.gun,
    required this.startDelay,
    required this.finishOrder,
    required this.placeOverall,
    required this.placeGender,
    required this.placeCategory,
    required this.placeNation,
    required this.behindOverall,
    required this.behindGender,
    required this.behindCategory,
    required this.behindNation,
    required this.otherGenderAhead,
    required this.groupSize,
    required this.cpPlace,
    required this.sectionSets,
    required this.stats,
    required this.firstFinishByGender,
  });

  final CrossingTable table;
  final Race race;

  /// Race time this snapshot reflects (provisional while the race is live).
  final double asOf;
  final RankBasis basis;
  final bool official;
  final bool closed;

  final Float64List net, gun, startDelay;

  /// Runner indices of finishers, fastest first by [basis].
  final Int32List finishOrder;
  final Int32List placeOverall, placeGender, placeCategory, placeNation;
  final Int32List behindOverall, behindGender, behindCategory, behindNation;
  final Float64List otherGenderAhead;

  /// Finisher count per group key ("overall", "gender:F", "category:3", "nation:MAS").
  final Map<String, int> groupSize;

  /// `cpPlace[cp][runner]`: clock-order place when crossing that checkpoint (0 = none).
  final List<Int32List> cpPlace;
  final Map<SectionSet, SectionData> sectionSets;
  final Map<String, GroupStats> stats;

  /// Race time the first man / woman crossed the finish.
  final Map<Gender, double> firstFinishByGender;

  int get finishers => finishOrder.length;
  bool get provisional => !official;

  int _idx(int participantId) => table.indexOf[participantId] ?? -1;

  Participant participant(int id) => table.runners[_idx(id)];

  double basisTime(int i) => basis == RankBasis.net ? net[i] : gun[i];

  ResultStatus statusOf(int participantId) {
    final i = _idx(participantId);
    if (i < 0) return ResultStatus.dns;
    if (!net[i].isNaN) return ResultStatus.finished;
    if (table.times[0][i].isNaN || table.times[0][i] > asOf) return ResultStatus.dns;
    return closed ? ResultStatus.dnf : ResultStatus.onCourse;
  }

  ResultRow result(int participantId) {
    final i = _idx(participantId);
    final status = statusOf(participantId);
    if (i < 0 || status != ResultStatus.finished) {
      return ResultRow(participantId: participantId, status: status, startDelayS: i >= 0 && !startDelay[i].isNaN ? startDelay[i] : null);
    }
    final p = table.runners[i];
    PlaceInfo info(Int32List place, Int32List behind, String key) => PlaceInfo(place: place[i], of: groupSize[key] ?? 0, behind: behind[i]);
    return ResultRow(
      participantId: participantId,
      status: status,
      netS: net[i],
      gunS: gun[i],
      startDelayS: startDelay[i],
      overall: info(placeOverall, behindOverall, 'overall'),
      gender: info(placeGender, behindGender, 'gender:${p.gender.code}'),
      category: info(placeCategory, behindCategory, 'category:${p.categoryId}'),
      nation: info(placeNation, behindNation, 'nation:${p.nation}'),
      otherGenderAheadPct: otherGenderAhead[i],
      avgPaceSPerKm: net[i] / (race.distanceM / 1000),
      avgKph: race.distanceM / net[i] * 3.6,
    );
  }

  /// Sections for one runner. Sections the runner hasn't completed are left out.
  List<SectionResult> sections(int participantId, [SectionSet set = SectionSet.checkpoints]) {
    final i = _idx(participantId);
    if (i < 0) return const [];
    final d = sectionSets[set]!;
    final out = <SectionResult>[];
    for (var s = 0; s < d.bounds.length; s++) {
      final (a, b) = d.bounds[s];
      final ta = table.times[a][i], tb = table.times[b][i];
      if (ta.isNaN || tb.isNaN || ta > asOf || tb > asOf) continue;
      out.add(SectionResult(
        fromIndex: a,
        toIndex: b,
        distanceM: race.checkpoints[b].distanceM - race.checkpoints[a].distanceM,
        durationS: tb - ta,
        passed: d.passed[s][i],
        passedBy: d.passedBy[s][i],
        placeAtEnd: cpPlace[b][i],
        basedOn: d.basedOn[s],
      ));
    }
    return out;
  }

  /// Place in clock order at each checkpoint (null where not crossed).
  List<int?> placesByCheckpoint(int participantId) {
    final i = _idx(participantId);
    return [for (final cp in cpPlace) (i < 0 || cp[i] == 0) ? null : cp[i]];
  }

  /// Finishers just ahead of and behind this runner, by [basis].
  ({int? ahead, int? behind}) ghosts(int participantId) {
    final i = _idx(participantId);
    if (i < 0 || net[i].isNaN) return (ahead: null, behind: null);
    final pos = finishOrder.indexOf(i);
    return (
      ahead: pos > 0 ? table.runners[finishOrder[pos - 1]].id : null,
      behind: pos >= 0 && pos < finishOrder.length - 1 ? table.runners[finishOrder[pos + 1]].id : null,
    );
  }

  /// Finishers in rank order (participant ids), optionally filtered.
  List<int> ranking({Gender? gender, int? categoryId, String? nation}) => [
        for (final i in finishOrder)
          if ((gender == null || table.runners[i].gender == gender) &&
              (categoryId == null || table.runners[i].categoryId == categoryId) &&
              (nation == null || table.runners[i].nation == nation))
            table.runners[i].id,
      ];

  /// Estimated race distance of a runner at race time [t], from checkpoint
  /// crossings only: linear between the passes either side of [t]; past the
  /// last pass it extrapolates at the last section's pace, capped at the
  /// next checkpoint (PRD 12.2 "Estimated position").
  double estimatedDistanceAt(int participantId, double t) {
    final i = _idx(participantId);
    if (i < 0) return 0;
    final cps = race.checkpoints;
    double? lastT, lastD;
    double? prevT, prevD;
    for (var k = 0; k < cps.length; k++) {
      final tk = table.times[k][i];
      if (tk.isNaN || tk > asOf) break;
      if (tk >= t) {
        if (lastT == null) return 0;
        final f = (t - lastT) / (tk - lastT);
        return lastD! + (cps[k].distanceM - lastD) * f;
      }
      prevT = lastT;
      prevD = lastD;
      lastT = tk;
      lastD = cps[k].distanceM;
    }
    if (lastT == null) return 0;
    if (lastD! >= race.distanceM) return race.distanceM;
    final paceMps = (prevT != null) ? (lastD - prevD!) / (lastT - prevT) : 3.0;
    final next = cps.firstWhere((c) => c.distanceM > lastD!, orElse: () => cps.last).distanceM;
    return math.min(next, lastD + paceMps * (t - lastT));
  }
}

class SectionData {
  SectionData(this.bounds, this.passed, this.passedBy, this.basedOn);
  final List<(int, int)> bounds;
  final List<Int32List> passed;
  final List<Int32List> passedBy;
  final List<int> basedOn;
}

/// Fenwick (binary indexed) tree over 1-based ranks.
class _Fenwick {
  _Fenwick(int n) : _t = Int32List(n + 1);
  final Int32List _t;
  void add(int i) {
    for (; i < _t.length; i += i & -i) {
      _t[i]++;
    }
  }

  int prefix(int i) {
    var s = 0;
    for (; i > 0; i -= i & -i) {
      s += _t[i];
    }
    return s;
  }
}

class InsightsEngine {
  static const histStartS = 3600.0;
  static const histBinS = 600.0;
  static const histBins = 21;

  static InsightsSnapshot compute(
    CrossingTable table,
    Race race, {
    required double asOf,
    RankBasis basis = RankBasis.net,
    bool official = false,
    bool closed = false,
  }) {
    final n = table.length;
    final cps = race.checkpoints.length;
    final finishIdx = cps - 1;

    double at(int cp, int i) {
      final v = table.times[cp][i];
      return (v.isNaN || v > asOf) ? double.nan : v;
    }

    // ---- times ----
    final net = Float64List(n), gun = Float64List(n), delay = Float64List(n);
    for (var i = 0; i < n; i++) {
      final s = at(0, i), f = at(finishIdx, i);
      delay[i] = s;
      gun[i] = f;
      net[i] = (s.isNaN || f.isNaN) ? double.nan : f - s;
    }
    double key(int i) => basis == RankBasis.net ? net[i] : gun[i];

    final finishers = <int>[for (var i = 0; i < n; i++) if (!net[i].isNaN) i]..sort((a, b) {
        final c = key(a).compareTo(key(b));
        return c != 0 ? c : a.compareTo(b);
      });
    final finishOrder = Int32List.fromList(finishers);

    // ---- places per group (ties share a place) ----
    final groupSize = <String, int>{};
    final placeO = Int32List(n), placeG = Int32List(n), placeC = Int32List(n), placeN = Int32List(n);
    final behindO = Int32List(n), behindG = Int32List(n), behindC = Int32List(n), behindN = Int32List(n);

    void rankGroup(String k, List<int> ordered, Int32List place, Int32List behind) {
      groupSize[k] = ordered.length;
      var j = 0;
      while (j < ordered.length) {
        var e = j;
        while (e + 1 < ordered.length && key(ordered[e + 1]) == key(ordered[j])) {
          e++;
        }
        for (var x = j; x <= e; x++) {
          place[ordered[x]] = j + 1;
          behind[ordered[x]] = ordered.length - e - 1;
        }
        j = e + 1;
      }
    }

    rankGroup('overall', finishers, placeO, behindO);
    final byGender = <Gender, List<int>>{}, byCat = <int, List<int>>{}, byNation = <String, List<int>>{};
    for (final i in finishers) {
      final p = table.runners[i];
      byGender.putIfAbsent(p.gender, () => []).add(i);
      byCat.putIfAbsent(p.categoryId, () => []).add(i);
      byNation.putIfAbsent(p.nation, () => []).add(i);
    }
    byGender.forEach((g, l) => rankGroup('gender:${g.code}', l, placeG, behindG));
    byCat.forEach((c, l) => rankGroup('category:$c', l, placeC, behindC));
    byNation.forEach((c, l) => rankGroup('nation:$c', l, placeN, behindN));

    // ---- other-gender compare: share of the other gender with a slower time ----
    final other = Float64List(n)..fillRange(0, n, double.nan);
    for (final g in Gender.values) {
      final otherList = byGender[g == Gender.m ? Gender.f : Gender.m] ?? const <int>[];
      final otherTimes = [for (final i in otherList) key(i)];
      for (final i in byGender[g] ?? const <int>[]) {
        if (otherTimes.isEmpty) continue;
        final slower = otherTimes.length - _upperBound(otherTimes, key(i));
        other[i] = slower / otherTimes.length * 100;
      }
    }

    // ---- clock-order place at every checkpoint ----
    final cpPlace = <Int32List>[];
    for (var k = 0; k < cps; k++) {
      final crossers = <int>[for (var i = 0; i < n; i++) if (!at(k, i).isNaN) i]..sort((a, b) => at(k, a).compareTo(at(k, b)));
      final place = Int32List(n);
      var j = 0;
      while (j < crossers.length) {
        var e = j;
        while (e + 1 < crossers.length && at(k, crossers[e + 1]) == at(k, crossers[j])) {
          e++;
        }
        for (var x = j; x <= e; x++) {
          place[crossers[x]] = j + 1;
        }
        j = e + 1;
      }
      cpPlace.add(place);
    }

    // ---- sections and overtakes ----
    SectionData sectionSet(List<(int, int)> bounds) {
      final passed = <Int32List>[], passedBy = <Int32List>[], basedOn = <int>[];
      for (final (a, b) in bounds) {
        final r = _overtakes(n, (i) => at(a, i), (i) => at(b, i));
        passed.add(r.passed);
        passedBy.add(r.passedBy);
        basedOn.add(r.count);
      }
      return SectionData(bounds, passed, passedBy, basedOn);
    }

    final half = race.checkpointNear(0.5);
    final q1 = race.checkpointNear(0.25), q3 = race.checkpointNear(0.75);
    final sectionSets = {
      SectionSet.checkpoints: sectionSet([for (var k = 0; k < cps - 1; k++) (k, k + 1)]),
      SectionSet.halves: sectionSet([(0, half), (half, finishIdx)]),
      SectionSet.quarters: sectionSet([(0, q1), (q1, half), (half, q3), (q3, finishIdx)]),
    };

    // ---- field stats ----
    GroupStats statsFor(String scope, List<int> group) {
      final times = [for (final i in group) net[i]]..sort();
      final hist = List<int>.filled(histBins, 0);
      var f = 0, m = 0;
      for (final i in group) {
        final b = ((net[i] - histStartS) / histBinS).floor().clamp(0, histBins - 1);
        hist[b]++;
        if (table.runners[i].gender == Gender.f) {
          f++;
        } else {
          m++;
        }
      }
      double median = double.nan;
      if (times.isNotEmpty) {
        final mid = times.length ~/ 2;
        median = times.length.isOdd ? times[mid] : (times[mid - 1] + times[mid]) / 2;
      }
      return GroupStats(
        scope: scope,
        finishers: group.length,
        medianNetS: median,
        histogram: hist,
        histStartS: histStartS,
        histBinS: histBinS,
        female: f,
        male: m,
        fastestNetS: times.isEmpty ? null : times.first,
      );
    }

    final stats = <String, GroupStats>{'overall': statsFor('overall', finishers)};
    byGender.forEach((g, l) => stats['gender:${g.code}'] = statsFor('gender:${g.code}', l));
    byCat.forEach((c, l) => stats['category:$c'] = statsFor('category:$c', l));

    final firstFinish = <Gender, double>{};
    for (var i = 0; i < n; i++) {
      final f = gun[i];
      if (f.isNaN) continue;
      final g = table.runners[i].gender;
      if (!firstFinish.containsKey(g) || f < firstFinish[g]!) firstFinish[g] = f;
    }

    return InsightsSnapshot._(
      table: table,
      race: race,
      asOf: asOf,
      basis: basis,
      official: official,
      closed: closed,
      net: net,
      gun: gun,
      startDelay: delay,
      finishOrder: finishOrder,
      placeOverall: placeO,
      placeGender: placeG,
      placeCategory: placeC,
      placeNation: placeN,
      behindOverall: behindO,
      behindGender: behindG,
      behindCategory: behindC,
      behindNation: behindN,
      otherGenderAhead: other,
      groupSize: groupSize,
      cpPlace: cpPlace,
      sectionSets: sectionSets,
      stats: stats,
      firstFinishByGender: firstFinish,
    );
  }

  /// "You passed" / "passed you" for every runner across one section.
  ///
  /// passed(i)   = #{j : A_j < A_i and B_j > B_i}  (j was ahead at A, behind at B)
  /// passedBy(i) = #{j : A_j > A_i and B_j < B_i}
  /// A and B are clock times of crossing the section start and end.
  /// Only runners with both crossings count.
  static ({Int32List passed, Int32List passedBy, int count}) _overtakes(int n, double Function(int) a, double Function(int) b) {
    final passed = Int32List(n), passedBy = Int32List(n);
    final idx = <int>[for (var i = 0; i < n; i++) if (!a(i).isNaN && !b(i).isNaN) i];
    if (idx.isEmpty) return (passed: passed, passedBy: passedBy, count: 0);

    // Compress B to dense 1-based ranks (equal B -> equal rank).
    final bs = [for (final i in idx) b(i)]..sort();
    final distinct = <double>[];
    for (final v in bs) {
      if (distinct.isEmpty || distinct.last != v) distinct.add(v);
    }
    int rankB(int i) => _lowerBound(distinct, b(i)) + 1;

    idx.sort((x, y) => a(x).compareTo(a(y)));

    // Forward pass: runners already inserted crossed A strictly earlier.
    var fw = _Fenwick(distinct.length);
    var inserted = 0;
    var g = 0;
    while (g < idx.length) {
      var e = g;
      while (e + 1 < idx.length && a(idx[e + 1]) == a(idx[g])) {
        e++;
      }
      for (var x = g; x <= e; x++) {
        final i = idx[x];
        passed[i] = inserted - fw.prefix(rankB(i)); // B_j > B_i
      }
      for (var x = g; x <= e; x++) {
        fw.add(rankB(idx[x]));
        inserted++;
      }
      g = e + 1;
    }

    // Backward pass: runners already inserted crossed A strictly later.
    fw = _Fenwick(distinct.length);
    g = idx.length - 1;
    while (g >= 0) {
      var s = g;
      while (s - 1 >= 0 && a(idx[s - 1]) == a(idx[g])) {
        s--;
      }
      for (var x = s; x <= g; x++) {
        final i = idx[x];
        passedBy[i] = fw.prefix(rankB(i) - 1); // B_j < B_i
      }
      for (var x = s; x <= g; x++) {
        fw.add(rankB(idx[x]));
      }
      g = s - 1;
    }
    return (passed: passed, passedBy: passedBy, count: idx.length);
  }

  static int _lowerBound(List<double> xs, double v) {
    var lo = 0, hi = xs.length;
    while (lo < hi) {
      final m = (lo + hi) >> 1;
      if (xs[m] < v) {
        lo = m + 1;
      } else {
        hi = m;
      }
    }
    return lo;
  }

  /// First index with xs[i] > v (xs sorted ascending).
  static int _upperBound(List<double> xs, double v) {
    var lo = 0, hi = xs.length;
    while (lo < hi) {
      final m = (lo + hi) >> 1;
      if (xs[m] <= v) {
        lo = m + 1;
      } else {
        hi = m;
      }
    }
    return lo;
  }
}
