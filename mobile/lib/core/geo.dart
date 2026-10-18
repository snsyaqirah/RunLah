import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

const _earthR = 6371000.0;

/// Great-circle distance in metres.
double haversine(LatLng a, LatLng b) {
  final la1 = a.latitudeInRad, la2 = b.latitudeInRad;
  final dLa = la2 - la1;
  final dLo = b.longitudeInRad - a.longitudeInRad;
  final h = math.pow(math.sin(dLa / 2), 2) + math.cos(la1) * math.cos(la2) * math.pow(math.sin(dLo / 2), 2);
  return 2 * _earthR * math.asin(math.sqrt(h.toDouble()));
}

/// Bearing in degrees (0 = north, clockwise).
double bearing(LatLng a, LatLng b) {
  final la1 = a.latitudeInRad, la2 = b.latitudeInRad;
  final dLo = b.longitudeInRad - a.longitudeInRad;
  final y = math.sin(dLo) * math.cos(la2);
  final x = math.cos(la1) * math.sin(la2) - math.sin(la1) * math.cos(la2) * math.cos(dLo);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

LatLng lerpLatLng(LatLng a, LatLng b, double t) =>
    LatLng(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t);

/// A course polyline with distance-along-route helpers.
///
/// [nominalLength] is the official race distance (e.g. 21,097.5 m). The drawn
/// geometry is rarely exactly that long, so race distances are scaled onto
/// the geometry: `at(10000)` is always "the 10 km point" on the map.
class RoutePath {
  RoutePath(List<LatLng> points, {double? nominalLength}) : points = List.unmodifiable(points) {
    var acc = 0.0;
    final c = <double>[0];
    for (var i = 1; i < points.length; i++) {
      acc += haversine(points[i - 1], points[i]);
      c.add(acc);
    }
    cumulative = List.unmodifiable(c);
    geometryLength = acc;
    this.nominalLength = nominalLength ?? acc;
  }

  final List<LatLng> points;
  late final List<double> cumulative;
  late final double geometryLength;
  late final double nominalLength;

  double get _scale => geometryLength / nominalLength;

  /// Point at race distance [d] metres (clamped to the course).
  LatLng at(double d) {
    final g = (d * _scale).clamp(0.0, geometryLength);
    var lo = 0, hi = cumulative.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (cumulative[mid] <= g) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final seg = cumulative[hi] - cumulative[lo];
    final t = seg <= 0 ? 0.0 : (g - cumulative[lo]) / seg;
    return lerpLatLng(points[lo], points[hi], t);
  }

  /// Heading of the course at race distance [d].
  double headingAt(double d) {
    final a = at(math.max(0, d - 15));
    final b = at(math.min(nominalLength, d + 15));
    return bearing(a, b);
  }

  /// Snap a GPS fix to the course. Returns race distance and how far off
  /// the course the fix was, in metres. [hint] (last known distance) keeps
  /// the snap from jumping to a different lap of a looping course.
  ({double distance, double offCourse}) snap(LatLng p, {double? hint, double window = 1500}) {
    var best = double.infinity;
    var bestG = 0.0;
    final gHint = hint == null ? null : hint * _scale;
    for (var i = 1; i < points.length; i++) {
      if (gHint != null && (cumulative[i] < gHint - window || cumulative[i - 1] > gHint + window)) continue;
      final a = points[i - 1], b = points[i];
      // Project in a local flat frame (fine over a few hundred metres).
      final kx = math.cos(a.latitudeInRad) * 111320.0;
      const ky = 110540.0;
      final bx = (b.longitude - a.longitude) * kx, by = (b.latitude - a.latitude) * ky;
      final px = (p.longitude - a.longitude) * kx, py = (p.latitude - a.latitude) * ky;
      final len2 = bx * bx + by * by;
      final t = len2 == 0 ? 0.0 : ((px * bx + py * by) / len2).clamp(0.0, 1.0);
      final dx = px - bx * t, dy = py - by * t;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < best) {
        best = dist;
        bestG = cumulative[i - 1] + (cumulative[i] - cumulative[i - 1]) * t;
      }
    }
    return (distance: bestG / _scale, offCourse: best);
  }

  /// Sub-polyline between two race distances (for drawing "done so far").
  List<LatLng> slice(double from, double to, {double step = 40}) {
    final out = <LatLng>[];
    for (var d = from; d < to; d += step) {
      out.add(at(d));
    }
    out.add(at(to));
    return out;
  }

  /// Local metres (east, north) from the start, for 3D scenes.
  ({double x, double y}) toLocal(LatLng p) {
    final o = points.first;
    return (
      x: (p.longitude - o.longitude) * math.cos(o.latitudeInRad) * 111320.0,
      y: (p.latitude - o.latitude) * 110540.0,
    );
  }

  GeoBounds get bounds {
    var minLa = 90.0, maxLa = -90.0, minLo = 180.0, maxLo = -180.0;
    for (final p in points) {
      minLa = math.min(minLa, p.latitude);
      maxLa = math.max(maxLa, p.latitude);
      minLo = math.min(minLo, p.longitude);
      maxLo = math.max(maxLo, p.longitude);
    }
    return GeoBounds(LatLng(minLa, minLo), LatLng(maxLa, maxLo));
  }
}

/// Minimal bounds type so this file doesn't depend on flutter_map.
class GeoBounds {
  const GeoBounds(this.southWest, this.northEast);
  final LatLng southWest;
  final LatLng northEast;
  LatLng get center => LatLng((southWest.latitude + northEast.latitude) / 2, (southWest.longitude + northEast.longitude) / 2);
}
