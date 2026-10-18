import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/map_tiles.dart';
import '../../data/activity_store.dart';
import '../../data/models.dart';
import '../../services/voice_service.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Navy gradient card used for the big live numbers.
class HeroPanel extends StatelessWidget {
  const HeroPanel({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 18), this.colors});
  final Widget child;
  final EdgeInsets padding;
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(RL.radius + 4),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors ?? const [Color(0xFF1B2B4F), RL.navy, Color(0xFF0E1830)],
        ),
        boxShadow: [BoxShadow(color: RL.navy.withValues(alpha: 0.28), blurRadius: 22, offset: const Offset(0, 10))],
      ),
      child: DefaultTextStyle.merge(style: const TextStyle(color: Colors.white), child: child),
    );
  }
}

/// A big tabular number with a caption, scaled down to fit narrow screens.
class Metric extends StatelessWidget {
  const Metric({
    super.key,
    required this.value,
    required this.label,
    this.size = 26,
    this.color,
    this.labelColor,
    this.align = CrossAxisAlignment.start,
    this.unit,
  });
  final String value;
  final String label;
  final double size;
  final Color? color;
  final Color? labelColor;
  final CrossAxisAlignment align;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final c = color ?? ink(context);
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: align == CrossAxisAlignment.center ? Alignment.center : (align == CrossAxisAlignment.end ? Alignment.centerRight : Alignment.centerLeft),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: value),
              if (unit != null) TextSpan(text: ' $unit', style: TextStyle(fontSize: size * 0.45, fontWeight: FontWeight.w700, color: c.withValues(alpha: 0.7))),
            ]),
            maxLines: 1,
            style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, height: 1.05, color: c, fontFeatures: _tabular, letterSpacing: -0.5),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: labelColor ?? muted(context), letterSpacing: 0.2),
        ),
      ],
    );
  }
}

/// Counts up to [value] whenever it changes ("You've passed 1,094 runners").
class CountUpText extends StatelessWidget {
  const CountUpText(this.value, {super.key, required this.style, this.format, this.duration = const Duration(milliseconds: 900)});
  final num value;
  final TextStyle style;
  final String Function(num v)? format;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text(
        format?.call(v) ?? fmtInt(v.round()),
        maxLines: 1,
        style: style.copyWith(fontFeatures: _tabular),
      ),
    );
  }
}

/// Fades and slides its child in, [index] × 60 ms after first build.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    final total = 380 + index * 60;
    final start = (index * 60) / total;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      builder: (_, v, child) {
        final p = Curves.easeOutCubic.transform(((v - start) / (1 - start)).clamp(0.0, 1.0));
        return Opacity(opacity: p, child: Transform.translate(offset: Offset(0, 18 * (1 - p)), child: child));
      },
      child: child,
    );
  }
}

/// Two-option segmented switch with a sliding amber thumb.
class SegmentSwitch extends StatelessWidget {
  const SegmentSwitch({super.key, required this.index, required this.labels, required this.icons, required this.onChanged, this.badges = const {}});
  final int index;
  final List<String> labels;
  final List<IconData> icons;
  final ValueChanged<int> onChanged;

  /// Small dot on a segment (e.g. a free run in progress).
  final Set<int> badges;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dark ? const Color(0xFF1F2937) : RL.line),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment(index == 0 ? -1 : 1, 0),
            child: FractionallySizedBox(
              widthFactor: 1 / labels.length,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: RL.navy,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: RL.navy.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3))],
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == index,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onChanged(i),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icons[i], size: 18, color: i == index ? RL.amber : muted(context)),
                                const SizedBox(width: 6),
                                AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 200),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: i == index ? Colors.white : muted(context),
                                  ),
                                  child: Text(labels[i]),
                                ),
                                if (badges.contains(i)) ...[
                                  const SizedBox(width: 6),
                                  Container(width: 7, height: 7, decoration: const BoxDecoration(color: RL.green, shape: BoxShape.circle)),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Live indicator dot that breathes (respects TickerMode).
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, this.color = RL.green, this.size = 8});
  final Color color;
  final double size;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 2.2,
      height: s * 2.2,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: s + s * 1.2 * _c.value,
              height: s + s * 1.2 * _c.value,
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.4 * (1 - _c.value))),
            ),
            Container(width: s, height: s, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
          ],
        ),
      ),
    );
  }
}

