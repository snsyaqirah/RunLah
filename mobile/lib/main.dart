import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/achievements.dart';
import 'data/activity_store.dart';
import 'data/app_state.dart';
import 'data/demo/field_generator.dart';
import 'data/demo/kl_course.dart';
import 'data/sim/race_sim.dart';
import 'services/notification_center.dart';
import 'services/push_service.dart';
import 'services/tracking_service.dart';
import 'services/voice_service.dart';
import 'services/weather_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  final settings = SettingsController(prefs);

  // Demo mode: a simulated race stands in for the Laravel API + Reverb.
  final event = buildDemoEvent();
  final sim = RaceSim(event: event, field: generateDemoField(event.races.first))..startCountdown();

  final follows = FollowsController(sim, prefs);
  final insights = InsightsController(sim);
  final notices = NotificationCenter(sim, follows);
  final store = ActivityStore(prefs);
  final voice = VoiceService();
  final tracking = TrackingService(settings, store, voice);
  final achievements = Achievements(prefs, sim, store);
  await initPushService(notices);

  runApp(
    MultiProvider(
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
      child: const RunLahApp(),
    ),
  );
}
