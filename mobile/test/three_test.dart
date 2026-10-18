import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runlah/data/demo/field_generator.dart';
import 'package:runlah/data/demo/kl_course.dart';
import 'package:runlah/data/sim/race_sim.dart';
import 'package:runlah/features/three/race3d_mode.dart';
import 'package:runlah/features/three/race3d_payload.dart';

RaceSim? _sim;
RaceSim _demoSim() => _sim ??= () {
      final event = buildDemoEvent(raceDay: DateTime(2026, 10, 4));
      return RaceSim(event: event, field: generateDemoField(event.races.first));
    }();

void main() {
  group('Race3DPayload', () {
    test('includes you and friends, respects the cap', () {
      final sim = _demoSim();
      final data = Race3DPayload.build(sim, mode: Race3DMode.replay);
      final runners = (data['runners'] as List).cast<Map<String, Object?>>();
      final ids = runners.map((r) => r['id']).toSet();
      expect(ids, contains(sim.youId));
      for (final f in sim.friendIds) {
        expect(ids, contains(f));
      }
      expect(runners.length, lessThanOrEqualTo(Race3DPayload.maxRunners));
      expect(runners.length, Race3DPayload.maxRunners);
      expect(runners.firstWhere((r) => r['id'] == sim.youId)['cls'], 'you');
    });

    test('dump payload for the JS preview (RUNLAH_DUMP_PAYLOAD)', () {
      final out = Platform.environment['RUNLAH_DUMP_PAYLOAD'];
      if (out == null) return;
      final sim = _demoSim();
      final data = Race3DPayload.build(
        sim,
        mode: Race3DMode.replay,
        labels: {'${sim.youId}': 'You · 34144', for (final f in sim.friendIds) '$f': '${sim.participant(f).firstName} · ${sim.participant(f).bib}'},
      );
      File(out).writeAsStringSync(jsonEncode(data));
    });
  });
}
