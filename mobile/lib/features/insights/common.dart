import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/insights/insights_engine.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';

/// Shared bits for the Results & Race Insights feature.

/// Where a runner is in their race, as far as the current snapshot knows.
enum Phase { preRace, notStarted, onCourse, finished, dnf, dns }

Phase phaseOf(RaceSim sim, InsightsSnapshot s, int pid) {
  final st = s.statusOf(pid);
  if (st == ResultStatus.finished) return Phase.finished;
  if (sim.status == RaceStatus.preRace) return Phase.preRace;
  if (st == ResultStatus.dnf) return Phase.dnf;
  if (st == ResultStatus.dns) return s.closed ? Phase.dns : Phase.notStarted;
  // On course per the timing data; the tracker also knows about drop-outs.
  if (sim.stateAt(pid, s.asOf) == RunnerState.dnf) return Phase.dnf;
  return Phase.onCourse;
}

/// Race time a runner crossed checkpoint [k], if the snapshot knows it.
double? crossAt(InsightsSnapshot s, int pid, int k) {
  final i = s.table.indexOf[pid];
  if (i == null || k < 0 || k >= s.table.times.length) return null;
  final t = s.table.times[k][i];
  return (t.isNaN || t > s.asOf) ? null : t;
}

/// Index of the last checkpoint a runner has crossed (or null).
int? lastCheckpoint(InsightsSnapshot s, int pid) {
  int? last;
  for (var k = 0; k < s.race.checkpoints.length; k++) {
    if (crossAt(s, pid, k) == null) break;
    last = k;
  }
  return last;
}

/// Name as shown in Insights: the user's own display name for "you",
/// otherwise the public results name (respects bib-only).
String nameOf(BuildContext context, Participant p) {
  final sim = context.read<RaceSim>();
  if (p.id == sim.youId) {
    final n = context.read<SettingsController>().displayName.trim();
    return n.isEmpty ? p.name : n;
  }
  return p.displayName;
}

String firstNameOf(BuildContext context, Participant p) {
  final sim = context.read<RaceSim>();
  if (p.id == sim.youId) return nameOf(context, p).split(' ').first;
  if (p.resultsName == ResultsName.bibOnly) return p.displayName;
  return p.firstName;
}

String categoryName(Race race, Participant p) {
  for (final c in race.categories) {
    if (c.id == p.categoryId) return c.name;
  }
  return '';
}

String nationName(String code) => switch (code) {
      'MAS' => tr('Malaysia'),
      'SGP' => tr('Singapore'),
      'IDN' => tr('Indonesia'),
      'KEN' => tr('Kenya'),
      'GBR' => tr('United Kingdom'),
      'AUS' => tr('Australia'),
      'JPN' => tr('Japan'),
      'CHN' => tr('China'),
      'IND' => tr('India'),
      'PHL' => tr('Philippines'),
      'THA' => tr('Thailand'),
      'USA' => tr('United States'),
      'KOR' => tr('South Korea'),
      _ => code,
    };

/// "KM 14.1" / "MI 8.8".
String kmLabel(double metres, Units units) => '${units == Units.km ? 'KM' : 'MI'} ${fmtDistance(metres, units, withUnit: false)}';

/// Distance label for a checkpoint axis: "0", "2.6", ... "21.1".
String cpAxisLabel(Checkpoint c, Units units) => c.distanceM == 0 ? '0' : fmtDistance(c.distanceM, units, withUnit: false);

Color genderColor(Gender g) => g == Gender.f ? RL.female : RL.male;

// ------------------------------------------------------------------ widgets

/// Number that counts up to [value] (and glides between later values).
class CountUp extends StatelessWidget {
  const CountUp({
    super.key,
    required this.value,
    required this.format,
    this.style,
    this.from = 0,
    this.duration = const Duration(milliseconds: 1200),
    this.textAlign,
  });
  final double value;
  final String Function(double v) format;
  final TextStyle? style;
  final double from;
  final Duration duration;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final end = value.isFinite ? value : from;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: from, end: end),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text(
        format(v == end ? end : v),
        maxLines: 1,
        textAlign: textAlign,
        style: style,
      ),
    );
  }
}

/// Fades and slides its child in, a little later for higher [index].
class Entrance extends StatelessWidget {
  const Entrance({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delay = 70 * index.clamp(0, 8);
    final total = 460 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (_, v, c) => Opacity(
        opacity: v.clamp(0, 1),
        child: Transform.translate(offset: Offset(0, (1 - v) * 26), child: c),
      ),
    );
  }
}

