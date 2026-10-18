import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models.dart';
import '../theme.dart';

/// A runner (or any point) drawn on the [CourseMap].
class MapDot {
  const MapDot({
    required this.point,
    required this.color,
    this.label,
    this.size = 18,
    this.estimated = false,
    this.pulse = false,
    this.icon,
    this.onTap,
  });
  final LatLng point;
  final Color color;
  final String? label;
  final double size;

  /// Hollow ring = position estimated between checkpoints, not live GPS.
  final bool estimated;

  /// Animated halo (used for "you").
  final bool pulse;
  final IconData? icon;
  final VoidCallback? onTap;
}

/// The course map used everywhere: event preview, live run, cheer map,
/// "Where were you", organizer console. Light/dark CARTO tiles over
/// OpenStreetMap, the route in green, checkpoints and landmarks on top.
class CourseMap extends StatefulWidget {
  const CourseMap({
    super.key,
    required this.race,
    this.dots = const [],
    this.extraPolylines = const [],
    this.extraLayers = const [],
    this.showCheckpoints = true,
    this.showLandmarks = true,
    this.doneUpTo,
    this.controller,
    this.interactive = true,
    this.padding = const EdgeInsets.all(28),
    this.onTap,
  });

  final Race race;
  final List<MapDot> dots;
  final List<Polyline> extraPolylines;

  /// Extra flutter_map layers drawn above the route and below the dots.
  final List<Widget> extraLayers;
  final bool showCheckpoints;
  final bool showLandmarks;

  /// Highlight the course from the start up to this race distance (metres).
  final double? doneUpTo;
  final MapController? controller;
  final bool interactive;
  final EdgeInsets padding;
  final void Function(LatLng)? onTap;

  static const routeGreen = Color(0xFF3BA55C);

  @override
  State<CourseMap> createState() => _CourseMapState();
}

class _CourseMapState extends State<CourseMap> {
  // One tile provider (and HTTP client) per map, not per rebuild.
  // TileLayer disposes it when the map goes away.
  final _tiles = NetworkTileProvider();

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final race = w.race, dots = w.dots, extraPolylines = w.extraPolylines, extraLayers = w.extraLayers;
    final showCheckpoints = w.showCheckpoints, showLandmarks = w.showLandmarks, doneUpTo = w.doneUpTo;
    final controller = w.controller, interactive = w.interactive, padding = w.padding, onTap = w.onTap;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final route = race.route;
    final b = route.bounds;
    return ClipRRect(
      borderRadius: BorderRadius.circular(RL.radius),
      child: FlutterMap(
        mapController: controller,
        options: MapOptions(
          initialCameraFit: CameraFit.bounds(
            bounds: LatLngBounds(b.southWest, b.northEast),
            padding: padding,
          ),
          backgroundColor: dark ? const Color(0xFF1B2333) : const Color(0xFFE9EEF3),
          interactionOptions: InteractionOptions(
            flags: interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none,
          ),
          onTap: onTap == null ? null : (_, p) => onTap(p),
        ),
        children: [
          TileLayer(
            urlTemplate: dark
                ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
            subdomains: const ['a', 'b', 'c', 'd'],
            userAgentPackageName: 'com.runlah.runlah',
            tileProvider: _tiles,
            retinaMode: RetinaMode.isHighDensity(context),
          ),
          PolylineLayer(
            polylines: [
              Polyline(
                points: route.points,
                strokeWidth: 6,
                color: CourseMap.routeGreen.withValues(alpha: doneUpTo == null ? 0.9 : 0.45),
                borderColor: Colors.white.withValues(alpha: dark ? 0.15 : 0.8),
                borderStrokeWidth: 2,
              ),
              if (doneUpTo != null && doneUpTo > 0)
                Polyline(points: route.slice(0, doneUpTo), strokeWidth: 6, color: RL.amber),
              ...extraPolylines,
            ],
          ),
          ...extraLayers,
          if (showLandmarks)
            MarkerLayer(
              markers: [
                for (final l in race.landmarks)
                  if (l.kind != 'park')
                    Marker(
                      point: l.location,
                      width: 120,
                      height: 30,
                      child: IgnorePointer(child: _LandmarkLabel(l, dark: dark)),
                    ),
              ],
            ),
          if (showCheckpoints)
            MarkerLayer(
              markers: [
                for (final c in race.checkpoints.skip(1))
                  Marker(
                    point: c.location,
                    width: 30,
                    height: 30,
                    child: _CheckpointPin(c),
                  ),
                Marker(point: race.start.location, width: 34, height: 34, child: const _StartPin()),
              ],
            ),
          MarkerLayer(
            markers: [
              for (final d in dots)
                Marker(
                  point: d.point,
                  width: d.label == null ? d.size + 16 : 140,
                  height: d.size + 16 + (d.label == null ? 0 : 40),
                  child: _DotWidget(d),
                ),
            ],
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Container(
              margin: const EdgeInsets.all(6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: (dark ? Colors.black : Colors.white).withValues(alpha: 0.7), borderRadius: BorderRadius.circular(4)),
              child: Text('© OpenStreetMap · © CARTO', style: TextStyle(fontSize: 9, color: dark ? Colors.white70 : RL.slate)),
            ),
          ),
        ],
      ),
    );
  }
}

