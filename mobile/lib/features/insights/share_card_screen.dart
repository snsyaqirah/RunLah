import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/insights/insights_engine.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import 'common.dart';

enum CardFormat { story, square }

enum CardStyle { night, sunrise, minimal }

enum CardHighlight { top, passed, quarter, category }

/// Everything a share card shows, resolved for the current snapshot.
class ShareCardData {
  ShareCardData({
    required this.name,
    required this.bib,
    required this.category,
    required this.event,
    required this.race,
    required this.date,
    required this.phase,
    required this.official,
    required this.link,
    required this.route,
    required this.units,
    this.timeS,
    this.place,
    this.of,
    this.topPct,
    this.distanceM,
    this.highlights = const {},
  });

  final String name, bib, category, event, race, date, link;
  final Phase phase;
  final bool official;
  final RoutePath route;
  final Units units;
  final double? timeS;
  final int? place, of;
  final double? topPct;

  /// Distance covered, for runners who haven't finished.
  final double? distanceM;
  final Map<CardHighlight, ({String value, String label, IconData icon})> highlights;

  bool get finished => phase == Phase.finished;

  static ShareCardData build(BuildContext context, InsightsSnapshot s, RaceSim sim, int pid, Units units) {
    final p = sim.participant(pid);
    final phase = phaseOf(sim, s, pid);
    final cat = categoryName(s.race, p);
    final raceLabel = '${tr(s.race.name)} · ${fmtDistance(s.race.distanceM, units)}';
    final hl = <CardHighlight, ({String value, String label, IconData icon})>{};
    ResultRow? r;
    if (phase == Phase.finished) {
      r = s.result(pid);
      final o = r.overall!;
      hl[CardHighlight.top] = (
        value: o.place == 1 ? tr('Winner') : tr('Top {pct}', {'pct': fmtPct(o.topPct)}),
        label: tr('of {n} finishers', {'n': fmtInt(o.of)}),
        icon: Icons.emoji_events_rounded,
      );
      final halves = s.sections(pid, SectionSet.halves);
      final passed = halves.fold<int>(0, (a, h) => a + h.passed);
      if (passed > 0) hl[CardHighlight.passed] = (value: fmtInt(passed), label: tr('runners passed on the road'), icon: Icons.trending_up_rounded);
      final quarters = s.sections(pid, SectionSet.quarters);
      if (quarters.length == 4) {
        var best = 0;
        for (var i = 1; i < 4; i++) {
          if (quarters[i].speedKph > quarters[best].speedKph) best = i;
        }
        hl[CardHighlight.quarter] = (value: fmtSpeed(quarters[best].speedKph, units), label: tr('fastest quarter (Q{n})', {'n': best + 1}), icon: Icons.bolt_rounded);
      }
      hl[CardHighlight.category] = (value: ordinal(r.category!.place), label: tr('in {cat} of {n}', {'cat': cat, 'n': fmtInt(r.category!.of)}), icon: Icons.military_tech_rounded);
    }
    return ShareCardData(
      name: nameOf(context, p),
      bib: p.bib,
      category: cat,
      event: sim.event.name,
      race: raceLabel,
      date: fmtDate(sim.event.date),
      phase: phase,
      official: s.official,
      link: deepLink(p),
      route: s.race.route,
      units: units,
      timeS: r?.netS,
      place: r?.overall?.place,
      of: r?.overall?.of,
      topPct: r?.overall?.topPct,
      distanceM: phase == Phase.finished
          ? s.race.distanceM
          : (p.hasGps ? sim.distanceAt(pid, s.asOf) : s.estimatedDistanceAt(pid, s.asOf)),
      highlights: hl,
    );
  }
}

/// F26 share card: 9:16 story or 1:1 square, three styles, one highlight,
/// exported as a PNG (1080 px wide) through the share sheet.
class ShareCardScreen extends StatefulWidget {
  const ShareCardScreen({super.key, required this.participantId});
  final int participantId;

  @override
  State<ShareCardScreen> createState() => _ShareCardScreenState();
}

