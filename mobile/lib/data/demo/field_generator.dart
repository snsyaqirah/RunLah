import 'dart:math' as math;

import '../models.dart';

/// Generates a realistic simulated field for the demo race.
///
/// Calibrated against the KLSCM 2026 half marathon: 11,664 finishers
/// (7,754 men, 3,910 women) and a median net time around 2:50. Finish times
/// are log-normal per gender; front runners start close to the gun, back
/// runners up to ~15 minutes later; most runners slow down a little in the
/// second half.
class DemoField {
  DemoField(this.participants, this.plans, this.youId, this.friendIds);
  final List<Participant> participants;
  final Map<int, RunnerPlan> plans;
  final int youId;
  final List<int> friendIds;
}

class _Rng {
  _Rng(int seed) : _r = math.Random(seed);
  final math.Random _r;
  double next() => _r.nextDouble();
  int nextInt(int n) => _r.nextInt(n);
  T pick<T>(List<T> xs) => xs[_r.nextInt(xs.length)];
  double normal() {
    final u1 = math.max(1e-12, _r.nextDouble());
    final u2 = _r.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }
}

const _malayM = ['Muhammad', 'Ahmad', 'Mohd', 'Amir', 'Hafiz', 'Faiz', 'Irfan', 'Hakim', 'Danial', 'Syafiq', 'Aiman', 'Haziq', 'Izzat', 'Zulkifli', 'Rizal', 'Azlan', 'Khairul', 'Firdaus'];
const _malayF = ['Nur', 'Siti', 'Aina', 'Nurul', 'Farah', 'Aisyah', 'Hani', 'Syaqirah', 'Amira', 'Liyana', 'Iman', 'Balqis', 'Zulaikha', 'Hanis', 'Atiqah'];
const _malayLast = ['Ismail', 'Abdullah', 'Rahman', 'Hassan', 'Ibrahim', 'Yusof', 'Osman', 'Hamzah', 'Aziz', 'Karim', 'Salleh', 'Zainal', 'Razak', 'Omar', 'Hashim'];
const _chineseLast = ['Tan', 'Lim', 'Lee', 'Wong', 'Ng', 'Chan', 'Ong', 'Teh', 'Goh', 'Chong', 'Yap', 'Loh'];
const _chineseGivenM = ['Wei Jie', 'Jun Hao', 'Kah Seng', 'Zhi Hao', 'Chee Keong', 'Jia Wei', 'Boon Hock', 'Yi Xuan'];
const _chineseGivenF = ['Mei Ling', 'Hui Min', 'Xin Yi', 'Pei Shan', 'Li Ying', 'Jia Hui', 'Siew Ling', 'Yee Wen'];
const _indianM = ['Ravi', 'Kumar', 'Arjun', 'Suresh', 'Vikram', 'Ganesh', 'Prakash', 'Dinesh'];
const _indianF = ['Priya', 'Kavitha', 'Deepa', 'Anjali', 'Shalini', 'Meera', 'Lakshmi', 'Nisha'];
const _indianLast = ['Subramaniam', 'Krishnan', 'Muthu', 'Raj', 'Pillai', 'Nair', 'Govindasamy', 'Selvam'];
const _foreignM = ['James', 'Daniel', 'Kenji', 'Brian', 'Eliud', 'Lucas', 'Tom', 'Ryan', 'Budi', 'Jose'];
const _foreignF = ['Emma', 'Sarah', 'Yuki', 'Grace', 'Faith', 'Chloe', 'Anna', 'Dewi', 'Maria', 'Sophie'];
const _foreignLast = ['Smith', 'Tanaka', 'Kiprop', 'Brown', 'Santoso', 'Garcia', 'Wilson', 'Kim', 'Nguyen', 'Muller'];
const _nations = ['SGP', 'IDN', 'KEN', 'GBR', 'AUS', 'JPN', 'CHN', 'IND', 'PHL', 'THA', 'USA', 'KOR'];

