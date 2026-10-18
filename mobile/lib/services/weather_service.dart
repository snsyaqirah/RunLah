import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// How risky the heat is for running, from the "feels like" temperature.
enum HeatRisk { low, moderate, high, extreme }

/// Current conditions at the start line.
class WeatherNow {
  const WeatherNow({
    required this.temperatureC,
    required this.humidityPct,
    required this.apparentC,
    required this.windKph,
    required this.weatherCode,
    required this.observedAt,
    this.estimated = false,
  });

  /// Typical KL conditions just before a dawn gun (late-year, ~04:30).
  /// Used offline, in tests, and until the first fetch returns.
  factory WeatherNow.typicalKlDawn() => WeatherNow(
        temperatureC: 25.2,
        humidityPct: 88,
        apparentC: 28.9,
        windKph: 5.4,
        weatherCode: 2,
        observedAt: DateTime.now(),
        estimated: true,
      );

  final double temperatureC;
  final double humidityPct;

  /// Open-Meteo "apparent temperature" (humidity and wind included).
  final double apparentC;
  final double windKph;

  /// WMO weather code.
  final int weatherCode;
  final DateTime observedAt;

  /// True when these are typical values, not a live reading.
  final bool estimated;

  /// NOAA heat index (Rothfusz regression), in °C.
  double get heatIndexC {
    final t = temperatureC * 9 / 5 + 32;
    final rh = humidityPct;
    var hi = 0.5 * (t + 61 + (t - 68) * 1.2 + rh * 0.094);
    if ((hi + t) / 2 >= 80) {
      hi = -42.379 +
          2.04901523 * t +
          10.14333127 * rh -
          0.22475541 * t * rh -
          0.00683783 * t * t -
          0.05481717 * rh * rh +
          0.00122874 * t * t * rh +
          0.00085282 * t * rh * rh -
          0.00000199 * t * t * rh * rh;
    }
    return (hi - 32) * 5 / 9;
  }

  /// The higher of the apparent temperature and the heat index.
  double get feelsLikeC => apparentC > heatIndexC ? apparentC : heatIndexC;

  /// Thresholds are set lower than generic heat-index bands because the
  /// runners are working hard for 1–4 hours.
  HeatRisk get risk {
    final f = feelsLikeC;
    if (f >= 38) return HeatRisk.extreme;
    if (f >= 32) return HeatRisk.high;
    if (f >= 27) return HeatRisk.moderate;
    return HeatRisk.low;
  }
}

/// Race-day weather for the start line (Dataran Merdeka) and a heat alert.
///
/// Fetches current conditions from Open-Meteo (no API key). Never throws:
/// offline, in tests, or on any error it keeps the typical KL dawn values
/// and flags them as [WeatherNow.estimated].
class WeatherService extends ChangeNotifier {
  WeatherService({this.client, bool autoFetch = true}) {
    if (autoFetch) refresh();
  }

  static const latitude = 3.1478;
  static const longitude = 101.6936;
  static const placeName = 'Dataran Merdeka';

  static final Uri endpoint = Uri.parse(
    'https://api.open-meteo.com/v1/forecast?latitude=$latitude&longitude=$longitude'
    '&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m'
    '&timezone=Asia%2FKuala_Lumpur',
  );

  /// Injected HTTP client (tests); null = a fresh client per request.
  final http.Client? client;
  WeatherNow _now = WeatherNow.typicalKlDawn();
  bool _loading = false;
  bool _disposed = false;
  DateTime? _fetchedAt;

  WeatherNow get now => _now;
  bool get loading => _loading;
  bool get estimated => _now.estimated;

  /// When the last live reading arrived (null = never).
  DateTime? get fetchedAt => _fetchedAt;

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _notify();
    try {
      final c = client ?? http.Client();
      try {
        final res = await c.get(endpoint).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final parsed = parse(res.body);
          if (parsed != null) {
            _now = parsed;
            _fetchedAt = DateTime.now();
          }
        }
      } finally {
        if (client == null) c.close();
      }
    } catch (_) {
      // Offline or blocked: keep the estimate.
    }
    _loading = false;
    _notify();
  }

  /// Parses an Open-Meteo `current` response. Returns null if it's malformed.
  static WeatherNow? parse(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map) return null;
      final c = json['current'];
      if (c is! Map) return null;
      double n(String k) => (c[k] as num).toDouble();
      final time = c['time'];
      return WeatherNow(
        temperatureC: n('temperature_2m'),
        humidityPct: n('relative_humidity_2m'),
        apparentC: n('apparent_temperature'),
        windKph: n('wind_speed_10m'),
        weatherCode: (c['weather_code'] as num).round(),
        observedAt: (time is String ? DateTime.tryParse(time) : null) ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
