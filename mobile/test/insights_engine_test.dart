import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:runlah/core/format.dart';
import 'package:runlah/data/demo/field_generator.dart';
import 'package:runlah/data/demo/kl_course.dart';
import 'package:runlah/data/insights/insights_engine.dart';
import 'package:runlah/data/models.dart';
import 'package:runlah/data/sim/race_sim.dart';

Participant _p(int id, Gender g, {int cat = 1, String nation = 'MAS'}) =>
    Participant(id: id, raceId: 21, bib: '$id', name: 'R$id', gender: g, birthYear: 1995, nation: nation, categoryId: cat);

void main() {
  final race = buildDemoEvent(raceDay: DateTime(2026, 10, 4)).races.first;
  final cps = race.checkpoints.length;

  CrossingTable randomTable(int n, int seed) {
    final r = math.Random(seed);
    final runners = [for (var i = 0; i < n; i++) _p(i + 1, r.nextBool() ? Gender.m : Gender.f, cat: 1 + r.nextInt(3))];
    final times = [for (var k = 0; k < cps; k++) Float64List(n)];
    for (var i = 0; i < n; i++) {
      var t = r.nextInt(300).toDouble(); // start delay, coarse so ties happen
      final dnfAt = r.nextDouble() < 0.1 ? 1 + r.nextInt(cps - 1) : cps;
      for (var k = 0; k < cps; k++) {
        if (k > 0) t += 300 + r.nextInt(400); // coarse -> ties
        times[k][i] = k < dnfAt ? t : double.nan;
      }
    }
    return CrossingTable(runners: runners, times: times);
  }

  test('places, ties, behind and Top % match brute force', () {
    final table = randomTable(400, 1);
    final s = InsightsEngine.compute(table, race, asOf: 1e9);
    for (final p in table.runners) {
      final i = table.indexOf[p.id]!;
      final r = s.result(p.id);
      if (r.status != ResultStatus.finished) continue;
      final mine = r.netS!;
      var faster = 0, slower = 0, of = 0;
      for (var j = 0; j < table.length; j++) {
        final n = s.net[j];
        if (n.isNaN) continue;
        of++;
        if (n < mine) faster++;
        if (n > mine) slower++;
      }
      expect(r.overall!.place, faster + 1, reason: 'place of ${p.id}');
      expect(r.overall!.behind, slower);
      expect(r.overall!.of, of);
      expect(r.overall!.topPct, closeTo(faster / of * 100, 1e-9));
      expect(i, isNonNegative);
    }
  });

  test('overtakes match brute force on every section', () {
    final table = randomTable(300, 7);
    final s = InsightsEngine.compute(table, race, asOf: 1e9);
    for (final p in table.runners.take(120)) {
      final i = table.indexOf[p.id]!;
      for (final sec in s.sections(p.id)) {
        final a = table.times[sec.fromIndex], b = table.times[sec.toIndex];
        var passed = 0, passedBy = 0;
        for (var j = 0; j < table.length; j++) {
          if (a[j].isNaN || b[j].isNaN) continue;
          if (a[j] < a[i] && b[j] > b[i]) passed++;
          if (a[j] > a[i] && b[j] < b[i]) passedBy++;
        }
        expect(sec.passed, passed, reason: 'passed ${p.id} ${sec.fromIndex}->${sec.toIndex}');
        expect(sec.passedBy, passedBy, reason: 'passedBy ${p.id} ${sec.fromIndex}->${sec.toIndex}');
      }
    }
  });

  test('other-gender compare and ghosts', () {
    final table = randomTable(200, 3);
    final s = InsightsEngine.compute(table, race, asOf: 1e9);
    final me = s.ranking().elementAt(50);
    final r = s.result(me);
    final myG = s.participant(me).gender;
    final others = [for (var j = 0; j < table.length; j++) if (!s.net[j].isNaN && table.runners[j].gender != myG) s.net[j]];
    final slower = others.where((t) => t > r.netS!).length;
    expect(r.otherGenderAheadPct, closeTo(slower / others.length * 100, 1e-9));
    final g = s.ghosts(me);
    final order = s.ranking();
    expect(g.ahead, order[49]);
    expect(g.behind, order[51]);
  });

  test('provisional snapshot only counts crossings up to asOf', () {
    final table = randomTable(150, 9);
    final early = InsightsEngine.compute(table, race, asOf: 2000);
    for (var i = 0; i < table.length; i++) {
      final f = table.times.last[i];
      if (!f.isNaN && f > 2000) expect(early.net[i].isNaN, isTrue);
    }
  });

  test('pct formatting never rounds up to 100', () {
    expect(fmtPct(3897 / 3910 * 100), '99.7%');
    expect(fmtPct(99.96), '99.9%');
    expect(fmtPct(171 / 11664 * 100), '1.5%');
    expect(ordinal(172), '172nd');
    expect(ordinal(111), '111th');
    expect(fmtDuration(5775), '1:36:15');
  });

  test('demo field: bib 34144 looks like the real KLSCM result', () {
    final event = buildDemoEvent(raceDay: DateTime(2026, 10, 4));
    final sw = Stopwatch()..start();
    final field = generateDemoField(event.races.first);
    final sim = RaceSim(event: event, field: field);
    final genMs = sw.elapsedMilliseconds;
    sw.reset();
    final s = sim.insights(asOf: sim.race.cutoffS.toDouble());
    final computeMs = sw.elapsedMilliseconds;
    final r = s.result(sim.youId);
    final halves = s.sections(sim.youId, SectionSet.halves);
    final quarters = s.sections(sim.youId, SectionSet.quarters);
    final stats = s.stats['overall']!;
    // ignore: avoid_print
    print('generate ${genMs}ms, insights ${computeMs}ms\n'
        'finishers ${s.finishers} (F ${stats.female}, M ${stats.male}), median ${fmtDuration(stats.medianNetS)}\n'
        'you: net ${fmtDuration(r.netS)} gun ${fmtDuration(r.gunS)} delay ${fmtDuration(r.startDelayS)}\n'
        'overall ${r.overall!.place}/${r.overall!.of} top ${fmtPct(r.overall!.topPct)} behind ${r.overall!.behind}\n'
        'gender ${r.gender!.place}/${r.gender!.of}  category ${r.category!.place}/${r.category!.of}  other-gender ${fmtPct(r.otherGenderAheadPct!)}\n'
        'halves passed/by: ${halves.map((h) => '${h.passed}/${h.passedBy}').join(', ')}\n'
        'quarters kph: ${quarters.map((q) => q.speedKph.toStringAsFixed(1)).join(', ')}\n'
        'male winner ${fmtDuration(s.firstFinishByGender[Gender.m])}, female winner ${fmtDuration(s.firstFinishByGender[Gender.f])}');
    expect(s.finishers, 11664);
    expect(stats.female, 3910);
    expect(r.netS, closeTo(5775, 1));
    expect(r.startDelayS, 39);
    expect(quarters.map((q) => double.parse(q.speedKph.toStringAsFixed(1))), [13.2, 13.8, 12.9, 12.8]);
    sim.dispose();
  });
}
