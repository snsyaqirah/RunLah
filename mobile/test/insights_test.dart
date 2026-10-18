import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runlah/core/format.dart';
import 'package:runlah/core/l10n/i18n.dart';
import 'package:runlah/data/models.dart';
import 'package:runlah/data/sim/race_sim.dart';
import 'package:runlah/features/insights/certificate_screen.dart';
import 'package:runlah/features/insights/insights_screen.dart';
import 'package:runlah/features/insights/results_screen.dart';
import 'package:runlah/features/insights/share_card_screen.dart';

import 'helpers.dart';

/// Lets count-ups, bar growth and the place-line runner finish animating
/// (and flushes InsightsController's 1.5 s throttle timer).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 600));
  }
}

/// Drags [scrollable] down in steps so lazily built children get laid out
/// (and any overflow is reported).
Future<void> scrollThrough(WidgetTester tester, Finder scrollable, {int steps = 10}) async {
  for (var i = 0; i < steps; i++) {
    await tester.drag(scrollable, const Offset(0, -380), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.pump(const Duration(seconds: 2));
}

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).first);
  await settle(tester);
}

/// Race live, 50 minutes in, clock paused.
void goLive(TestApp app) {
  app.sim.fireGun();
  app.sim.jumpTo(3000);
  app.sim.pause();
}

/// Pumps a screen and disposes the app's InsightsController afterwards, so
/// snapshots from earlier tests don't keep recomputing on the shared sim.
Future<TestApp> pump(WidgetTester tester, Widget Function(TestApp app) child, {bool finished = false, Size size = const Size(390, 844)}) async {
  final app = await pumpScreen(tester, child, finished: finished, size: size);
  addTearDown(app.insights.dispose);
  await settle(tester);
  return app;
}

final _tabBody = find.byType(TabBarView);

