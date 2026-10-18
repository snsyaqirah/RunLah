import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runlah/core/l10n/bm_cheer.dart';
import 'package:runlah/core/l10n/i18n.dart';
import 'package:runlah/data/demo/kl_course.dart';
import 'package:runlah/data/models.dart';
import 'package:runlah/features/cheer/add_runner_sheet.dart';
import 'package:runlah/features/cheer/cheer_live.dart';
import 'package:runlah/features/cheer/cheer_screen.dart';
import 'package:runlah/features/cheer/cheer_spots_screen.dart';
import 'package:runlah/features/cheer/live_map_screen.dart';
import 'package:runlah/features/cheer/live_runner_card.dart';
import 'package:runlah/features/cheer/ranking_screen.dart';
import 'package:runlah/features/cheer/runner_detail_screen.dart';

import 'helpers.dart';

const _sizes = [Size(390, 844), Size(360, 740)];

/// Live race at 4000 s (Arep past halfway, friends on course), paused so
/// no sim timer outlives the test.
Future<void> _goLive(WidgetTester tester, TestApp app, {double at = 4000}) async {
  app.sim.fireGun();
  app.sim.jumpTo(at);
  app.sim.pause();
  // Lets the insights controller's throttled recompute and the cheer
  // engine's 1 Hz refresh run.
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(milliseconds: 600));
}