class _ShareCardScreenState extends State<ShareCardScreen> {
  final _boundary = GlobalKey();
  CardFormat _format = CardFormat.story;
  CardStyle _style = CardStyle.night;
  CardHighlight? _highlight;
  bool _busy = false;

  Future<void> _share(BuildContext buttonContext, ShareCardData data) async {
    final origin = originOf(buttonContext);
    setState(() => _busy = true);
    try {
      final bytes = await capturePng(_boundary, pixelRatio: 1080 / ShareCard.width);
      if (bytes == null) throw StateError('no image');
      final text = data.finished
          ? tr('{name} finished the {race} in {time}. Full Race Insights: {link}', {'name': data.name, 'race': data.event, 'time': fmtDuration(data.timeS), 'link': 'https://${data.link}'})
          : tr('Follow {name} live at {race}: {link}', {'name': data.name, 'race': data.event, 'link': 'https://${data.link}'});
      final ok = await sharePng(bytes, fileName: 'runlah-${data.bib}-${_format.name}.png', text: text, origin: origin);
      if (!mounted) return;
      if (!ok) showSnack(context, tr('Sharing isn\'t available on this device. Try the link instead.'));
      if (ok && kIsWeb) showSnack(context, tr('Image ready. If no share sheet opened, it was downloaded.'));
    } catch (_) {
      if (mounted) showSnack(context, tr('Couldn\'t create the image. Please try again.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<InsightsController>().snapshot;
    final sim = context.watch<RaceSim>();
    final units = context.watch<SettingsController>().units;
    final data = ShareCardData.build(context, s, sim, widget.participantId, units);
    final keys = data.highlights.keys.toList();
    final hl = keys.contains(_highlight) ? _highlight : (keys.isEmpty ? null : keys.first);
    final size = ShareCard.sizeOf(_format);
    final previewH = _format == CardFormat.story ? 470.0 : 330.0;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Share card'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            height: previewH,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 10))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: FittedBox(
                    child: RepaintBoundary(
                      key: _boundary,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        child: SizedBox(
                          key: ValueKey('$_format$_style$hl'),
                          width: size.width,
                          height: size.height,
                          child: ShareCard(data: data, format: _format, style: _style, highlight: hl),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SectionLabel(tr('Format')),
          SegToggle<CardFormat>(
            value: _format,
            options: [(CardFormat.story, tr('Story 9:16')), (CardFormat.square, tr('Square 1:1'))],
            onChanged: (f) => setState(() => _format = f),
          ),
          const SizedBox(height: 18),
          SectionLabel(tr('Style')),
          Row(
            children: [
              for (final st in CardStyle.values) ...[
                if (st != CardStyle.night) const SizedBox(width: 10),
                Expanded(child: _StyleSwatch(style: st, selected: st == _style, onTap: () => setState(() => _style = st))),
              ],
            ],
          ),
          if (keys.isNotEmpty) ...[
            const SizedBox(height: 18),
            SectionLabel(tr('Highlight')),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in keys)
                  ChoiceChip(
                    avatar: Icon(data.highlights[k]!.icon, size: 16, color: k == hl ? Colors.white : RL.amber),
                    label: Text(switch (k) {
                      CardHighlight.top => tr('Top %'),
                      CardHighlight.passed => tr('Runners passed'),
                      CardHighlight.quarter => tr('Fastest quarter'),
                      CardHighlight.category => tr('Category place'),
                    }),
                    selected: k == hl,
                    showCheckmark: false,
                    selectedColor: RL.navy,
                    labelStyle: TextStyle(fontWeight: FontWeight.w700, color: k == hl ? Colors.white : ink(context)),
                    onSelected: (_) => setState(() => _highlight = k),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Builder(
            builder: (bc) => FilledButton.icon(
              onPressed: _busy ? null : () => _share(bc, data),
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Icon(Icons.ios_share_rounded),
              label: Text(tr('Share image')),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: 'https://${data.link}'));
              if (context.mounted) showSnack(context, tr('Link copied'));
            },
            icon: const Icon(Icons.link_rounded),
            label: Text(data.link, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: 10),
          Text(
            tr('The image is {w}×{h} px, ready for stories and feeds. The link opens these Race Insights in the app or on the web.', {
              'w': 1080,
              'h': (1080 * size.height / size.width).round(),
            }),
            style: TextStyle(fontSize: 12.5, color: muted(context)),
          ),
        ],
      ),
    );
  }
}

class _StyleSwatch extends StatelessWidget {
  const _StyleSwatch({required this.style, required this.selected, required this.onTap});
  final CardStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = CardPalette.of(style);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 64,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: pal.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? RL.amber : (Theme.of(context).brightness == Brightness.dark ? Colors.white24 : RL.line), width: selected ? 3 : 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(width: 22, height: 4, decoration: BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(9))),
            const SizedBox(height: 5),
            Text(
              switch (style) {
                CardStyle.night => tr('Navy night'),
                CardStyle.sunrise => tr('Amber sunrise'),
                CardStyle.minimal => tr('Minimal light'),
              },
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: pal.fg, fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class CardPalette {
  const CardPalette({required this.background, required this.fg, required this.sub, required this.accent, required this.panel, required this.hlBg, required this.hlValue, required this.hlLabel, required this.route});
  final Gradient background;
  final Color fg, sub, accent, panel, hlBg, hlValue, hlLabel, route;

  static CardPalette of(CardStyle s) => switch (s) {
        CardStyle.night => CardPalette(
            background: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0A1226), RL.navy, Color(0xFF2A3D66)]),
            fg: Colors.white,
            sub: Colors.white70,
            accent: RL.amber,
            panel: Colors.white.withValues(alpha: 0.08),
            hlBg: RL.amber.withValues(alpha: 0.16),
            hlValue: RL.amber,
            hlLabel: Colors.white70,
            route: RL.amber.withValues(alpha: 0.75),
          ),
        CardStyle.sunrise => CardPalette(
            background: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFC56E), RL.amber, Color(0xFFD9480F)]),
            fg: Colors.white,
            sub: Colors.white.withValues(alpha: 0.85),
            accent: RL.navy,
            panel: Colors.white.withValues(alpha: 0.18),
            hlBg: RL.navy,
            hlValue: Colors.white,
            hlLabel: Colors.white70,
            route: Colors.white.withValues(alpha: 0.7),
          ),
        CardStyle.minimal => CardPalette(
            background: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white, Color(0xFFF3F5F9)]),
            fg: RL.navy,
            sub: RL.slate,
            accent: RL.amber,
            panel: const Color(0xFFEDF0F6),
            hlBg: RL.navy,
            hlValue: RL.amber,
            hlLabel: Colors.white70,
            route: RL.navy.withValues(alpha: 0.35),
          ),
      };
}