/// Horizontal bars, one per completed kilometre. Fastest in amber.
class KmSplitsList extends StatelessWidget {
  const KmSplitsList({super.key, required this.splitsS, required this.units, this.maxRows});
  final List<double> splitsS;
  final Units units;
  final int? maxRows;

  @override
  Widget build(BuildContext context) {
    if (splitsS.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(tr('Your first kilometre split shows up here.'), style: TextStyle(color: muted(context))),
      );
    }
    final fastest = splitsS.reduce(math.min);
    final slowest = splitsS.reduce(math.max);
    final rows = maxRows == null || splitsS.length <= maxRows! ? splitsS.length : maxRows!;
    final startIndex = splitsS.length - rows;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        for (var i = startIndex; i < splitsS.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w800, color: muted(context), fontFeatures: _tabular)),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      // Faster = longer bar. Scale between 45% and 100%.
                      final span = slowest - fastest;
                      final f = span < 1 ? 1.0 : 1 - (splitsS[i] - fastest) / span * 0.55;
                      final best = splitsS[i] == fastest;
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: f),
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, _) => Container(
                            height: 14,
                            width: c.maxWidth * v,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(7),
                              gradient: LinearGradient(
                                colors: best
                                    ? const [Color(0xFFF5B342), RL.amber]
                                    : [RL.teal.withValues(alpha: dark ? 0.55 : 0.35), RL.teal.withValues(alpha: dark ? 0.8 : 0.6)],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 64,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      fmtPace(splitsS[i], Units.km, withUnit: false),
                      style: TextStyle(fontWeight: FontWeight.w800, color: splitsS[i] == fastest ? RL.amber : ink(context), fontFeatures: _tabular),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (startIndex > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(tr('+ {n} earlier kilometres', {'n': startIndex}), style: TextStyle(fontSize: 12, color: muted(context))),
          ),
      ],
    );
  }
}