String _name(_Rng r, Gender g, String nation) {
  final m = g == Gender.m;
  if (nation != 'MAS') {
    return '${r.pick(m ? _foreignM : _foreignF)} ${r.pick(_foreignLast)}';
  }
  final roll = r.next();
  if (roll < 0.62) {
    final first = r.pick(m ? _malayM : _malayF);
    final second = r.pick(m ? _malayM : _malayF);
    final mid = (first == 'Muhammad' || first == 'Nur' || first == 'Siti' || first == 'Mohd') && second != first ? ' $second' : '';
    return '$first$mid ${m ? 'bin' : 'binti'} ${r.pick(_malayLast)}';
  } else if (roll < 0.88) {
    return '${r.pick(_chineseLast)} ${r.pick(m ? _chineseGivenM : _chineseGivenF)}';
  }
  return '${r.pick(m ? _indianM : _indianF)} ${r.pick(_indianLast)}';
}

int _age(_Rng r) {
  // Mostly 25–50, long tail to 70 (about 23% under 30, like KLSCM).
  final a = 37 + r.normal() * 9.5;
  return a.clamp(18, 72).round();
}

int _categoryFor(List<Category> cats, Gender g, int age) =>
    cats.firstWhere((c) => c.gender == g && age >= c.ageMin && age <= c.ageMax).id;

/// Builds per-km cumulative net times that sum to [netS], with a fade and
/// a slow, crowded first kilometre for back starters.
List<double> _plan(_Rng r, double netS, double distanceM, double crowding, double fade) {
  final fullKm = (distanceM / 1000).floor();
  final lastFrac = distanceM / 1000 - fullKm;
  final weights = <double>[];
  for (var k = 0; k <= fullKm; k++) {
    final len = k < fullKm ? 1.0 : lastFrac;
    if (len <= 0) continue;
    final x = (k + 0.5) / (fullKm + 1); // 0..1 through the race
    var w = 1 + fade * (x - 0.5) * 2 + r.normal() * 0.018;
    if (k == 0) w += crowding;
    if (k == 1) w += crowding * 0.4;
    weights.add(w * len);
  }
  final total = weights.fold<double>(0, (a, b) => a + b);
  final cum = <double>[0];
  var acc = 0.0;
  for (final w in weights) {
    acc += netS * w / total;
    cum.add(acc);
  }
  return cum;
}

/// Exact plan for "you": KLSCM 2026 bib 34144 (net 1:36:15, start delay 0:39,
/// quarter speeds 13.2 / 13.8 / 12.9 / 12.8 km/h). Marks include the quarter
/// points so section speeds come out exact.
({List<double> cum, List<double> marks}) _youPlan(double distanceM) {
  const quarterKph = [13.2, 13.8, 12.9, 12.8];
  final q = distanceM / 4;
  final quarterS = [for (final k in quarterKph) q / (k / 3.6)];
  final scale = 5775 / quarterS.fold<double>(0, (a, b) => a + b);
  double netAt(double d) {
    var t = 0.0;
    var left = d;
    for (var i = 0; i < 4 && left > 0; i++) {
      final take = math.min(left, q);
      t += quarterS[i] * scale * take / q;
      left -= take;
    }
    return t;
  }

  final marks = {...RunnerPlan.kmMarks(distanceM), q, 2 * q, 3 * q}.toList()..sort();
  return (cum: [for (final m in marks) netAt(m)], marks: marks);
}

