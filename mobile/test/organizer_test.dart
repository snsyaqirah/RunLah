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

/// Scrolls the visible tab's list to the end in steps (lays out every card).
Future<void> scrollTab(WidgetTester tester, {int steps = 10}) async {
  final list = find.byType(ListView).hitTestable().first;
  for (var i = 0; i < steps; i++) {
    await tester.drag(list, const Offset(0, -350), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 120));
  }
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

  const sizes = [Size(390, 844), Size(360, 740)];
  for (final size in sizes) {
    final tag = '${size.width.round()}x${size.height.round()}';

    testWidgets('race control: gun button, live field, close $tag', (tester) async {
      final app = await pumpScreen(tester, (_) => const OrganizerScreen(), size: size);
      expect(find.text('GUN'), findsOneWidget);
      await scrollTab(tester);

      await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
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
      expect(find.text('Finishers per minute'.toUpperCase()), findsOneWidget);
      expect(find.text('On course'), findsOneWidget);
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
      await tester.scrollUntilVisible(importBibs, 200, scrollable: find.byType(Scrollable).hitTestable().last);
      await tester.tap(importBibs);
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.textContaining('0 duplicates'), findsOneWidget);
      await scrollTab(tester);
    });
  }
}
