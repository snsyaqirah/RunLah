import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:runlah/data/sim/race_sim.dart';
import 'package:runlah/features/three/race3d_controller.dart';
import 'package:runlah/features/three/race3d_mode.dart';
import 'package:runlah/features/three/race3d_payload.dart';
import 'package:runlah/features/three/race3d_screen.dart';
import 'package:runlah/features/three/race3d_view.dart';

import 'helpers.dart';

/// pumpScreen + let the InsightsController's 1.5 s debounce timer (started
/// by finishing the race) fire, so no timer is left pending.
Future<void> pump3D(WidgetTester tester, Race3DScreen screen, {Size size = const Size(390, 844)}) async {
  await pumpScreen(tester, (_) => screen, finished: true, size: size);
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Race3DScreen', () {
    for (final size in const [Size(390, 844), Size(360, 740)]) {
      for (final mode in Race3DMode.values) {
        testWidgets('${mode.name} at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
          await pump3D(tester, Race3DScreen(mode: mode), size: size);
          expect(tester.takeException(), isNull);
          final title = switch (mode) {
            Race3DMode.replay => 'Race replay',
            Race3DMode.drone => 'Drone view',
            Race3DMode.flyover => 'Course flyover',
          };
          expect(find.text(title), findsWidgets);
          // No platform view in tests: the placeholder stands in for the scene.
          expect(find.byIcon(Icons.view_in_ar_rounded), findsOneWidget);
          expect(find.byType(Slider), findsOneWidget);
        });
      }
    }

    testWidgets('switches modes and toggles play', (tester) async {
      await pump3D(tester, const Race3DScreen(mode: Race3DMode.replay));
      expect(find.text('Follow you'), findsOneWidget);
      expect(find.text('60×'), findsOneWidget);

      await tester.tap(find.text('Flyover'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Course flyover'), findsOneWidget);
      expect(find.text('Follow you'), findsNothing);

      await tester.tap(find.byIcon(Icons.videocam_rounded));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('2×'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pump();
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('picked runner card fits at 360 px and can follow', (tester) async {
      await pump3D(tester, const Race3DScreen(mode: Race3DMode.replay), size: const Size(360, 740));
      final sim = tester.element(find.byType(Race3DScreen)).read<RaceSim>();
      // Longest name in the field.
      final p = sim.participants.reduce((a, b) => a.displayName.length >= b.displayName.length ? a : b);
      final view = tester.widget<Race3DView>(find.byType(Race3DView));
      view.controller.handleMessage('{"type":"pick","id":${p.id}}');
      await tester.pump(); // stream delivers in a microtask
      await tester.pump();
      expect(find.text(p.displayName), findsOneWidget);
      expect(find.textContaining(p.bib), findsOneWidget);
      await tester.tap(find.text('Follow'));
      await tester.pump();
      expect(find.text('Unfollow'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(find.text(p.displayName), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('starts at a given race time', (tester) async {
      await pump3D(tester, const Race3DScreen(mode: Race3DMode.replay, atRaceTime: 3600));
      expect(find.text('1:00:00'), findsOneWidget);
      expect(find.textContaining('05:45:00'), findsOneWidget);
    });
  });

  group('Race3DPayload', () {
    late RaceSim sim;
    setUpAll(() async => sim = (await TestApp.create()).sim);

    test('includes you and friends, respects the cap', () {
      final data = Race3DPayload.build(sim, mode: Race3DMode.replay);
      final runners = (data['runners'] as List).cast<Map<String, Object?>>();
      final ids = runners.map((r) => r['id']).toSet();
      expect(ids, contains(sim.youId));
      for (final f in sim.friendIds) {
        expect(ids, contains(f));
      }
      expect(runners.length, Race3DPayload.maxRunners);
      expect(ids.length, runners.length, reason: 'no duplicates');
      expect(runners.firstWhere((r) => r['id'] == sim.youId)['cls'], 'you');
      expect(runners.where((r) => r['cls'] == 'friend').length, sim.friendIds.length);

      final small = Race3DPayload.build(sim, mode: Race3DMode.replay, cap: 500);
      expect((small['runners'] as List).length, lessThanOrEqualTo(500));
      expect((small['runners'] as List).map((r) => (r as Map)['id']), contains(sim.youId));
    });

    test('drone window contains your finish and everyone finishing near you', () {
      final finish = Race3DPayload.finishTime(sim, sim.youId)!;
      final w = Race3DPayload.droneWindow(sim, sim.youId);
      expect(w.start, lessThan(finish));
      expect(w.end, greaterThan(finish));
      expect(w.end - w.start, closeTo(2 * Race3DPayload.droneHalfWindowS, 0.001));
      expect(Race3DPayload.initialTime(sim, Race3DMode.drone, focusId: sim.youId), closeTo(finish - 60, 0.001));

      final data = Race3DPayload.build(sim, mode: Race3DMode.drone);
      final ids = (data['runners'] as List).map((r) => (r as Map)['id']).toSet();
      final table = sim.crossingTable;
      var near = 0;
      for (var i = 0; i < table.length; i++) {
        final t = table.times.last[i];
        if (!t.isNaN && (t - finish).abs() <= Race3DPayload.droneIncludeS) {
          near++;
          expect(ids, contains(table.runners[i].id));
        }
      }
      expect(near, greaterThan(10));
      final window = data['window'] as List;
      expect((window[0] as num) <= finish && finish <= (window[1] as num), isTrue);
      expect(data['focusId'], sim.youId);
    });

    test('runner kinematics round-trip (you keep your own marks)', () {
      final data = Race3DPayload.build(sim, mode: Race3DMode.replay);
      final runners = (data['runners'] as List).cast<Map<String, Object?>>();
      final you = runners.firstWhere((r) => r['id'] == sim.youId);
      expect(you['marks'], isNotNull, reason: 'your plan has quarter marks');
      final cum = (you['cum'] as List).cast<num>();
      expect(you['startDelay'] as num, closeTo(39, 0.05));
      expect(cum.last, closeTo(5775, 0.05));
      final field = runners.firstWhere((r) => r['cls'] == 'field');
      expect(field.containsKey('marks'), isFalse);
      expect((field['cum'] as List).length, (data['marks'] as List).length);
      // Route: ~20 m samples with race distance per point.
      final route = data['route'] as Map;
      expect((route['x'] as List).length, (route['d'] as List).length);
      expect((route['d'] as List).last, closeTo(sim.race.distanceM, 0.1));
      expect(jsonEncode(data).length, lessThan(900 * 1024));
    });

    test('initial times per mode', () {
      expect(Race3DPayload.initialTime(sim, Race3DMode.flyover, focusId: sim.youId), 0);
      final f = Race3DPayload.finishTime(sim, sim.youId)!;
      // Pre-race / closed: 20 minutes before your finish.
      sim.reset();
      expect(Race3DPayload.initialTime(sim, Race3DMode.replay, focusId: sim.youId), closeTo(f - 1200, 0.001));
      expect(Race3DPayload.initialTime(sim, Race3DMode.replay, focusId: sim.youId, atRaceTime: 999999), sim.race.cutoffS);
    });

    test('dump payload for the JS preview (RUNLAH_DUMP_PAYLOAD)', () {
      final out = Platform.environment['RUNLAH_DUMP_PAYLOAD'];
      if (out == null) return;
      final data = Race3DPayload.build(
        sim,
        mode: Race3DMode.replay,
        labels: {
          '${sim.youId}': 'You · 34144',
          for (final f in sim.friendIds) '$f': '${sim.participant(f).firstName} · ${sim.participant(f).bib}',
        },
      );
      File(out).writeAsStringSync(jsonEncode(data));
    });
  });

  group('Race3DController', () {
    test('sends init on ready, then commands; parses events', () async {
      final c = Race3DController();
      final sent = <Map<String, Object?>>[];
      c.attach(send: (json) async => sent.add(jsonDecode(json) as Map<String, Object?>), init: () => {'mode': 'replay'});

      c.play(); // before ready: dropped, init carries the state
      expect(sent, isEmpty);

      final events = <Race3DEvent>[];
      final sub = c.events.listen(events.add);
      c.handleMessage('{"type":"ready","webgl":true}');
      expect(sent.single['type'], 'init');
      expect((sent.single['data'] as Map)['mode'], 'replay');
      expect(c.isReady, isTrue);

      c.seek(1234);
      c.setMode(Race3DMode.drone, t: 5760, speed: 2);
      c.follow(null);
      expect(sent[1], {'type': 'seek', 't': 1234});
      expect(sent[2], {'type': 'mode', 'mode': 'drone', 't': 5760, 'speed': 2});
      expect(sent[3], {'type': 'follow', 'id': null});

      c.handleMessage('{"type":"time","t":4615.5,"playing":true}');
      c.handleMessage('{"type":"pick","id":42}');
      c.handleMessage('not json');
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<Race3DTime>().single.t, 4615.5);
      expect(events.whereType<Race3DPick>().single.id, 42);

      // A page reload needs a fresh init; onPageFinished is the fallback.
      c.pageStarted();
      c.pageFinished();
      expect(sent.last['type'], 'init');
      await sub.cancel();
      c.dispose();
    });
  });
}