DemoField generateDemoField(Race race, {int seed = 2026}) {
  final r = _Rng(seed);
  final cats = race.categories;
  final participants = <Participant>[];
  final plans = <int, RunnerPlan>{};

  // Finishers by gender match KLSCM 2026; a few extra DNFs on top.
  const menFinish = 7754, womenFinish = 3910, menDnf = 60, womenDnf = 36;
  final specs = <(Gender, bool)>[
    for (var i = 0; i < menFinish - 2; i++) (Gender.m, false), // minus you and Hafiz
    for (var i = 0; i < womenFinish - 1; i++) (Gender.f, false), // minus Qirah
    for (var i = 0; i < menDnf; i++) (Gender.m, true),
    for (var i = 0; i < womenDnf; i++) (Gender.f, true),
  ];

  // Median ~2:40 men, ~3:09 women, sigma 0.25 → bib 34144 lands near
  // 170th overall like the real result.
  const muM = 9.172, muF = 9.339, sigma = 0.25;
  final targets = <double>[];
  for (final s in specs) {
    var t = math.exp((s.$1 == Gender.m ? muM : muF) + r.normal() * sigma);
    t = t.clamp(s.$1 == Gender.m ? 3780.0 : 4260.0, 15300.0 + r.next() * 600);
    targets.add(t);
  }
  // Start delay follows corral order (faster runners near the front).
  final order = List<int>.generate(specs.length, (i) => i)..sort((a, b) => targets[a].compareTo(targets[b]));
  final rankOf = List<int>.filled(specs.length, 0);
  for (var i = 0; i < order.length; i++) {
    rankOf[order[i]] = i;
  }

  var bibCounter = 10001;
  var id = 1;
  for (var i = 0; i < specs.length; i++) {
    final (g, dnf) = specs[i];
    final q = rankOf[i] / specs.length;
    final nation = r.next() < 0.86 ? 'MAS' : r.pick(_nations);
    final age = _age(r);
    // Corral order, except ~12% "eager starters" who squeeze to the front
    // whatever their pace (that's who fast runners overtake early on).
    final eager = q > 0.05 && r.next() < 0.12;
    final startDelay = eager
        ? 5 + r.next() * 55
        : math.max(2.0, 18 + math.pow(q, 1.15) * 880 + r.normal() * (4 + 26 * q));
    final crowding = 0.02 + q * 0.09 + r.next() * 0.03;
    final fade = 0.02 + q * 0.06 + r.normal() * 0.035;
    // Every finisher crosses before the cutoff (gun time), so official
    // results count the full 11,664. The slowest spread over the last 30 min.
    final maxNet = race.cutoffS - startDelay - 20;
    final net = targets[i] <= maxNet ? targets[i] : maxNet - r.next() * 1800;
    final cum = _plan(r, net, race.distanceM, crowding, fade);
    final bib = (bibCounter++).toString();
    if (bib == '34144') bibCounter++;
    participants.add(Participant(
      id: id,
      raceId: race.id,
      bib: bib,
      name: _name(r, g, nation),
      gender: g,
      birthYear: 2026 - age,
      nation: nation,
      categoryId: _categoryFor(cats, g, age),
      hasGps: r.next() < 0.45,
      resultsName: r.next() < 0.04 ? ResultsName.bibOnly : ResultsName.full,
      verifyCode: (100000 + r.nextInt(899999)).toString(),
    ));
    plans[id] = RunnerPlan(startDelayS: startDelay, cumS: cum, marksM: RunnerPlan.kmMarks(race.distanceM), dnfAtM: dnf ? race.distanceM * (0.2 + r.next() * 0.7) : null);
    id++;
  }

  // You: KLSCM 2026 bib 34144.
  final youId = id++;
  participants.add(Participant(
    id: youId,
    raceId: race.id,
    bib: '34144',
    name: 'Arep',
    gender: Gender.m,
    birthYear: 2001,
    nation: 'MAS',
    categoryId: _categoryFor(cats, Gender.m, 25),
    hasGps: true,
    verifyCode: '261004',
  ));
  final yp = _youPlan(race.distanceM);
  plans[youId] = RunnerPlan(startDelayS: 39, cumS: yp.cum, marksM: yp.marks);

  // Two friends you follow.
  final qirahId = id++;
  participants.add(Participant(
    id: qirahId,
    raceId: race.id,
    bib: '20417',
    name: 'Nur Syaqirah binti Osman',
    gender: Gender.f,
    birthYear: 2000,
    nation: 'MAS',
    categoryId: _categoryFor(cats, Gender.f, 26),
    hasGps: true,
    verifyCode: '204170',
  ));
  plans[qirahId] = RunnerPlan(startDelayS: 212, cumS: _plan(r, 2 * 3600 + 18 * 60 + 40, race.distanceM, 0.05, 0.06), marksM: RunnerPlan.kmMarks(race.distanceM));

  final hafizId = id++;
  participants.add(Participant(
    id: hafizId,
    raceId: race.id,
    bib: '28803',
    name: 'Muhammad Hafiz bin Rahman',
    gender: Gender.m,
    birthYear: 1994,
    nation: 'MAS',
    categoryId: _categoryFor(cats, Gender.m, 32),
    hasGps: false,
    verifyCode: '288030',
  ));
  plans[hafizId] = RunnerPlan(startDelayS: 145, cumS: _plan(r, 2 * 3600 + 2 * 60 + 15, race.distanceM, 0.04, 0.09), marksM: RunnerPlan.kmMarks(race.distanceM));

  return DemoField(participants, plans, youId, [qirahId, hafizId]);
}
