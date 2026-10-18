import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runlah/features/home/event_detail_screen.dart';
import 'package:runlah/features/home/home_screen.dart';
import 'package:runlah/services/weather_service.dart';

import 'helpers.dart';

/// Scrolls [scrollable] to the end in steps so every lazily built child gets
/// laid out (and any overflow is reported).
Future<void> scrollThrough(WidgetTester tester, Finder scrollable, {int steps = 12}) async {
  for (var i = 0; i < steps; i++) {
    await tester.drag(scrollable, const Offset(0, -350));
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Drags [scroll] so [target] sits mid-screen (clear of pinned app bars).
Future<void> centre(WidgetTester tester, Finder target, Finder scroll) async {
  await tester.pump();
  final rect = tester.getRect(target);
  final mid = tester.view.physicalSize.height / tester.view.devicePixelRatio / 2;
  final position = tester.state<ScrollableState>(scroll).position;
  position.jumpTo((position.pixels - (mid - rect.center.dy)).clamp(position.minScrollExtent, position.maxScrollExtent));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  const sizes = [Size(390, 844), Size(360, 740)];

  testWidgets('dark mode: home live and event detail at 360x740', (tester) async {
    tester.view.physicalSize = const Size(360, 740) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    late TestApp app;
    await tester.runAsync(() async => app = await TestApp.create());
    app.sim.fireGun();
    app.sim.jumpTo(5000);
    app.sim.pause();
    await tester.pumpWidget(app.wrap(const HomeScreen(), brightness: Brightness.dark));
    await tester.pump(const Duration(milliseconds: 1500));
    await scrollThrough(tester, find.byType(ListView));
    await tester.pumpWidget(app.wrap(const EventDetailScreen(), brightness: Brightness.dark));
    await tester.pump(const Duration(milliseconds: 800));
    await scrollThrough(tester, find.byType(Scrollable).first);
  });

  group('weather', () {
    test('heat risk bands and Open-Meteo parsing', () {
      final w = WeatherService.parse(
        '{"current":{"time":"2026-10-18T05:00","temperature_2m":25.1,"relative_humidity_2m":89,"apparent_temperature":29.4,"weather_code":3,"wind_speed_10m":4.2}}',
      );
      expect(w, isNotNull);
      expect(w!.estimated, isFalse);
      expect(w.risk, HeatRisk.moderate);
      expect(WeatherService.parse('not json'), isNull);
      expect(WeatherNow.typicalKlDawn().estimated, isTrue);
      final hot = WeatherNow(temperatureC: 34, humidityPct: 70, apparentC: 41, windKph: 3, weatherCode: 0, observedAt: DateTime(2026));
      expect(hot.risk, HeatRisk.extreme);
    });
  });

  for (final size in sizes) {
    final tag = '${size.width.round()}x${size.height.round()}';

    testWidgets('home pre-race $tag', (tester) async {
      await pumpScreen(tester, (_) => const HomeScreen(), size: size);
      expect(find.text('GUN IN'), findsOneWidget);
      expect(find.text('Good morning,').evaluate().length + find.text('Good afternoon,').evaluate().length + find.text('Good evening,').evaluate().length + find.text('Good night,').evaluate().length, 1);
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('34144'), 250, scrollable: list);
      expect(find.text('AREP'), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('Heat risk'), 250, scrollable: list);
      await scrollThrough(tester, find.byType(ListView));
      expect(find.text('Putrajaya Lakeside 10K'), findsOneWidget);
    });

    testWidgets('home live $tag', (tester) async {
      final app = await pumpScreen(tester, (_) => const HomeScreen(), size: size);
      app.sim.fireGun();
      app.sim.jumpTo(3000);
      app.sim.pause();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('0:50:00'), findsOneWidget);
      expect(find.text('On course'), findsOneWidget);
      await scrollThrough(tester, find.byType(ListView));
    });

    testWidgets('home finished $tag', (tester) async {
      await pumpScreen(tester, (_) => const HomeScreen(), finished: true, size: size);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('OFFICIAL'), findsWidgets);
      expect(find.text('1:36:15'), findsOneWidget);
      expect(find.text('See your Race Insights'), findsOneWidget);
      await scrollThrough(tester, find.byType(ListView));
    });

    testWidgets('event detail + join with bib $tag', (tester) async {
      await pumpScreen(tester, (_) => const EventDetailScreen(), size: size);
      final scroll = find.byType(Scrollable).first;
      final submit = find.byKey(const Key('join-submit'));
      await tester.scrollUntilVisible(submit, 200, scrollable: scroll);
      await tester.pump(const Duration(milliseconds: 300));
      await centre(tester, submit, scroll);

      // Unknown bib.
      await tester.enterText(find.byKey(const Key('join-bib')), '99999');
      await tester.enterText(find.byKey(const Key('join-code')), '123456');
      await centre(tester, submit, scroll);
      await tester.tap(submit);
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.textContaining('is not on the start list'), findsOneWidget);

      // Wrong code.
      await tester.enterText(find.byKey(const Key('join-bib')), '34144');
      await tester.enterText(find.byKey(const Key('join-code')), '123456');
      await centre(tester, submit, scroll);
      await tester.tap(submit);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('doesn\'t match bib 34144'), findsOneWidget);

      // Right code.
      await tester.enterText(find.byKey(const Key('join-code')), '261004');
      await centre(tester, submit, scroll);
      await tester.tap(submit);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('You\'re in!'), findsOneWidget);

      // Friends' bibs are already claimed by their own accounts.
      await centre(tester, find.text('Done'), scroll);
      await tester.tap(find.text('Done'));
      await tester.pump(const Duration(seconds: 1));
      await centre(tester, find.text('Link another bib'), scroll);
      await tester.tap(find.text('Link another bib'));
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(find.byKey(const Key('join-bib')), '20417');
      await tester.enterText(find.byKey(const Key('join-code')), '204170');
      await centre(tester, submit, scroll);
      await tester.tap(submit);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('already claimed by another RunLah account'), findsOneWidget);

      await scrollThrough(tester, scroll);
      expect(find.text('Cheer someone in this race'), findsOneWidget);
    });
  }
}