/// Compact pill toggle ("Net | Gun", "Quarters | Checkpoints").
/// Scales down instead of overflowing on narrow screens.
class SegToggle<T> extends StatelessWidget {
  const SegToggle({super.key, required this.value, required this.options, required this.onChanged, this.onDark = false});
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  /// Drawn on a navy hero card.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark || onDark;
    final track = onDark
        ? Colors.white.withValues(alpha: 0.10)
        : dark
            ? Colors.white.withValues(alpha: 0.07)
            : const Color(0xFFE9EDF4);
    final selBg = onDark ? RL.amber : (dark ? RL.amber : RL.navy);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (v, label) in options)
              Semantics(
                button: true,
                selected: v == value,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: v == value ? null : () => onChanged(v),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                    decoration: BoxDecoration(
                      color: v == value ? selBg : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: v == value ? Colors.white : (dark ? Colors.white70 : RL.slate),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Official / Provisional / Live / Pre-race badge for the current snapshot.
class ResultsStatusPill extends StatelessWidget {
  const ResultsStatusPill({super.key, this.filled = false});
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final sim = context.watch<RaceSim>();
    if (sim.status == RaceStatus.preRace) return Pill(tr('Pre-race'), color: RL.slate, filled: filled, icon: Icons.schedule_rounded);
    if (sim.official) return Pill(tr('Official'), color: RL.green, filled: filled, icon: Icons.verified_rounded);
    if (sim.status == RaceStatus.live) return Pill(tr('Live · provisional'), color: RL.amber, filled: filled, icon: Icons.sensors_rounded);
    return Pill(tr('Provisional'), color: RL.amber, filled: filled, icon: Icons.hourglass_bottom_rounded);
  }
}

/// Navy gradient hero card with faint running-track arcs.
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 18), this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Stack(
      children: [
        const Positioned.fill(child: CustomPaint(painter: _TrackArcs())),
        Padding(padding: padding, child: child),
      ],
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0E1830), RL.navy, Color(0xFF2A3D66)],
          stops: [0, 0.55, 1],
        ),
        boxShadow: [BoxShadow(color: RL.navy.withValues(alpha: 0.16), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

class _TrackArcs extends CustomPainter {
  const _TrackArcs();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final c = Offset(size.width * 1.02, size.height * -0.1);
    for (var i = 0; i < 6; i++) {
      p.color = (i == 2 ? RL.amber : Colors.white).withValues(alpha: i == 2 ? 0.16 : 0.05);
      canvas.drawCircle(c, size.width * 0.32 + i * 16, p);
    }
  }

  @override
  bool shouldRepaint(covariant _TrackArcs old) => false;
}

/// Light text styles for content on [HeroCard].
const heroLabel = TextStyle(color: RL.amber, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.2);
const heroMuted = TextStyle(color: Colors.white70, fontSize: 12.5);
const tabular = [FontFeature.tabularFigures()];

/// Small stat on a [HeroCard]: value on top, caption below.
class HeroStat extends StatelessWidget {
  const HeroStat({super.key, required this.value, required this.label, this.align = CrossAxisAlignment.start});
  final String value;
  final String label;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: align,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, maxLines: 1, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, fontFeatures: tabular)),
          ),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
        ],
      );
}

/// Round initials badge for a runner.
class RunnerAvatar extends StatelessWidget {
  const RunnerAvatar({super.key, required this.name, required this.color, this.size = 38, this.icon});
  final String name;
  final Color color;
  final double size;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final parts = name.split(' ').where((w) => w.isNotEmpty && w != 'bin' && w != 'binti').toList();
    final initials = parts.isEmpty ? '?' : (parts.length == 1 ? parts.first.substring(0, 1) : '${parts[0][0]}${parts[1][0]}').toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle, border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5)),
      child: icon != null
          ? Icon(icon, size: size * 0.5, color: color)
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Text(initials, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: size * 0.36)),
              ),
            ),
    );
  }
}

/// Card with an icon, title and subtitle that opens something.
class ActionTile extends StatelessWidget {
  const ActionTile({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap, this.color = RL.amber});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => RLCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: ink(context))),
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: muted(context))),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: muted(context)),
          ],
        ),
      );
}

/// Friendly empty / state card with an icon, a title and a message.
class StateCard extends StatelessWidget {
  const StateCard({super.key, required this.icon, required this.title, required this.message, this.color = RL.amber, this.children = const []});
  final IconData icon;
  final String title;
  final String message;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => RLCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 14),
            Text(title, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: ink(context))),
            const SizedBox(height: 6),
            Text(message, style: TextStyle(fontSize: 14, height: 1.4, color: muted(context))),
            ...children,
          ],
        ),
      );
}

/// Scroll body for one Insights tab inside the NestedScrollView.
class TabScroll extends StatelessWidget {
  const TabScroll({super.key, required this.storageKey, required this.children});
  final String storageKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) => CustomScrollView(
        key: PageStorageKey(storageKey),
        slivers: [
          SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: RL.gap + 2),
                  Entrance(index: i, child: children[i]),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- PNG export

/// Renders the [RepaintBoundary] behind [key] to PNG bytes.
Future<Uint8List?> capturePng(GlobalKey key, {double pixelRatio = 3}) async {
  await WidgetsBinding.instance.endOfFrame;
  final ro = key.currentContext?.findRenderObject();
  if (ro is! RenderRepaintBoundary) return null;
  final image = await ro.toImage(pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Shares a PNG through the system share sheet. On web, share_plus falls
/// back to downloading the file when the Web Share API can't take files.
Future<bool> sharePng(Uint8List bytes, {required String fileName, required String text, Rect? origin}) async {
  try {
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'image/png', name: fileName)],
      fileNameOverrides: [fileName],
      text: text,
      sharePositionOrigin: origin,
      downloadFallbackEnabled: true,
    ));
    return true;
  } catch (_) {
    return false;
  }
}

/// Share-sheet anchor rect for iPad popovers.
Rect? originOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}

/// Public deep link for a runner's Insights.
String deepLink(Participant p) => 'runlah.app/r/${p.bib}';

/// One-line result summary for lists: "172nd · 1:36:15", "On course · KM 8.2".
String statusLine(InsightsSnapshot s, RaceSim sim, int id, Units units) {
  switch (phaseOf(sim, s, id)) {
    case Phase.finished:
      final r = s.result(id);
      return '${ordinal(r.overall!.place)} · ${fmtDuration(s.basis == RankBasis.net ? r.netS : r.gunS)}';
    case Phase.onCourse:
      final p = sim.participant(id);
      final d = p.hasGps ? sim.distanceAt(id, s.asOf) : s.estimatedDistanceAt(id, s.asOf);
      return '${tr('On course')} · ${kmLabel(d, units)}';
    case Phase.dnf:
      return tr('Did not finish');
    case Phase.dns:
      return tr('Did not start');
    case Phase.notStarted:
      return tr('Not started yet');
    case Phase.preRace:
      return tr('Registered');
  }
}