/// Pace along the run (fl_chart). Faster is drawn higher.
class PaceChart extends StatelessWidget {
  const PaceChart({super.key, required this.series, required this.units, this.height = 180});
  final List<({double d, double pace})> series;
  final Units units;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (series.length < 3) {
      return SizedBox(height: 60, child: Center(child: Text(tr('Not enough data for a pace chart yet.'), style: TextStyle(color: muted(context)))));
    }
    final paces = [for (final s in series) s.pace];
    final minP = paces.reduce(math.min), maxP = paces.reduce(math.max);
    final pad = math.max(10.0, (maxP - minP) * 0.2);
    final avg = paces.reduce((a, b) => a + b) / paces.length;
    final maxKm = series.last.d / 1000;
    final grid = Theme.of(context).brightness == Brightness.dark ? Colors.white12 : RL.line;
    String kmLabel(double v) => units == Units.km ? v.toStringAsFixed(0) : (v * 1000 / kMetresPerMile).toStringAsFixed(1);
    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxKm,
          minY: -(maxP + pad),
          maxY: -(minP - pad),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: math.max(5, ((maxP - minP + 2 * pad) / 4).roundToDouble()),
            getDrawingHorizontalLine: (_) => FlLine(color: grid, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: math.max(5, ((maxP - minP + 2 * pad) / 3).roundToDouble()),
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(fmtPace(-v, units, withUnit: false), style: TextStyle(fontSize: 10, color: muted(context))),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: math.max(1, (maxKm / 5).ceilToDouble()),
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(kmLabel(v), style: TextStyle(fontSize: 10, color: muted(context))),
                ),
              ),
            ),
          ),
          extraLinesData: ExtraLinesData(horizontalLines: [
            HorizontalLine(y: -avg, color: RL.amber.withValues(alpha: 0.7), strokeWidth: 1.5, dashArray: [6, 4]),
          ]),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => RL.navy,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${fmtPace(-s.y, units)}\n${fmtDistance(s.x * 1000, units, decimals: 2)}',
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (final s in series) FlSpot(s.d / 1000, -s.pace)],
              isCurved: true,
              curveSmoothness: 0.25,
              preventCurveOverShooting: true,
              color: RL.teal,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [RL.teal.withValues(alpha: 0.28), RL.teal.withValues(alpha: 0.0)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Map of your own GPS track (same tiles as [CourseMap]).
class TrackMap extends StatefulWidget {
  const TrackMap({super.key, required this.points, this.follow = false, this.interactive = false, this.live = false, this.fallbackCenter});
  final List<LatLng> points;

  /// Keep the camera on the latest point.
  final bool follow;
  final bool interactive;

  /// Current position pulses.
  final bool live;
  final LatLng? fallbackCenter;

  @override
  State<TrackMap> createState() => _TrackMapState();
}

class _TrackMapState extends State<TrackMap> {
  final _ctrl = MapController();
  bool _ready = false;

  @override
  void didUpdateWidget(covariant TrackMap old) {
    super.didUpdateWidget(old);
    if (widget.follow && _ready && widget.points.isNotEmpty) {
      final last = widget.points.last;
      if (old.points.isEmpty || old.points.last != last) {
        try {
          _ctrl.move(last, _ctrl.camera.zoom);
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pts = _thin(widget.points);
    final center = widget.points.isNotEmpty ? widget.points.last : (widget.fallbackCenter ?? DemoTracks.klccPark.points.first);
    final fit = !widget.follow && pts.length >= 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(RL.radius),
      child: FlutterMap(
        mapController: _ctrl,
        options: MapOptions(
          initialCenter: center,
          initialZoom: 16,
          initialCameraFit: fit ? CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(36), maxZoom: 17) : null,
          backgroundColor: dark ? const Color(0xFF1B2333) : const Color(0xFFE9EEF3),
          interactionOptions: InteractionOptions(flags: widget.interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none),
          onMapReady: () => _ready = true,
        ),
        children: [
          runlahTileLayer(context),
          if (pts.length >= 2)
            PolylineLayer(polylines: [
              Polyline(
                points: pts,
                strokeWidth: 5,
                color: RL.amber,
                borderColor: Colors.white.withValues(alpha: dark ? 0.2 : 0.9),
                borderStrokeWidth: 2,
              ),
            ]),
          MarkerLayer(markers: [
            if (widget.points.length >= 2 && !widget.live)
              Marker(point: widget.points.first, width: 22, height: 22, child: const _Pin(color: RL.green, icon: Icons.play_arrow_rounded)),
            if (widget.points.isNotEmpty)
              Marker(
                point: widget.points.last,
                width: 44,
                height: 44,
                child: widget.live ? const _YouDot() : const _Pin(color: RL.navy, icon: Icons.sports_score_rounded),
              ),
          ]),
          Align(
            alignment: Alignment.bottomRight,
            child: Container(
              margin: const EdgeInsets.all(6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: (dark ? Colors.black : Colors.white).withValues(alpha: 0.7), borderRadius: BorderRadius.circular(4)),
              child: Text(mapAttribution, style: TextStyle(fontSize: 9, color: dark ? Colors.white70 : RL.slate)),
            ),
          ),
        ],
      ),
    );
  }

  static List<LatLng> _thin(List<LatLng> pts) {
    if (pts.length <= 1200) return pts;
    final step = (pts.length / 1200).ceil();
    return [for (var i = 0; i < pts.length; i += step) pts[i], pts.last];
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.color, required this.icon});
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 4)],
          ),
          child: Icon(icon, size: 12, color: Colors.white),
        ),
      );
}

