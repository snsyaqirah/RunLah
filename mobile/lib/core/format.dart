import 'package:intl/intl.dart';

import 'l10n/i18n.dart';

enum Units { km, mi }

const double kMetresPerMile = 1609.344;

/// 5775 -> "1:36:15", 39 -> "0:39", 754 -> "12:34".
/// [forceHours] always shows the hour part ("0:12:34").
String fmtDuration(num? seconds, {bool forceHours = false, bool signed = false}) {
  if (seconds == null || seconds.isNaN || seconds.isInfinite) return '–';
  final neg = seconds < 0;
  final s = seconds.abs().round();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  final body = (h > 0 || forceHours)
      ? '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}'
      : '$m:${sec.toString().padLeft(2, '0')}';
  if (neg) return '−$body';
  return signed ? '+$body' : body;
}

/// Gap between two runners, e.g. "3 s", "1:05".
String fmtGap(num seconds) {
  final s = seconds.abs().round();
  if (s < 60) return '$s s';
  return fmtDuration(s);
}

/// Pace from seconds per km. Shows "/km" or "/mi" by [units].
String fmtPace(num? secPerKm, Units units, {bool withUnit = true}) {
  if (secPerKm == null || secPerKm <= 0 || secPerKm.isInfinite || secPerKm > 3600) return withUnit ? '–:–' : '–:–';
  final v = units == Units.km ? secPerKm : secPerKm * kMetresPerMile / 1000;
  final s = v.round();
  final body = '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  return withUnit ? '$body ${units == Units.km ? '/km' : '/mi'}' : body;
}

String paceUnit(Units units) => units == Units.km ? '/km' : '/mi';
String distUnit(Units units) => units == Units.km ? 'km' : 'mi';
String speedUnit(Units units) => units == Units.km ? 'km/h' : 'mph';

/// Speed from km/h, converted by [units], one decimal.
String fmtSpeed(num kph, Units units, {bool withUnit = true}) {
  final v = units == Units.km ? kph : kph * 1000 / kMetresPerMile;
  return withUnit ? '${v.toStringAsFixed(1)} ${speedUnit(units)}' : v.toStringAsFixed(1);
}

/// Distance in metres -> "14.2 km" / "8.8 mi".
String fmtDistance(num metres, Units units, {int decimals = 1, bool withUnit = true}) {
  final v = units == Units.km ? metres / 1000 : metres / kMetresPerMile;
  return withUnit ? '${v.toStringAsFixed(decimals)} ${distUnit(units)}' : v.toStringAsFixed(decimals);
}

final _int = NumberFormat.decimalPattern('en');

/// 11664 -> "11,664".
String fmtInt(num n) => _int.format(n);

/// 172 -> "172nd" in English, "ke-172" in BM.
String ordinal(int n) {
  if (I18n.instance.isMalay) return 'ke-${fmtInt(n)}';
  final mod100 = n % 100;
  final suffix = (mod100 >= 11 && mod100 <= 13)
      ? 'th'
      : switch (n % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return '${fmtInt(n)}$suffix';
}

/// Percent with one decimal, never rounding up to 100 unless it really is 100.
String fmtPct(double pct) {
  if (pct >= 100) return '100%';
  var r = (pct * 10).round() / 10;
  if (r >= 100) r = 99.9;
  return '${r.toStringAsFixed(1)}%';
}

/// Clock time of day, 24h ("04:45").
String fmtClock(DateTime t) => DateFormat('HH:mm').format(t);
String fmtClockSec(DateTime t) => DateFormat('HH:mm:ss').format(t);
String fmtDate(DateTime t) => DateFormat('d MMM yyyy').format(t);