/// Scroll the first scrollable to the end in steps, so every card is laid
/// out at least once (catches overflow further down).
Future<void> _scrollThrough(WidgetTester tester, {int steps = 8}) async {
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < steps; i++) {
    await tester.drag(scrollable, const Offset(0, -450), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Drag the first scrollable until [finder] matches something (several
/// matches are fine, unlike scrollUntilVisible).
Future<void> _scrollUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 12 && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -250), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  group('parseFollowCode', () {
    test('accepts deep links, web links and plain bibs', () {
      expect(parseFollowCode('runlah://follow/20417'), '20417');
      expect(parseFollowCode('https://runlah.app/r/34144'), '34144');
      expect(parseFollowCode('http://runlah.app/r/28803?ref=qr'), '28803');
      expect(parseFollowCode(' 28803 '), '28803');
      expect(parseFollowCode('Follow Arep live: https://runlah.app/r/34144 !'), '34144');
      expect(parseFollowCode('hello'), isNull);
      expect(parseFollowCode(''), isNull);
    });
  });

  test('suggested cheer spots cover checkpoints and KL landmarks', () {
    final race = buildDemoEvent(raceDay: DateTime(2026, 10, 4)).races.first;
    final spots = CheerSpot.suggested(race);
    final names = spots.map((s) => s.name).toList();
    expect(names, containsAll(['KLCC', 'Bukit Bintang', 'Brickfields', 'Dataran Merdeka']));
    for (var i = 1; i < spots.length; i++) {
      expect(spots[i].distanceM, greaterThanOrEqualTo(spots[i - 1].distanceM));
    }
  });

  test('BM translations keep their placeholders', () {
    final re = RegExp(r'\{(\w+)\}');
    for (final e in bmCheer.entries) {
      final en = re.allMatches(e.key).map((m) => m.group(1)).toSet();
      final ms = re.allMatches(e.value).map((m) => m.group(1)).toSet();
      expect(ms, en, reason: e.key);
    }
  });

  for (final size in _sizes) {
    final w = size.width.toInt();

    testWidgets('Cheer tab pre-race @$w', (tester) async {
      final app = await pumpScreen(tester, (_) => const CheerScreen(), size: size);
      expect(find.text('Cheer'), findsWidgets);
      expect(find.byType(LiveRunnerCard), findsWidgets);
      expect(find.text('NOT STARTED'), findsWidgets);
      expect(app.sim.status, RaceStatus.preRace);
      await _scrollThrough(tester);
    });

    testWidgets('Cheer tab live @$w', (tester) async {
      final app = await pumpScreen(tester, (_) => const CheerScreen(), size: size);
      await _goLive(tester, app);
      // Overtake counter and leaders strip are filled by the 1 Hz engine.
      final live = CheerLive.of(app.sim);
      expect(live.counts(app.sim.youId).lastCp, greaterThan(0));
      expect(live.leaderMen, isNotNull);
      expect(find.text('Leaders on course'), findsOneWidget);
      // The cards sit below the status card and map on small phones.
      await _scrollUntilFound(tester, find.text('RUNNING'));
      expect(find.text('RUNNING'), findsWidgets);
      await _scrollThrough(tester);
    });

    testWidgets('Cheer tab finished @$w', (tester) async {
      await pumpScreen(tester, (_) => const CheerScreen(), size: size, finished: true);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('FINISHED'), findsWidgets);
      await _scrollThrough(tester);
      expect(find.text('Race Insights'), findsWidgets);
    });

    testWidgets('add runner by search @$w', (tester) async {
      final app = await pumpScreen(tester, (_) => const CheerScreen(), size: size);
      final before = app.follows.ids.length;
      await tester.tap(find.byTooltip('Add runner'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Follow a runner'), findsOneWidget);

      // Pick someone who isn't followed yet: the first match for a common name.
      final target = app.sim.search('Aiman').firstWhere((p) => !app.follows.isFollowing(p.id) && p.id != app.sim.youId);
      await tester.enterText(find.byKey(const ValueKey('cheer-search')), target.bib);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(target.displayName), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, 'Follow').first);
      await tester.pump(const Duration(milliseconds: 400));
      expect(app.follows.ids.length, before + 1);
      expect(app.follows.isFollowing(target.id), isTrue);
      expect(find.text('Following'), findsWidgets);

      // Close the sheet: the new card animates into the list.
      await tester.tapAt(const Offset(20, 20));
      await tester.pump(const Duration(milliseconds: 800));
      await _scrollThrough(tester);
      expect(find.byType(LiveRunnerCard), findsNWidgets(4));
    });

    testWidgets('ranking live and official @$w', (tester) async {
      final app = await pumpScreen(tester, (_) => const RankingScreen(), size: size);
      await _goLive(tester, app, at: 5000);
      expect(find.text('Leaders on course'), findsOneWidget);
      expect(find.text('PROVISIONAL'), findsOneWidget);
      await _scrollThrough(tester, steps: 4);

      app.finishRace();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('OFFICIAL'), findsOneWidget);
      await tester.tap(find.text('Women'));
      await tester.pump(const Duration(milliseconds: 500));
      // The chip row scrolls sideways on narrow phones.
      await tester.ensureVisible(find.textContaining('My category'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.textContaining('My category'));
      await tester.pump(const Duration(milliseconds: 500));
      final chip = tester.widget<ChoiceChip>(find.ancestor(of: find.textContaining('My category'), matching: find.byType(ChoiceChip)));
      expect(chip.selected, isTrue);
      await _scrollThrough(tester, steps: 12);
    });

    testWidgets('runner detail + send cheer @$w', (tester) async {
      late int qirah;
      final app = await pumpScreen(tester, (a) {
        qirah = a.sim.friendIds[0];
        return RunnerDetailScreen(participantId: qirah);
      }, size: size);
      await _goLive(tester, app, at: 3600);
      final cheersBefore = app.sim.cheersFor(qirah).length;
      await tester.scrollUntilVisible(find.text('Jangan give up!'), 300, scrollable: find.byType(Scrollable).first);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Jangan give up!'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(app.sim.cheersFor(qirah).length, cheersBefore + 1);
      expect(find.text('CHEER SENT!'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await _scrollThrough(tester);
    });

    testWidgets('runner detail finished shows meeting point @$w', (tester) async {
      late int qirah;
      await pumpScreen(tester, (a) {
        qirah = a.sim.friendIds[0];
        return RunnerDetailScreen(participantId: qirah, scrollToMeet: true);
      }, size: size, finished: true);
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('Meeting point B'), findsOneWidget);
      expect(find.text('See Race Insights'), findsOneWidget);
      await _scrollThrough(tester);
    });

    testWidgets('cheer spots @$w', (tester) async {
      final app = await pumpScreen(tester, (_) => const CheerSpotsScreen(), size: size);
      await _goLive(tester, app, at: 1200);
      expect(find.text('Cheer spots'), findsOneWidget);
      expect(find.textContaining('KLCC'), findsWidgets);
      await tester.tap(find.byTooltip('Leave-now alert').first);
      await tester.pump(const Duration(milliseconds: 400));
      expect(CheerLive.of(app.sim).alarms, isNotEmpty);
      await _scrollThrough(tester);
      CheerLive.of(app.sim).alarms.clear();
    });

    testWidgets('live map with field @$w', (tester) async {
      final app = await pumpScreen(tester, (a) => LiveMapScreen(focus: a.sim.friendIds[0]), size: size);
      await _goLive(tester, app, at: 3000);
      await tester.tap(find.text('Show field'));
      await tester.pump(const Duration(seconds: 2));
      expect(CheerLive.of(app.sim).field, isNotEmpty);
      await tester.pump(const Duration(milliseconds: 500));
    });
  }

  testWidgets('Cheer tab in dark mode and Bahasa Malaysia', (tester) async {
    tester.view.physicalSize = const Size(360, 740) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    late TestApp app;
    await tester.runAsync(() async => app = await TestApp.create());
    I18n.instance.lang = 'ms';
    addTearDown(() => I18n.instance.lang = 'en');
    await tester.pumpWidget(app.wrap(const CheerScreen(), brightness: Brightness.dark));
    await _goLive(tester, app);
    expect(find.text('Sorak'), findsWidgets);
    await _scrollThrough(tester);
  });
}