class _YouDot extends StatefulWidget {
  const _YouDot();
  @override
  State<_YouDot> createState() => _YouDotState();
}

class _YouDotState extends State<_YouDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 18 + 26 * _c.value,
              height: 18 + 26 * _c.value,
              decoration: BoxDecoration(shape: BoxShape.circle, color: RL.amber.withValues(alpha: 0.35 * (1 - _c.value))),
            ),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: RL.amber,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [BoxShadow(color: Color(0x50000000), blurRadius: 6)],
              ),
            ),
          ],
        ),
      );
}

/// Small route thumbnail for history rows.
class RouteThumb extends StatelessWidget {
  const RouteThumb({super.key, required this.points, this.size = 56});
  final List<TrackPoint> points;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1B2333) : RL.amberSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: CustomPaint(painter: _ThumbPainter(points, dark)),
    );
  }
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.points, this.dark);
  final List<TrackPoint> points;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) {
      final p = Paint()..color = RL.amber;
      canvas.drawCircle(size.center(Offset.zero), 5, p);
      return;
    }
    var minLa = 90.0, maxLa = -90.0, minLo = 180.0, maxLo = -180.0;
    for (final p in points) {
      minLa = math.min(minLa, p.lat);
      maxLa = math.max(maxLa, p.lat);
      minLo = math.min(minLo, p.lng);
      maxLo = math.max(maxLo, p.lng);
    }
    final kx = math.cos(minLa * math.pi / 180);
    final w = math.max(1e-9, (maxLo - minLo) * kx), h = math.max(1e-9, maxLa - minLa);
    final scale = (size.shortestSide - 14) / math.max(w, h);
    final ox = (size.width - w * scale) / 2, oy = (size.height - h * scale) / 2;
    Offset at(TrackPoint p) => Offset(ox + (p.lng - minLo) * kx * scale, oy + (maxLa - p.lat) * scale);
    final path = Path()..moveTo(at(points.first).dx, at(points.first).dy);
    final step = math.max(1, points.length ~/ 200);
    for (var i = step; i < points.length; i += step) {
      final o = at(points[i]);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = RL.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(at(points.last), 3.2, Paint()..color = dark ? Colors.white : RL.navy);
  }

  @override
  bool shouldRepaint(covariant _ThumbPainter old) => old.points.length != points.length;
}

/// Share link card: URL, QR, copy and system share sheet (PRD F08).
class ShareLinkCard extends StatelessWidget {
  const ShareLinkCard({super.key, required this.url, required this.privacy, this.onPrivacy, this.message});
  final String url;
  final Privacy privacy;
  final ValueChanged<Privacy>? onPrivacy;
  final String? message;

  Future<void> _share(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(ShareParams(
        text: '${message ?? tr('Follow my run live on RunLah')}\n$url',
        subject: tr('Follow my run live on RunLah'),
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('Link copied'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final off = privacy == Privacy.off;
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(tr('Live share link'), trailing: PrivacyChip(privacy: privacy)),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: off ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: RL.line)),
                  child: QrImageView(
                    data: url,
                    size: 92,
                    padding: const EdgeInsets.all(4),
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: RL.navy),
                    dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: RL.navy),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        privacy == Privacy.public ? tr('Anyone can follow you. Family can scan the code or open the link.') : tr('Only people with this link can follow you live.'),
                        style: TextStyle(fontSize: 12.5, color: muted(context)),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        url.replaceFirst('https://', ''),
                        maxLines: 2,
                        style: TextStyle(fontWeight: FontWeight.w800, color: ink(context), fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            secondChild: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(tr('Live sharing is off. Nobody can see your position; the organizer still gets your checkpoint times.'), style: TextStyle(color: muted(context))),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: off
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: url));
                          if (context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('Link copied'))));
                        },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('Copy'))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: off ? (onPrivacy == null ? null : () => onPrivacy!(Privacy.linkOnly)) : () => _share(context),
                  icon: Icon(off ? Icons.link_rounded : Icons.ios_share_rounded, size: 18),
                  label: FittedBox(fit: BoxFit.scaleDown, child: Text(off ? tr('Turn on') : tr('Share'))),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Public / Link only / Off as a small pill.