/// The card itself, drawn at a fixed logical size (360 wide) so the PNG
/// export is exactly 1080 px wide at pixel ratio 3.
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.data, required this.format, required this.style, this.highlight});
  final ShareCardData data;
  final CardFormat format;
  final CardStyle style;
  final CardHighlight? highlight;

  static const width = 360.0;
  static Size sizeOf(CardFormat f) => f == CardFormat.story ? const Size(360, 640) : const Size(360, 360);

  @override
  Widget build(BuildContext context) {
    final pal = CardPalette.of(style);
    final size = sizeOf(format);
    return MediaQuery.withNoTextScaling(
      child: DefaultTextStyle(
        style: TextStyle(color: pal.fg, fontFamily: DefaultTextStyle.of(context).style.fontFamily, decoration: TextDecoration.none),
        child: Container(
          width: size.width,
          height: size.height,
          decoration: BoxDecoration(gradient: pal.background),
          child: format == CardFormat.story ? _story(pal) : _square(pal),
        ),
      ),
    );
  }

  ({String big, String caption}) _main() {
    if (data.finished) return (big: fmtDuration(data.timeS), caption: tr('Net time').toUpperCase());
    return (
      big: fmtDistance(data.distanceM ?? 0, data.units),
      caption: switch (data.phase) {
        Phase.onCourse => tr('On course · live').toUpperCase(),
        Phase.dnf => tr('Did not finish').toUpperCase(),
        _ => tr('Registered').toUpperCase(),
      },
    );
  }

  Widget _logo(CardPalette pal) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(7)),
            child: const Icon(Icons.directions_run_rounded, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 7),
          Text('RunLah', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: pal.fg, letterSpacing: -0.3)),
        ],
      );

  Widget _footer(CardPalette pal) => Row(
        children: [
          Icon(Icons.link_rounded, size: 14, color: pal.sub),
          const SizedBox(width: 5),
          Flexible(child: Text(data.link, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: pal.fg))),
          const SizedBox(width: 8),
          Text(
            (data.official ? tr('Official') : tr('Provisional')).toUpperCase(),
            style: TextStyle(fontSize: 9.5, letterSpacing: 1.6, fontWeight: FontWeight.w800, color: pal.sub),
          ),
        ],
      );

  Widget? _highlightPanel(CardPalette pal, {bool compact = false}) {
    final h = highlight == null ? null : data.highlights[highlight];
    if (h == null) return null;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: compact ? 9 : 12),
      decoration: BoxDecoration(color: pal.hlBg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(h.icon, color: pal.hlValue, size: compact ? 22 : 28),
          const SizedBox(width: 10),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(h.value, maxLines: 1, style: TextStyle(fontSize: compact ? 22 : 28, fontWeight: FontWeight.w900, color: pal.hlValue, fontFeatures: tabular)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(h.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, height: 1.2, fontWeight: FontWeight.w700, color: pal.hlLabel)),
          ),
        ],
      ),
    );
  }

  Widget _statBox(CardPalette pal, String value, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: pal.panel, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(fit: BoxFit.scaleDown, child: Text(value, maxLines: 1, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: pal.fg, fontFeatures: tabular))),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: pal.sub)),
          ],
        ),
      );

  Widget _story(CardPalette pal) {
    final main = _main();
    final hl = _highlightPanel(pal);
    return Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: _CardArcs(pal.accent))),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _logo(pal),
                  const Spacer(),
                  Text(tr('Race Insights').toUpperCase(), style: TextStyle(fontSize: 9.5, letterSpacing: 1.8, fontWeight: FontWeight.w800, color: pal.sub)),
                ],
              ),
              const SizedBox(height: 18),
              Text(data.event, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: pal.fg)),
              Text('${data.race} · ${data.date}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: pal.sub)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: CustomPaint(painter: RouteOutlinePainter(route: data.route, color: pal.route, accent: pal.accent == RL.navy ? Colors.white : pal.accent, progress: (data.distanceM ?? 0) / data.route.nominalLength)),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(data.name, maxLines: 1, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: pal.fg)),
              ),
              Text('#${data.bib} · ${data.category}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: pal.sub)),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(main.big, maxLines: 1, style: TextStyle(fontSize: 68, height: 1, letterSpacing: -1.5, fontWeight: FontWeight.w900, color: pal.fg, fontFeatures: tabular)),
              ),
              const SizedBox(height: 2),
              Text(main.caption, maxLines: 1, style: TextStyle(fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w800, color: pal.sub)),
              if (data.finished) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _statBox(pal, ordinal(data.place!), tr('of {n} finishers', {'n': fmtInt(data.of!)}))),
                    const SizedBox(width: 10),
                    Expanded(child: _statBox(pal, data.place == 1 ? tr('Winner') : tr('Top {pct}', {'pct': fmtPct(data.topPct!)}), tr('overall'))),
                  ],
                ),
              ],
              if (hl != null) ...[const SizedBox(height: 10), hl],
              const SizedBox(height: 16),
              _footer(pal),
            ],
          ),
        ),
      ],
    );
  }

  Widget _square(CardPalette pal) {
    final main = _main();
    final hl = _highlightPanel(pal, compact: true);
    return Stack(
      children: [
        Positioned(
          right: -6,
          top: 30,
          width: 190,
          height: 170,
          child: Opacity(
            opacity: 0.55,
            child: CustomPaint(painter: RouteOutlinePainter(route: data.route, color: pal.route, accent: pal.accent == RL.navy ? Colors.white : pal.accent, progress: (data.distanceM ?? 0) / data.route.nominalLength)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _logo(pal),
              const SizedBox(height: 12),
              SizedBox(
                width: 210,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(data.name, maxLines: 1, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: pal.fg)),
                ),
              ),
              SizedBox(
                width: 200,
                child: Text(data.event, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: pal.sub)),
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(main.big, maxLines: 1, style: TextStyle(fontSize: 58, height: 1, letterSpacing: -1.2, fontWeight: FontWeight.w900, color: pal.fg, fontFeatures: tabular)),
              ),
              Text(main.caption, maxLines: 1, style: TextStyle(fontSize: 9.5, letterSpacing: 2, fontWeight: FontWeight.w800, color: pal.sub)),
              if (data.finished) ...[
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${ordinal(data.place!)} ${tr('of {n}', {'n': fmtInt(data.of!)})}  ·  ${data.place == 1 ? tr('Winner') : tr('Top {pct}', {'pct': fmtPct(data.topPct!)})}',
                    maxLines: 1,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: pal.fg),
                  ),
                ),
              ],
              if (hl != null) ...[const SizedBox(height: 10), hl],
              const SizedBox(height: 12),
              _footer(pal),
            ],
          ),
        ),
      ],
    );
  }
}

