import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:runlah/core/theme.dart';
import 'package:runlah/data/achievements.dart';
import 'package:runlah/data/activity_store.dart';
import 'package:runlah/data/app_state.dart';
import 'package:runlah/data/demo/field_generator.dart';
import 'package:runlah/data/demo/kl_course.dart';
import 'package:runlah/data/sim/race_sim.dart';
import 'package:runlah/services/notification_center.dart';
import 'package:runlah/services/tracking_service.dart';
import 'package:runlah/services/voice_service.dart';
import 'package:runlah/services/weather_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Everything main() wires up, for widget tests.
class TestApp {
  TestApp._(this.prefs, this.settings, this.sim, this.follows, this.insights, this.notices, this.store, this.voice, this.tracking, this.achievements);

  final SharedPreferences prefs;
  final SettingsController settings;
  final RaceSim sim;
  final FollowsController follows;
  final InsightsController insights;
  final NotificationCenter notices;
  final ActivityStore store;
  final VoiceService voice;
  final TrackingService tracking;
  final Achievements achievements;

  static RaceSim? _cachedSim;

  /// Builds the app state. The 11,760-runner field is generated once and
  /// shared between tests (call [sim.reset] if a test needs a clean race).
  static Future<TestApp> create() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsController(prefs);
    final sim = _cachedSim ??= () {
      final event = buildDemoEvent(raceDay: DateTime(2026, 10, 4));
      return RaceSim(event: event, field: generateDemoField(event.races.first));
    }();
    sim.reset();
    final follows = FollowsController(sim, prefs);
    final insights = InsightsController(sim);
    final notices = NotificationCenter(sim, follows);
    final store = ActivityStore(prefs);
    final voice = VoiceService();
    final tracking = TrackingService(settings, store, voice);
    final achievements = Achievements(prefs, sim, store);
    return TestApp._(prefs, settings, sim, follows, insights, notices, store, voice, tracking, achievements);
  }

  /// Race finished and results official (most Insights screens want this).
  void finishRace() {
    sim.jumpTo(sim.race.cutoffS.toDouble());
    sim.pause();
    sim.publishOfficial();
  }

  Widget wrap(Widget child, {Brightness brightness = Brightness.light}) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: sim),
          ChangeNotifierProvider.value(value: follows),
          ChangeNotifierProvider.value(value: insights),
          ChangeNotifierProvider.value(value: notices),
          ChangeNotifierProvider.value(value: store),
          ChangeNotifierProvider.value(value: tracking),
          ChangeNotifierProvider.value(value: achievements),
          ChangeNotifierProvider(create: (_) => WeatherService()),
          ChangeNotifierProvider(create: (_) => ShellController()),
          Provider.value(value: voice),
        ],
        child: MaterialApp(theme: buildTheme(brightness), home: child),
      );
}

/// Pump [child] on a phone-sized screen with all providers.
Future<TestApp> pumpScreen(WidgetTester tester, Widget Function(TestApp app) child, {bool finished = false, Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  late TestApp app;
  await tester.runAsync(() async => app = await TestApp.create());
  if (finished) app.finishRace();
  await tester.pumpWidget(app.wrap(child(app)));
  await tester.pump(const Duration(milliseconds: 500));
  return app;
}
