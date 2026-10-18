import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:runlah/core/l10n/i18n.dart';
import 'package:runlah/data/achievements.dart';
import 'package:runlah/data/models.dart';
import 'package:runlah/features/profile/privacy_screen.dart';
import 'package:runlah/features/profile/profile_screen.dart';
import 'package:runlah/features/profile/selfie_frame_screen.dart';
import 'package:runlah/features/profile/settings_screen.dart';
import 'package:runlah/features/profile/wrapped_screen.dart';
import 'package:runlah/features/shell/shell.dart';

import 'helpers.dart';

const _sizes = [Size(390, 844), Size(360, 740)];

ProfileView _view(TestApp app) => app.achievements.view(app.insights.snapshot, targetTimeS: app.settings.targetTimeS);

BadgeState _badge(ProfileView v, BadgeId id) => v.badges.firstWhere((b) => b.id == id);

/// Click through the "badge unlocked" celebration until it closes.
Future<int> _dismissCelebration(WidgetTester tester) async {
  var shown = 1;
  while (find.text('Next badge').evaluate().isNotEmpty) {
    await tester.tap(find.text('Next badge'));
    await tester.pump(const Duration(milliseconds: 300));
    shown++;
  }
  await tester.tap(find.text('Nice!'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
  return shown;
}

/// Scroll [text] into view, then tap it.
Future<void> _tapText(WidgetTester tester, String text, {Duration settle = const Duration(milliseconds: 400)}) async {
  if (find.text(text).evaluate().isEmpty) {
    // Lazily built list: scroll until the item exists.
    await tester.scrollUntilVisible(find.text(text), 200, scrollable: find.byType(Scrollable).first);
  }
  final f = find.text(text).last;
  await tester.ensureVisible(f);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(f);
  await tester.pump(settle);
}

Future<void> _scrollAll(WidgetTester tester, Finder scrollable) async {
  for (var i = 0; i < 8; i++) {
    await tester.drag(scrollable, const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  tearDown(() => I18n.instance.lang = 'en');

  test('demo history and personal bests', () {
    final half = demoHistory.where((e) => e.pbDistance == PbDistance.half).map((e) => e.netS!).reduce((a, b) => a < b ? a : b);
    expect(half, 1 * 3600 + 41 * 60 + 2);
    expect(pbDistanceFor(21097.5), PbDistance.half);
    expect(pbDistanceFor(10000), PbDistance.k10);
    expect(pbDistanceFor(15000), isNull);
  });

  for (final size in _sizes) {
    final tag = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('profile before the race · $tag', (tester) async {
      final app = await pumpScreen(tester, (_) => const ProfileScreen(), size: size);
      final v = _view(app);
      expect(find.text('Arep'), findsWidgets);
      expect(find.text('Bib 34144 · M 20-29'), findsOneWidget);
      expect(find.text('BADGES'), findsOneWidget);
      expect(v.halfPb.timeS, 6062);
      expect(v.halfPb.isNew, isFalse);
      expect(_badge(v, BadgeId.halfFinisher).unlocked, isTrue);
      expect(_badge(v, BadgeId.sub140).unlocked, isFalse);
      expect(_badge(v, BadgeId.fiveHalves).progress, closeTo(0.6, 1e-9));
      // Sample free runs from the Run tab feed the free-run badges.
      expect(_badge(v, BadgeId.firstFreeRun).unlocked, app.store.freeRuns.isNotEmpty);
      expect(v.unseen, isEmpty, reason: 'nothing to celebrate before the race');
      expect(find.text('Badge unlocked!'), findsNothing);
      await _scrollAll(tester, find.byType(CustomScrollView));
      expect(find.text('KL City Night-to-Dawn Run 2026'), findsWidgets);
      expect(find.text('UPCOMING'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('profile after the race: badges, new PB, celebration · $tag', (tester) async {
      final app = await pumpScreen(tester, (_) => const ProfileScreen(), finished: true, size: size);
      final v = _view(app);
      expect(v.current.netS, 5775);
      expect(v.halfPb.isNew, isTrue);
      expect(v.halfPb.improvementS, 6062 - 5775);
      for (final id in [BadgeId.sub140, BadgeId.top2, BadgeId.overtaker, BadgeId.categoryTop100, BadgeId.dawnPatrol, BadgeId.firstRunLah, BadgeId.pbBreaker, BadgeId.targetSmashed]) {
        expect(_badge(v, id).unlocked, isTrue, reason: id.name);
      }
      expect(_badge(v, BadgeId.negativeSplit).unlocked, isFalse, reason: 'Arep slowed in the 2nd half');
      expect(_badge(v, BadgeId.fiveHalves).progress, closeTo(0.8, 1e-9));
      expect(v.wrapped.passedBeforeHalf, greaterThan(1000));

      // The unlock celebration shows once, then never again.
      expect(find.textContaining('badges unlocked!'), findsOneWidget);
      final shown = await _dismissCelebration(tester);
      expect(shown, v.unseen.length);
      expect(_view(app).unseen, isEmpty);
      expect(app.prefs.getStringList('ach.seenBadges'), containsAll(['sub140', 'top2', 'overtaker']));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Nice!'), findsNothing);

      expect(find.text('1:36:15'), findsWidgets);
      expect(find.text('NEW PB'), findsWidgets);
      await _scrollAll(tester, find.byType(CustomScrollView));
      expect(find.text('OFFICIAL'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('language switch to Bahasa Malaysia · $tag', (tester) async {
      I18n.missing.clear();
      final app = await pumpScreen(tester, (_) => const ProfileScreen(), finished: true, size: size);
      await _dismissCelebration(tester);
      await tester.tap(find.text('BM'));
      await tester.pump();
      expect(app.settings.lang, 'ms');
      expect(app.prefs.getString('lang'), 'ms');
      // The real app re-keys MaterialApp on language; do the same here.
      await tester.pumpWidget(app.wrap(const KeyedSubtree(key: ValueKey('ms'), child: ProfileScreen())));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Saya'), findsOneWidget);
      expect(find.text('LENCANA'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('REKOD PERIBADI'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('REKOD PERIBADI'), findsOneWidget);
      await _scrollAll(tester, find.byType(CustomScrollView));
      // Other screens in BM too.
      for (final screen in const <Widget>[SettingsScreen(), PrivacyScreen(), RaceWrappedScreen(), SelfieFrameScreen()]) {
        await tester.pumpWidget(app.wrap(KeyedSubtree(key: UniqueKey(), child: screen)));
        await tester.pump(const Duration(milliseconds: 600));
        if (screen is! RaceWrappedScreen) await _scrollAll(tester, find.byType(Scrollable).first);
      }
      expect(I18n.missing, isEmpty, reason: 'every profile string has a BM translation');
      expect(tester.takeException(), isNull);
    });

    testWidgets('race wrapped pages · $tag', (tester) async {
      await pumpScreen(tester, (_) => const RaceWrappedScreen(), finished: true, size: size);
      expect(find.text('2026'), findsWidgets);
      Future<void> next() async {
        await tester.tapAt(Offset(size.width * 0.85, size.height * 0.5));
        await tester.pump(); // slide starts
        await tester.pump(const Duration(milliseconds: 500)); // slide done
        await tester.pump(); // page becomes active, count-ups start
        await tester.pump(const Duration(milliseconds: 1600));
      }

      await next();
      expect(find.text('THIS YEAR YOU RACED'), findsOneWidget);
      await next();
      expect(find.text('YOUR BEST RESULT'), findsOneWidget);
      expect(find.text('1:36:15'), findsWidgets);
      await next();
      expect(find.text('YOU OVERTOOK'), findsOneWidget);
      await next();
      expect(find.text('YOUR FASTEST QUARTER'), findsOneWidget);
      expect(find.text('Q2'), findsWidgets);
      await next();
      expect(find.textContaining('YOUR'), findsWidgets);
      await next();
      expect(find.text('Share my Wrapped'), findsOneWidget);
      // Tap on the left half goes back.
      await tester.tapAt(Offset(size.width * 0.1, size.height * 0.5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.text('Share my Wrapped'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('race wrapped before the race · $tag', (tester) async {
      await pumpScreen(tester, (_) => const RaceWrappedScreen(), size: size);
      for (var i = 0; i < 6; i++) {
        await tester.tapAt(Offset(size.width * 0.85, size.height * 0.5));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 1600));
        if (find.text('UNLOCKS ON RACE DAY').evaluate().isNotEmpty || find.text('Unlocks on race day').evaluate().isNotEmpty) break;
      }
      expect(find.text('Unlocks on race day'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('selfie frame without a photo · $tag', (tester) async {
      await pumpScreen(tester, (_) => const SelfieFrameScreen(), finished: true, size: size);
      expect(find.text('FINISHER'), findsOneWidget);
      expect(find.text('1:36:15'), findsOneWidget);
      await _tapText(tester, 'Race bib');
      // Let the frame cross-fade finish.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('34144'), findsOneWidget);
      await _tapText(tester, 'Minimal');
      await _scrollAll(tester, find.byType(Scrollable).first);
      expect(find.text('Share framed photo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('settings · $tag', (tester) async {
      final app = await pumpScreen(tester, (_) => const SettingsScreen(), size: size);
      // Top to bottom (the list builds lazily).
      await _tapText(tester, 'Miles');
      expect(app.settings.units.name, 'mi');
      await _tapText(tester, 'Dark');
      expect(app.settings.themeMode, ThemeMode.dark);
      await _tapText(tester, 'Bib only');
      expect(app.settings.resultsName, ResultsName.bibOnly);
      expect(app.sim.you.resultsName, ResultsName.bibOnly);
      expect(find.text('Others see you as: Runner 34144'), findsOneWidget);
      await _tapText(tester, 'Target time', settle: const Duration(milliseconds: 600));
      await _tapText(tester, '+1 min');
      await _tapText(tester, 'Save target', settle: const Duration(milliseconds: 600));
      expect(app.settings.targetTimeS, 6060);
      app.sim.you.resultsName = ResultsName.full;
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('privacy: export falls back to a dialog, delete resets', (tester) async {
    final app = await pumpScreen(tester, (_) => const PrivacyScreen());
    app.settings.displayName = 'Someone';
    await _tapText(tester, 'Export my data', settle: const Duration(milliseconds: 100));
    // The share plugin isn't there in tests: let its real async failure land.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Your data'), findsOneWidget);
    expect(find.textContaining('"bib": "34144"'), findsOneWidget);
    await _tapText(tester, 'Close');
    await tester.pump(const Duration(milliseconds: 300));
    await _tapText(tester, 'Delete my data');
    await _tapText(tester, 'Delete');
    await tester.pump(const Duration(milliseconds: 300));
    expect(app.settings.displayName, 'Arep');
    expect(app.prefs.getString('displayName'), 'Arep');
    expect(app.prefs.getStringList('follows'), isEmpty);
    expect(app.follows.ids, isEmpty);
    expect(app.store.activities, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('my QR code and dark mode', (tester) async {
    final app = await pumpScreen(tester, (_) => const ProfileScreen(), size: const Size(360, 740));
    await tester.pumpWidget(app.wrap(const ProfileScreen(), brightness: Brightness.dark));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byIcon(Icons.qr_code_2_rounded).first);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('My QR code'), findsWidgets);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('runlah://follow/34144'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('celebration waits until the Me tab is visible', (tester) async {
    await pumpScreen(tester, (_) => const Shell(), finished: true);
    expect(find.textContaining('badges unlocked!'), findsNothing);
    await tester.tap(find.text('Me').last);
    await tester.pump(); // tab switch; the Me tab sees it's visible
    await tester.pump(); // celebration route pushed
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('badges unlocked!'), findsOneWidget);
    await _dismissCelebration(tester);
    expect(find.textContaining('badges unlocked!'), findsNothing);
  });
}