class _CardArcs extends CustomPainter {
  _CardArcs(this.accent);
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final c = Offset(size.width * 1.05, size.height * 0.04);
    for (var i = 0; i < 7; i++) {
      p.color = (i == 3 ? accent : Colors.white).withValues(alpha: i == 3 ? 0.22 : 0.06);
      canvas.drawCircle(c, size.width * 0.25 + i * 18, p);
    }
  }

  @override
  bool shouldRepaint(covariant _CardArcs old) => old.accent != accent;
}

/// The course outline, fitted into the box; [progress] of it highlighted.
class RouteOutlinePainter extends CustomPainter {
  RouteOutlinePainter({required this.route, required this.color, required this.accent, this.progress = 1});
  final RoutePath route;
  final Color color;
  final Color accent;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || route.points.length < 2) return;
    final pts = route.points;
    final lat0 = pts.first.latitude * math.pi / 180;
    final k = math.cos(lat0);
    var minX = double.infinity, maxX = -double.infinity, minY = double.infinity, maxY = -double.infinity;
    for (final p in pts) {
      final x = p.longitude * k, y = -p.latitude;
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
    }
    final sx = size.width / (maxX - minX), sy = size.height / (maxY - minY);
    final sc = math.min(sx, sy) * 0.92;
    final ox = (size.width - (maxX - minX) * sc) / 2, oy = (size.height - (maxY - minY) * sc) / 2;
    Offset map(double lat, double lng) => Offset(ox + (lng * k - minX) * sc, oy + (-lat - minY) * sc);
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final o = map(pts[i].latitude, pts[i].longitude);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3.2
      ..color = color.withValues(alpha: color.a * 0.45);
    canvas.drawPath(path, stroke);
    final pr = progress.clamp(0.0, 1.0);
    if (pr > 0) {
      final done = Path();
      final n = 160;
      for (var i = 0; i <= n; i++) {
        final ll = route.at(route.nominalLength * pr * i / n);
        final o = map(ll.latitude, ll.longitude);
        i == 0 ? done.moveTo(o.dx, o.dy) : done.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(done, stroke..color = color..strokeWidth = 3.6);
      final end = route.at(route.nominalLength * pr);
      final e = map(end.latitude, end.longitude);
      canvas.drawCircle(e, 7, Paint()..color = accent.withValues(alpha: 0.3));
      canvas.drawCircle(e, 4.2, Paint()..color = accent);
    }
    final s = map(pts.first.latitude, pts.first.longitude);
    canvas.drawCircle(s, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant RouteOutlinePainter old) => old.progress != progress || old.color != color || old.accent != accent;
}