class _StartPin extends StatelessWidget {
  const _StartPin();
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: RL.navy, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5)),
        child: const Icon(Icons.flag_rounded, color: Colors.white, size: 16),
      );
}

class _CheckpointPin extends StatelessWidget {
  const _CheckpointPin(this.c);
  final Checkpoint c;
  @override
  Widget build(BuildContext context) {
    final finish = c.type == CheckpointType.finish;
    return Tooltip(
      message: '${c.shortLabel} · ${c.name}',
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: finish ? RL.amber : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: finish ? Colors.white : CourseMap.routeGreen, width: 2.5),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4)],
        ),
        child: finish
            ? const Icon(Icons.sports_score_rounded, size: 15, color: Colors.white)
            : Text('${c.index}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: RL.navy)),
      ),
    );
  }
}

class _LandmarkLabel extends StatelessWidget {
  const _LandmarkLabel(this.l, {required this.dark});
  final Landmark l;
  final bool dark;
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: (dark ? const Color(0xFF111827) : Colors.white).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(l.kind == 'mosque' ? Icons.mosque_rounded : Icons.location_city_rounded, size: 11, color: dark ? Colors.white70 : RL.slate),
              const SizedBox(width: 3),
              Flexible(
                child: Text(l.name, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: dark ? Colors.white70 : RL.slate)),
              ),
            ],
          ),
        ),
      );
}

class _DotWidget extends StatefulWidget {
  const _DotWidget(this.d);
  final MapDot d;
  @override
  State<_DotWidget> createState() => _DotWidgetState();
}

class _DotWidgetState extends State<_DotWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.d.pulse) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _DotWidget old) {
    super.didUpdateWidget(old);
    if (widget.d.pulse && !_c.isAnimating) _c.repeat();
    if (!widget.d.pulse && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final dot = SizedBox(
      width: d.size + 16,
      height: d.size + 16,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (d.pulse)
            AnimatedBuilder(
              animation: _c,
              builder: (_, _) => Container(
                width: d.size + 16 * _c.value,
                height: d.size + 16 * _c.value,
                decoration: BoxDecoration(shape: BoxShape.circle, color: d.color.withValues(alpha: 0.35 * (1 - _c.value))),
              ),
            ),
          Container(
            width: d.size,
            height: d.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: d.estimated ? Colors.white : d.color,
              border: Border.all(color: d.estimated ? d.color : Colors.white, width: d.estimated ? 3 : 2.5),
              boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 5, offset: Offset(0, 1))],
            ),
            child: d.icon == null ? null : Icon(d.icon, size: d.size * 0.6, color: d.estimated ? d.color : Colors.white),
          ),
        ],
      ),
    );
    return GestureDetector(
      onTap: d.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (d.label != null)
            Container(
              height: 20,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(color: d.color, borderRadius: BorderRadius.circular(8)),
              child: Text(d.label!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          dot,
          // Same height below as the label above keeps the dot centred on its point.
          if (d.label != null) const SizedBox(height: 20),
        ],
      ),
    );
  }
}