void main() {
  const sizes = [Size(390, 844), Size(360, 740)];

  for (final size in sizes) {
    final tag = '${size.width.round()}x${size.height.round()}';

    testWidgets('results pre-race $tag', (tester) async {
      await pump(tester, (_) => const ResultsScreen(), size: size);
      expect(find.text('Results appear here as runners finish'), findsOneWidget);
      expect(find.text('Start list'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '34144');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Arep'), findsWidgets);
      await scrollThrough(tester, find.byType(CustomScrollView), steps: 3);
    });

    testWidgets('results finished $tag', (tester) async {
      final app = await pump(tester, (_) => const ResultsScreen(), finished: true, size: size);
      expect(find.text('1:36:15'), findsWidgets);
      expect(find.text('172nd'), findsWidgets);
      expect(find.text('OFFICIAL'), findsWidgets);
      expect(find.text('See your Race Insights'), findsOneWidget);
      final snap = app.insights.snapshot;
      final n = snap.finishers;
      expect(find.text('${fmtInt(n)} finishers'), findsOneWidget);
      // Filter to women and back.
      await tester.tap(find.text('Women').first);
      await settle(tester);
      expect(find.text('${fmtInt(snap.stats['gender:F']!.finishers)} finishers'), findsOneWidget);
      await tester.tap(find.text('Overall').first);
      await settle(tester);
      // Jump to your row on page 4.
      await tester.tap(find.byTooltip('Jump to you'));
      await settle(tester);
      expect(find.text('Arep'), findsWidgets);
      expect(find.text('172'), findsOneWidget); // your row's place, on page 4
      expect(find.text('151'), findsNothing); // scrolled past the top of page 4
      await scrollThrough(tester, find.byType(CustomScrollView), steps: 6);
    });

    testWidgets('results live $tag', (tester) async {
      await pump(tester, (app) {
        goLive(app);
        return const ResultsScreen();
      }, size: size);
      expect(find.text('ON COURSE'), findsOneWidget);
      expect(find.text('LIVE · PROVISIONAL'), findsWidgets);
      await scrollThrough(tester, find.byType(CustomScrollView), steps: 4);
    });

    testWidgets('insights finish tab for you $tag', (tester) async {
      await pump(tester, (app) => InsightsScreen(participantId: app.sim.youId), finished: true, size: size);
      expect(find.text('1:36:15'), findsWidgets);
      expect(find.textContaining('172'), findsWidgets);
      expect(find.text('172nd'), findsOneWidget);
      expect(find.text('Crossed the start 0:39 after the gun'), findsOneWidget);
      await scrollThrough(tester, _tabBody);
      expect(find.text('Ahead of 99.7% of female finishers'), findsOneWidget);
      expect(find.text('E-certificate'), findsOneWidget);
    });

    testWidgets('insights net/gun toggle $tag', (tester) async {
      final app = await pump(tester, (app) => InsightsScreen(participantId: app.sim.youId), finished: true, size: size);
      expect(app.insights.basis, RankBasis.net);
      await tester.tap(find.text('Gun').first);
      await settle(tester);
      expect(app.insights.basis, RankBasis.gun);
      expect(find.text('GUN TIME'), findsOneWidget);
      expect(find.text('1:36:54'), findsOneWidget);
      await tester.tap(find.text('Net').first);
      await settle(tester);
      expect(app.insights.basis, RankBasis.net);
    });

    testWidgets('insights speed, where, compare for you $tag', (tester) async {
      await pump(tester, (app) => InsightsScreen(participantId: app.sim.youId, initialTab: 1), finished: true, size: size);
      expect(find.text('SECTION SPEED'), findsOneWidget);
      await scrollThrough(tester, _tabBody);
      expect(find.text('3D race replay'), findsOneWidget);

      await openTab(tester, 'Where');
      expect(find.text('THE MALE WINNER FINISHED?'), findsOneWidget);
      await tester.tap(find.byTooltip('Next'));
      await settle(tester);
      await scrollThrough(tester, _tabBody, steps: 4);

      await openTab(tester, 'Compare');
      expect(find.text('SIDE BY SIDE'), findsOneWidget);
      await scrollThrough(tester, _tabBody, steps: 4);
      expect(find.text('GAP CHART'), findsOneWidget);
    });

    testWidgets('insights on-course runner while live $tag', (tester) async {
      await pump(tester, (app) {
        goLive(app);
        return InsightsScreen(participantId: app.sim.friendIds[1]); // Hafiz, no GPS
      }, size: size);
      expect(find.text('ON COURSE'), findsOneWidget);
      await scrollThrough(tester, _tabBody, steps: 4);
      for (final t in ['Speed', 'Where', 'Compare']) {
        await openTab(tester, t);
        await scrollThrough(tester, _tabBody, steps: 4);
      }
    });

    testWidgets('insights DNF runner while live $tag', (tester) async {
      late int dnfId;
      await pump(tester, (app) {
        goLive(app);
        final sim = app.sim;
        dnfId = sim.participants.firstWhere((p) => sim.plan(p.id).dnfAtM != null && sim.stateAt(p.id, 3000) == RunnerState.dnf).id;
        return InsightsScreen(participantId: dnfId);
      }, size: size);
      expect(find.text('Stopped racing'), findsOneWidget);
      await scrollThrough(tester, _tabBody, steps: 3);
      for (final t in ['Speed', 'Where', 'Compare']) {
        await openTab(tester, t);
        await scrollThrough(tester, _tabBody, steps: 3);
      }
    });

    testWidgets('share card $tag', (tester) async {
      await pump(tester, (app) => ShareCardScreen(participantId: app.sim.youId), finished: true, size: size);
      expect(find.text('runlah.app/r/34144'), findsWidgets);
      expect(find.text('1:36:15'), findsOneWidget);
      await tester.tap(find.text('Square 1:1'));
      await settle(tester);
      await tester.ensureVisible(find.text('Amber sunrise'));
      await tester.tap(find.text('Amber sunrise'));
      await settle(tester);
      await tester.ensureVisible(find.text('Fastest quarter'));
      await tester.tap(find.text('Fastest quarter'));
      await settle(tester);
      await tester.drag(find.byType(ListView), const Offset(0, 2000));
      await settle(tester);
      expect(find.text('fastest quarter (Q2)'), findsOneWidget);
      await scrollThrough(tester, find.byType(ListView), steps: 3);
      await tester.ensureVisible(find.text('Minimal light'));
      await tester.tap(find.text('Minimal light'));
      await settle(tester);
    });
  }

  testWidgets('share card while live', (tester) async {
    await pump(tester, (app) {
      goLive(app);
      return ShareCardScreen(participantId: app.sim.youId);
    });
    expect(find.text('ON COURSE · LIVE'), findsOneWidget);
  });

  testWidgets('e-certificate when official', (tester) async {
    await pump(tester, (app) => CertificateScreen(participantId: app.sim.youId), finished: true, size: const Size(360, 740));
    expect(find.text('CERTIFICATE'), findsOneWidget);
    expect(find.text('Arep'), findsOneWidget);
    expect(find.text('1:36:15'), findsOneWidget);
  });

  testWidgets('insights in dark mode', (tester) async {
    tester.view.physicalSize = const Size(360, 740) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    late TestApp app;
    await tester.runAsync(() async => app = await TestApp.create());
    addTearDown(app.insights.dispose);
    app.finishRace();
    await tester.pumpWidget(app.wrap(InsightsScreen(participantId: app.sim.youId), brightness: Brightness.dark));
    await settle(tester);
    expect(find.text('172nd'), findsOneWidget);
    await scrollThrough(tester, _tabBody, steps: 6);
    await openTab(tester, 'Speed');
    await scrollThrough(tester, _tabBody, steps: 6);
  });
  testWidgets('Bahasa Malaysia: every string translated, no overflow at 360', (tester) async {
    I18n.missing.clear();
    addTearDown(() => I18n.instance.lang = 'en');
    final app = await pump(tester, (app) {
      I18n.instance.lang = 'ms';
      return InsightsScreen(participantId: app.sim.youId);
    }, finished: true, size: const Size(360, 740));
    expect(find.text('KEDUDUKAN ANDA'), findsOneWidget);
    expect(find.text('ke-172'), findsOneWidget);
    await scrollThrough(tester, _tabBody, steps: 6);
    for (final t in ['Kelajuan', 'Di mana', 'Banding']) {
      await openTab(tester, t);
      await scrollThrough(tester, _tabBody, steps: 5);
    }
    await tester.pumpWidget(app.wrap(const ResultsScreen()));
    await settle(tester);
    expect(find.text('Lihat Analisis Perlumbaan anda'), findsOneWidget);
    await scrollThrough(tester, find.byType(CustomScrollView), steps: 3);
    await tester.pumpWidget(app.wrap(ShareCardScreen(participantId: app.sim.youId)));
    await settle(tester);
    await scrollThrough(tester, find.byType(ListView), steps: 3);
    await tester.pumpWidget(app.wrap(CertificateScreen(participantId: app.sim.youId)));
    await settle(tester);
    expect(I18n.missing, isEmpty);
  });
}
