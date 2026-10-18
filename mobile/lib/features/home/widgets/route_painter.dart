import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../core/geo.dart';

/// A pin drawn on a [RouteSilhouette].
class RoutePin {
  const RoutePin(this.point, this.color, {this.radius = 6, this.halo = false});
  final LatLng point;
  final Color color;
  final double radius;
  final bool halo;
}

/// The course drawn as a clean line, scaled to fit. Works offline and costs
/// nothing to paint, so it's used for hero art, event covers and the SOS
/// mini-maps (the full [CourseMap] is used where interaction matters).
class RouteSilhouette extends StatelessWidget {
  const RouteSilhouette({
    super.key,
    required this.route,
    this.color = Colors.white,
    this.strokeWidth = 3,
    this.progress,
    this.progressColor = const Color(0xFFE8930C),
    this.pins = const [],
    this.glow = false,
    this.padding = 8,
  });

  final RoutePath route;
  final Color color;
  final double strokeWidth;

  /// Race distance (metres) drawn in [progressColor] from the start.
  final double? progress;
  final Color progressColor;
  final List<RoutePin> pins;
  final bool glow;
  final double padding;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _RoutePainter(this),
        size: Size.infinite,
      );
}

class _RoutePainter extends CustomPainter {
  _RoutePainter(this.w);
  final RouteSilhouette w;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = w.route.points;
    if (pts.length < 2 || size.isEmpty) return;
    final b = w.route.bounds;
    final k = math.cos(b.center.latitudeInRad);
    final spanX = (b.northEast.longitude - b.southWest.longitude) * k;
    final spanY = b.northEast.latitude - b.southWest.latitude;
    final avail = Size(size.width - w.padding * 2, size.height - w.padding * 2);
    if (avail.width <= 0 || avail.height <= 0 || spanX <= 0 || spanY <= 0) return;
    final s = math.min(avail.width / spanX, avail.height / spanY);
    final ox = w.padding + (avail.width - spanX * s) / 2;
    final oy = w.padding + (avail.height - spanY * s) / 2;
    Offset map(LatLng p) => Offset(ox + (p.longitude - b.southWest.longitude) * k * s, oy + (b.northEast.latitude - p.latitude) * s);

    Path pathOf(List<LatLng> list) {
      final path = Path()..moveTo(map(list.first).dx, map(list.first).dy);
      for (final p in list.skip(1)) {
        final o = map(p);
        path.lineTo(o.dx, o.dy);
      }
      return path;
    }

    final full = pathOf(pts);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = w.strokeWidth
      ..color = w.color;
    if (w.glow) {
      canvas.drawPath(
        full,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w.strokeWidth * 3
          ..strokeJoin = StrokeJoin.round
          ..color = w.color.withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawPath(full, stroke);

    final prog = w.progress;
    if (prog != null && prog > 0) {
      final done = pathOf(w.route.slice(0, math.min(prog, w.route.nominalLength), step: 120));
      canvas.drawPath(done, stroke..color = w.progressColor..strokeWidth = w.strokeWidth * 1.15);
    }

    // Start / finish marker.
    final start = map(pts.first);
    canvas.drawCircle(start, w.strokeWidth * 1.6, Paint()..color = w.color);
    canvas.drawCircle(start, w.strokeWidth * 0.8, Paint()..color = w.progressColor);

    for (final pin in w.pins) {
      final o = map(pin.point);
      if (pin.halo) canvas.drawCircle(o, pin.radius * 2.4, Paint()..color = pin.color.withValues(alpha: 0.22));
      canvas.drawCircle(o, pin.radius + 2, Paint()..color = Colors.white);
      canvas.drawCircle(o, pin.radius, Paint()..color = pin.color);
    }
  }

  @override
  bool shouldRepaint(_RoutePainter old) =>
      old.w.progress != w.progress || old.w.pins != w.pins || old.w.color != w.color || old.w.route != w.route;
}
