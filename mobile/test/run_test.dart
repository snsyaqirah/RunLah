import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runlah/data/activity_store.dart';
import 'package:runlah/features/run/activity_detail_screen.dart';
import 'package:runlah/features/run/finish_celebration.dart';
import 'package:runlah/features/run/run_screen.dart';
import 'package:runlah/services/points_sink.dart';
import 'package:runlah/services/tracking_service.dart';

import 'helpers.dart';

/// Scrolls the Run tab's list to the bottom in steps so every card gets
/// laid out (overflow errors fail the test).
Future<void> scrollThrough(WidgetTester tester, {int steps = 12}) async {
  final list = find.byType(Scrollable).first;
  for (var i = 0; i < steps; i++) {
    await tester.drag(list, const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> scrollToTop(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 8000));
  // Let the fling finish; a tap on a moving list only stops the scroll.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> settle(WidgetTester tester, {int seconds = 2}) async {
  for (var i = 0; i < seconds * 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  const sizes = [Size(390, 844), Size(360, 740)];

  for (final size in sizes) {
    final w = size.width.toInt();

    testWidgets('pre-race: bib, corral countdown, checks and settings ($w)', (tester) async {
      await pumpScreen(tester, (_) => const RunScreen(), size: size);
      await settle(tester);
      expect(find.text('34144'), findsOneWidget);
      // Plugin calls never answer in widget tests; the checks time out.
      await settle(tester, seconds: 6);
      expect(find.text('WAITING IN CORRAL'), findsOneWidget);
      expect(find.text('PRE-RACE CHECK'), findsOneWidget);
      // Plugins are missing in tests: the check degrades to demo mode.
      expect(find.text('Location: demo mode'), findsOneWidget);
      expect(find.text('Battery level unknown'), findsOneWidget);
      await scrollThrough(tester);
      expect(find.text('Voice coach'), findsOneWidget);
      expect(find.text('Link only'), findsWidgets);
    });

    testWidgets('live race view after the gun ($w)', (tester) async {
      final app = await pumpScreen(tester, (_) => const RunScreen(), size: size);
      app.sim.fireGun();
      app.sim.jumpTo(3000);
      app.sim.pause();
      await settle(tester);
      expect(find.text('Net time'), findsOneWidget);
      expect(find.text('OVERTAKES SINCE THE START LINE'), findsOneWidget);
      // Live overtakes counter (scans the field ≤1 Hz) is filled in.
      expect(find.textContaining('runners passed so far'), findsOneWidget);
      expect(find.textContaining('Next: '), findsOneWidget);
      await scrollThrough(tester);
      expect(find.text('Need help?'), findsOneWidget);
    });

    testWidgets('finished summary when opening after the finish ($w)', (tester) async {
      await pumpScreen(tester, (_) => const RunScreen(), size: size, finished: true);
      await settle(tester);
      expect(find.text('1:36:15'), findsWidgets);
      expect(find.text('See Race Insights'), findsOneWidget);
      // No confetti overlay when you open the app after finishing.
      expect(find.byType(FinishCelebration), findsNothing);
      await scrollThrough(tester);
      expect(find.text('Replay your race in 3D'), findsOneWidget);
    });

    testWidgets('free run with simulated GPS, offline queue and save ($w)', (tester) async {
      final app = await pumpScreen(tester, (_) => const RunScreen(), size: size);
      await tester.tap(find.text('Free run'));
      await settle(tester, seconds: 1);
      expect(find.text('START'), findsOneWidget);
      // Sample runs are seeded so history isn't empty.
      expect(app.store.activities.length, 2);

      await tester.tap(find.text('START'));
      // No GPS plugin in tests: the status check times out and the run
      // falls back to simulated GPS.
      await settle(tester, seconds: 5);
      final t = app.tracking;
      expect(t.state, TrackingState.running);
      expect(t.simulated, isTrue);
      expect(find.text('Simulated GPS'), findsWidgets);

      t.simSpeed = 30;
      await settle(tester, seconds: 16);
      expect(t.distanceM, greaterThan(1000));
      expect(t.splitsS, isNotEmpty);
      expect(t.uploadedPoints, greaterThan(0));
      expect((t.sink as DemoPointsSink).sent.first['source'], 'phone');

      t.simulateOffline = true;
      await settle(tester, seconds: 16);
      expect(t.queued.value, greaterThan(0));
      await scrollThrough(tester, steps: 4);
      expect(find.textContaining('will upload when online'), findsOneWidget);
      expect(find.text('LIVE SHARE LINK'), findsOneWidget);

      final backlog = t.queued.value;
      expect(backlog, greaterThan(50));
      t.simulateOffline = false;
      await settle(tester, seconds: 2);
      // The backlog went up in one batch; only fresh points are waiting.
      expect(t.queued.value, lessThan(backlog ~/ 2));

      t.pause();
      await settle(tester, seconds: 1);
      final saved = t.stop();
      expect(saved, isNotNull);
      expect(saved!.distanceM, greaterThan(1000));
      expect(app.store.byId(saved.id), isNotNull);
      await settle(tester, seconds: 2);
      expect(find.text('START'), findsOneWidget);
    });
  }

  testWidgets('crossing the finish shows the celebration', (tester) async {
    final app = await pumpScreen(tester, (_) => const RunScreen());
    app.sim.fireGun();
    final finish = app.sim.crossingTime(app.sim.youId, app.sim.race.distanceM)!;
    app.sim.jumpTo(finish - 20);
    app.sim.pause();
    await settle(tester);
    app.sim.jumpTo(finish + 2);
    await settle(tester, seconds: 3);
    expect(find.byType(FinishCelebration), findsOneWidget);
    expect(find.text('You did it, Arep!'), findsOneWidget);
    await settle(tester, seconds: 3);
    await tester.tap(find.text('Close'));
    await settle(tester);
    expect(find.byType(FinishCelebration), findsNothing);
    expect(find.text('See Race Insights'), findsOneWidget);
  });

  testWidgets('live view in dark mode', (tester) async {
    final app = await pumpScreen(tester, (_) => const RunScreen(), size: const Size(360, 740));
    await tester.pumpWidget(app.wrap(const RunScreen(), brightness: Brightness.dark));
    app.sim.fireGun();
    app.sim.jumpTo(5200);
    app.sim.pause();
    await settle(tester);
    await scrollThrough(tester);
    expect(find.text('Need help?'), findsOneWidget);
  });

  testWidgets('Bahasa Malaysia at 360 px: pre-race, free run and live', (tester) async {
    final app = await pumpScreen(tester, (_) => const RunScreen(), size: const Size(360, 740));
    app.settings.lang = 'ms';
    await tester.pumpWidget(app.wrap(KeyedSubtree(key: UniqueKey(), child: const RunScreen())));
    await settle(tester, seconds: 6);
    expect(find.text('Hari perlumbaan'), findsOneWidget);
    await scrollThrough(tester);
    await scrollToTop(tester);
    await tester.tap(find.text('Larian bebas'));
    await settle(tester, seconds: 1);
    expect(find.text('MULA'), findsOneWidget);
    await scrollThrough(tester, steps: 4);
    await scrollToTop(tester);
    await tester.tap(find.text('Hari perlumbaan'));
    app.sim.fireGun();
    app.sim.jumpTo(3000);
    app.sim.pause();
    await settle(tester);
    expect(find.text('Masa bersih'), findsOneWidget);
    await scrollThrough(tester);
    app.settings.lang = 'en';
  });

  testWidgets('saved run detail screen renders map, chart and splits', (tester) async {
    late String id;
    await pumpScreen(tester, (app) {
      id = app.store.activities.first.id;
      return ActivityDetailScreen(activityId: id);
    }, size: const Size(360, 740));
    await settle(tester);
    expect(find.text('Distance'), findsOneWidget);
    await scrollThrough(tester, steps: 6);
    expect(find.text('LIVE SHARE LINK'), findsOneWidget);
  });

  test('activity store queue batches, acks and persists', () async {
    final app = await TestApp.create();
    final store = app.store;
    final start = DateTime.utc(2026, 10, 4, 5);
    final pts = [
      for (var i = 0; i < 1200; i++) TrackPoint(t: start.add(Duration(seconds: i * 5)), lat: 3.15, lng: 101.71, acc: 5, spd: 2.8),
    ];
    store.enqueue('a1', pts);
    expect(store.queuedCount, 1200);
    final b = store.nextBatch()!;
    expect(b.points.length, 500);
    expect(b.points.first.toApiJson()['t'], '2026-10-04T05:00:00Z');
    store.ack('a1', b.points.last.t);
    expect(store.queuedCount, 700);
    store.persistQueue();
    final again = ActivityStore(app.prefs);
    expect(again.queuedCount, 700);
    expect(ActivityStore.newShareToken().length, 22);
  });
}