class PrivacyChip extends StatelessWidget {
  const PrivacyChip({super.key, required this.privacy});
  final Privacy privacy;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = privacyStyle(privacy);
    return Pill(label, icon: icon, color: color);
  }
}

(String, IconData, Color) privacyStyle(Privacy p) => switch (p) {
      Privacy.public => (tr('Public'), Icons.public_rounded, RL.green),
      Privacy.linkOnly => (tr('Link only'), Icons.link_rounded, RL.teal),
      Privacy.off => (tr('Off'), Icons.visibility_off_rounded, RL.slate),
    };

/// Three-way privacy picker (PRD F10).
class PrivacySelector extends StatelessWidget {
  const PrivacySelector({super.key, required this.value, required this.onChanged});
  final Privacy value;
  final ValueChanged<Privacy> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final p in Privacy.values) ...[
              Expanded(
                child: Builder(builder: (context) {
                  final (label, icon, color) = privacyStyle(p);
                  final on = p == value;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    height: 64,
                    decoration: BoxDecoration(
                      color: on ? color.withValues(alpha: dark ? 0.22 : 0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: on ? color : (dark ? const Color(0xFF374151) : RL.line), width: on ? 2 : 1.2),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => onChanged(p),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(icon, size: 20, color: on ? color : muted(context)),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: on ? ink(context) : muted(context))),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
              if (p != Privacy.values.last) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            switch (value) {
              Privacy.public => tr('Anyone can find you and follow your run live.'),
              Privacy.linkOnly => tr('Only people with your share link can follow you live.'),
              Privacy.off => tr('Nobody sees you live. The organizer still gets checkpoint times.'),
            },
            key: ValueKey(value),
            style: TextStyle(fontSize: 12.5, color: muted(context)),
          ),
        ),
      ],
    );
  }
}

/// Toggle row used in the settings cards (wraps cleanly at 360 px).
class ToggleRow extends StatelessWidget {
  const ToggleRow({super.key, required this.icon, required this.title, required this.subtitle, required this.value, required this.onChanged, this.color = RL.amber});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: ink(context))),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: muted(context))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(value: value, onChanged: onChanged, activeTrackColor: RL.amber),
          ],
        ),
      ),
    );
  }
}

/// Caption strip showing what the voice coach just said (fades after 6 s).
class VoiceCaption extends StatefulWidget {
  const VoiceCaption({super.key, required this.voice});
  final VoiceService voice;

  @override
  State<VoiceCaption> createState() => _VoiceCaptionState();
}

class _VoiceCaptionState extends State<VoiceCaption> {
  VoiceLine? _shown;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    widget.voice.lastLine.addListener(_onLine);
  }

  void _onLine() {
    final l = widget.voice.lastLine.value;
    if (l == null || !mounted) return;
    _hide?.cancel();
    setState(() => _shown = l);
    _hide = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _shown = null);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    widget.voice.lastLine.removeListener(_onLine);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = _shown;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(position: Tween(begin: const Offset(0, -0.4), end: Offset.zero).animate(a), child: child),
      ),
      child: l == null
          ? const SizedBox.shrink()
          : Container(
              key: ValueKey(l.at),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: RL.navy.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
              ),
              child: Row(
                children: [
                  const Icon(Icons.record_voice_over_rounded, color: RL.amber, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Icon tile + title + subtitle row used across the run cards.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.icon, required this.title, this.subtitle, this.color = RL.teal, this.trailing});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: ink(context))),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: TextStyle(fontSize: 12.5, color: muted(context))),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}
