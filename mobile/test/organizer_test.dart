import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runlah/data/models.dart';
import 'package:runlah/features/organizer/ocr/bib_scanner.dart';
import 'package:runlah/features/organizer/organizer_screen.dart';

import 'helpers.dart';

Future<void> openTab(WidgetTester tester, String label) async {
  final tab = find.descendant(of: find.byType(TabBar), matching: find.text(label));
  await tester.ensureVisible(tab);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(tab);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 600));
}

/// The visible tab's vertical list (tab bar and CSV previews scroll sideways).
final verticalList = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).hitTestable().first;

/// Scrolls the visible tab's list to the end in steps (lays out every card).
Future<void> scrollTab(WidgetTester tester, {int steps = 10}) async {
  for (var i = 0; i < steps; i++) {
    await tester.drag(verticalList, const Offset(0, -350), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Drags the nearest vertical scrollable so [target] sits mid-screen.
Future<void> centre(WidgetTester tester, Finder target) async {
  await tester.pump();
  final rect = tester.getRect(target);
  final mid = tester.view.physicalSize.height / tester.view.devicePixelRatio / 2;
  final position = tester.state<ScrollableState>(verticalList).position;
  position.jumpTo((position.pixels - (mid - rect.center.dy)).clamp(position.minScrollExtent, position.maxScrollExtent));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<TestApp> pumpDark(WidgetTester tester, Widget Function(TestApp app) child, {Size size = const Size(360, 740)}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  late TestApp app;
  await tester.runAsync(() async => app = await TestApp.create());
  await tester.pumpWidget(app.wrap(child(app), brightness: Brightness.dark));
  await tester.pump(const Duration(milliseconds: 500));
  return app;
}

void main() {
  test('OCR picks bib-like numbers and favours the big print', () {
    final hits = extractBibs([
      (text: 'KL', height: 20, confidence: 0.9),
      (text: '34144', height: 120, confidence: 0.95),
      (text: '2026', height: 30, confidence: 0.9),
      (text: 'RUN42', height: 40, confidence: 0.9),
    ]);
    expect(hits.first.bib, '34144');
    expect(hits.any((h) => h.bib == '42'), isFalse);
    expect(hits.first.confidence, greaterThan(hits.last.confidence));
  });

  testWidgets('dark mode: every tab renders at 360x740', (tester) async {
    final app = await pumpDark(tester, (_) => const OrganizerScreen());
    app.sim.fireGun();
    app.sim.jumpTo(6200);
    app.sim.pause();
    await tester.pump(const Duration(milliseconds: 1500));
    for (final t in ['Race control', 'Heatmap', 'SOS', 'Camera', 'Results', 'Setup']) {
      await openTab(tester, t);
      await scrollTab(tester, steps: 6);
    }
    await tester.pump(const Duration(seconds: 5));
  });

  const sizes = [Size(390, 844), Size(360, 740)];
  for (final size in sizes) {
    final tag = '${size.width.round()}x${size.height.round()}';

    testWidgets('race control: gun button, live field, close $tag', (tester) async {
      final app = await pumpScreen(tester, (_) => const OrganizerScreen(), size: size);
      expect(find.text('GUN'), findsOneWidget);
      await scrollTab(tester);

      await tester.drag(verticalList, const Offset(0, 3000));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('gun-button')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Fire the gun?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-gun')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(app.sim.status, RaceStatus.live);

      app.sim.jumpTo(4500);
      app.sim.pause();
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.scrollUntilVisible(find.text('On course'), 200, scrollable: verticalList);
      await tester.scrollUntilVisible(find.text('Finishers per minute'.toUpperCase()), 200, scrollable: verticalList);
      await tester.pump(const Duration(milliseconds: 800));

      // Close the race from the console.
      final close = find.byKey(const Key('close-race'));
      await tester.scrollUntilVisible(close, -200, scrollable: verticalList);
      await centre(tester, close);
      await tester.tap(close);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('confirm-close')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(app.sim.status, RaceStatus.closed);
      await scrollTab(tester);
      app.sim.pause();
    });

    testWidgets('heatmap pre-race and live $tag', (tester) async {
      final app = await pumpScreen(tester, (_) => const OrganizerScreen(), size: size);
      await openTab(tester, 'Heatmap');
      expect(find.textContaining('The heatmap comes alive after the gun'), findsOneWidget);
      app.sim.fireGun();
      app.sim.jumpTo(1500);
      app.sim.pause();
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.textContaining('near '), findsWidgets);
      await scrollTab(tester);
    });

    testWidgets('SOS queue: alert arrives, acknowledge, medic, close $tag', (tester) async {
      final app = await pumpScreen(tester, (_) => const OrganizerScreen(), size: size);
      await openTab(tester, 'SOS');
      expect(find.text('No SOS alerts'), findsOneWidget);
      app.sim.fireGun();
      app.sim.jumpTo(2800);
      app.sim.pause();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(app.sim.sosAlerts, hasLength(1));
      final id = app.sim.sosAlerts.first.id;
      expect(find.text('Cramp, cannot continue'), findsOneWidget);
      await tester.tap(find.byKey(Key('sos-ack-$id')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(app.sim.sosAlerts.first.status, 'acknowledged');
      await tester.tap(find.byKey(Key('sos-medic-$id')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Medic team'), findsWidgets);
      await tester.tap(find.byKey(Key('sos-close-$id')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(app.sim.sosAlerts.first.status, 'closed');
      await scrollTab(tester);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('checkpoint camera: manual read, simulated reads, review $tag', (tester) async {
      final app = await pumpScreen(tester, (_) => const OrganizerScreen(), size: size);
      await openTab(tester, 'Camera');
      app.sim.fireGun();
      app.sim.jumpTo(3000);
      app.sim.pause();
      await tester.pump(const Duration(milliseconds: 500));

      final pad = find.byKey(const Key('pad-record'));
      await tester.ensureVisible(pad);
      await tester.pump(const Duration(milliseconds: 300));
      await centre(tester, find.byKey(const Key('pad-5')));
      for (final d in '34144'.split('')) {
        await tester.tap(find.byKey(Key('pad-$d')));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(pad);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('recorded at'), findsOneWidget);
      expect(app.sim.staffReads.first.bib, '34144');
      expect(app.sim.staffReads.first.source, PassSource.manual);

      // Unknown bib on the keypad.
      await centre(tester, find.byKey(const Key('pad-5')));
      for (final d in '999'.split('')) {
        await tester.tap(find.byKey(Key('pad-$d')));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(pad);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('is not on the start list'), findsOneWidget);

      final sim = find.byKey(const Key('simulate-read'));
      await tester.ensureVisible(sim);
      await tester.pump(const Duration(milliseconds: 300));
      await centre(tester, sim);
      for (var i = 0; i < 12; i++) {
        await tester.tap(sim);
        await tester.pump(const Duration(milliseconds: 350));
      }
      expect(app.sim.staffReads.where((r) => r.source == PassSource.ocr), isNotEmpty);
      await scrollTab(tester, steps: 14);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('results: CSV import publishes official $tag', (tester) async {
      final app = await pumpScreen(tester, (_) => const OrganizerScreen(), size: size);
      await openTab(tester, 'Results');
      expect(find.text('PROVISIONAL'), findsWidgets);
      expect(find.textContaining('Import 11,664 rows'), findsOneWidget);
      await tester.tap(find.byKey(const Key('import-csv')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('confirm-import')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 1000));
      expect(app.sim.official, isTrue);
      expect(app.sim.timingImported, isTrue);
      expect(find.text('OFFICIAL'), findsWidgets);
      await scrollTab(tester);
    });

    testWidgets('setup checklist and bib import $tag', (tester) async {
      await pumpScreen(tester, (_) => const OrganizerScreen(), size: size);
      await openTab(tester, 'Setup');
      expect(find.text('Event ready for race day'), findsOneWidget);
      final importBibs = find.byKey(const Key('import-bibs'));
      await tester.scrollUntilVisible(importBibs, 200, scrollable: verticalList);
      await centre(tester, importBibs);
      await tester.tap(importBibs);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('0 duplicates'), findsOneWidget);
      await scrollTab(tester);
    });
  }
}
