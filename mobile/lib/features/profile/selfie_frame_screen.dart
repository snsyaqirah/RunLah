import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import 'profile_widgets.dart';

enum FrameStyle { finisher, bib, minimal }

/// Selfie frames (F34): take or pick a photo, lay a race frame over it
/// (race, net time, place, bib, RunLah mark) and share the PNG. Works
/// without a photo too, on a built-in night-to-dawn KL skyline.
class SelfieFrameScreen extends StatefulWidget {
  const SelfieFrameScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const SelfieFrameScreen());

  @override
  State<SelfieFrameScreen> createState() => _SelfieFrameScreenState();
}

class _SelfieFrameScreenState extends State<SelfieFrameScreen> {
  final _frameKey = GlobalKey();
  Uint8List? _photo;
  FrameStyle _style = FrameStyle.finisher;
  bool _busy = false;

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picker = ImagePicker();
      if (source == ImageSource.camera && !picker.supportsImageSource(ImageSource.camera)) {
        source = ImageSource.gallery;
      }
      final file = await picker.pickImage(
        source: source,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 92,
        preferredCameraDevice: CameraDevice.front,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _photo = bytes);
    } catch (_) {
      if (mounted) showProfileSnack(context, tr('Couldn\'t open the camera or photos. Check permissions and try again.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final sim = context.read<RaceSim>();
    final snap = context.watch<InsightsController>().snapshot;
    final r = snap.result(sim.youId);
    final data = _FrameData.from(sim, r, settings.units);

    return Scaffold(
      appBar: AppBar(title: Text(tr('Selfie frame'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AspectRatio(
                aspectRatio: 4 / 5,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: FittedBox(
                    child: RepaintBoundary(
                      key: _frameKey,
                      child: SizedBox(
                        width: 360,
                        height: 450,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: _Frame(key: ValueKey((_style, _photo?.length)), style: _style, photo: _photo, data: data),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SectionLabel(tr('Frame style')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (s, label, icon) in [
                (FrameStyle.finisher, tr('Finisher'), Icons.emoji_events_rounded),
                (FrameStyle.bib, tr('Race bib'), Icons.confirmation_number_rounded),
                (FrameStyle.minimal, tr('Minimal'), Icons.crop_square_rounded),
              ])
                ChoiceChip(
                  avatar: Icon(icon, size: 16, color: _style == s ? Colors.white : ink(context)),
                  label: Text(label),
                  selected: _style == s,
                  showCheckmark: false,
                  selectedColor: RL.amber,
                  labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _style == s ? Colors.white : ink(context)),
                  onSelected: (_) => setState(() => _style = s),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SectionLabel(tr('Photo')),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_rounded),
                  label: Text(tr('Take photo'), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_rounded),
                  label: Text(tr('Choose photo'), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
          if (_photo != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _photo = null),
                icon: const Icon(Icons.hide_image_outlined),
                label: Text(tr('Use the skyline instead')),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(tr('No photo? The KL skyline background works too.'), style: TextStyle(color: muted(context), fontSize: 12.5)),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => shareBoundary(
              context,
              _frameKey,
              fileName: 'runlah-selfie-${sim.you.bib}.png',
              text: data.shareText,
            ),
            icon: const Icon(Icons.ios_share_rounded),
            label: Text(tr('Share framed photo')),
          ),
        ],
      ),
    );
  }
}

/// What goes on the frame, depending on the race state.
class _FrameData {
  const _FrameData({
    required this.event,
    required this.distance,
    required this.headline,
    required this.big,
    required this.place,
    required this.bib,
    required this.pace,
    required this.date,
    required this.finished,
    required this.shareText,
  });
  final String event;
  final String distance;

  /// FINISHER / RACE DAY / ON COURSE
  final String headline;

  /// Net time, or the gun time before the race.
  final String big;
  final String? place;
  final String bib;
  final String? pace;
  final String date;
  final bool finished;
  final String shareText;

  factory _FrameData.from(RaceSim sim, ResultRow r, Units units) {
    final race = sim.race;
    final finished = r.status == ResultStatus.finished && r.netS != null;
    final distance = '${race.name} · ${fmtDistance(race.distanceM, units)}';
    final place = finished ? tr('{place} of {n}', {'place': ordinal(r.overall!.place), 'n': fmtInt(r.overall!.of)}) : null;
    return _FrameData(
      event: sim.event.name,
      distance: distance,
      headline: switch (r.status) {
        ResultStatus.finished => tr('FINISHER'),
        ResultStatus.onCourse => tr('ON COURSE'),
        _ => tr('RACE DAY'),
      },
      big: finished ? fmtDuration(r.netS) : fmtClock(race.scheduledStart),
      place: place,
      bib: sim.you.bib,
      pace: finished ? fmtPace(r.avgPaceSPerKm, units) : null,
      date: fmtDate(sim.event.date),
      finished: finished,
      shareText: finished
          ? tr('{time} at {race}! {place} · #RunLah', {'time': fmtDuration(r.netS), 'race': sim.event.name, 'place': place})
          : tr('Race day at {race}. Bib {bib}, gun {gun}. #RunLah', {'race': sim.event.name, 'bib': sim.you.bib, 'gun': fmtClock(race.scheduledStart)}),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({super.key, required this.style, required this.photo, required this.data});
  final FrameStyle style;
  final Uint8List? photo;
  final _FrameData data;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (photo != null)
          Image.memory(photo!, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => const _SkylineBackground())
        else
          const _SkylineBackground(),
        switch (style) {
          FrameStyle.finisher => _FinisherOverlay(data: data),
          FrameStyle.bib => _BibOverlay(data: data),
          FrameStyle.minimal => _MinimalOverlay(data: data),
        },
      ],
    );
  }
}

const _white = Colors.white;
const _tab = [FontFeature.tabularFigures()];

class _FinisherOverlay extends StatelessWidget {
  const _FinisherOverlay({required this.data});
  final _FrameData data;

  @override
  Widget build(BuildContext context) {
    Widget stat(String v, String l) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(v, style: const TextStyle(color: _white, fontWeight: FontWeight.w900, fontSize: 16, fontFeatures: _tab))),
              Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _white.withValues(alpha: 0.7), fontSize: 10.5)),
            ],
          ),
        );
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x66000000), Color(0x00000000), Color(0x00000000), Color(0xE614213D)],
              stops: [0, 0.22, 0.45, 0.85],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const RunLahMark(size: 15),
                  const Spacer(),
                  Text(data.date, style: const TextStyle(color: _white, fontWeight: FontWeight.w700, fontSize: 12)),
                ],
              ),
              const Spacer(),
              Text(data.headline, style: const TextStyle(color: RL.amber, fontWeight: FontWeight.w900, letterSpacing: 3, fontSize: 13)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(data.big, style: const TextStyle(color: _white, fontWeight: FontWeight.w900, fontSize: 64, height: 1.05, letterSpacing: -1.5, fontFeatures: _tab)),
              ),
              Text(data.event, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _white, fontWeight: FontWeight.w800, fontSize: 15)),
              Text(data.distance, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _white.withValues(alpha: 0.75), fontSize: 12)),
              const SizedBox(height: 12),
              Container(height: 1, color: _white.withValues(alpha: 0.2)),
              const SizedBox(height: 10),
              Row(
                children: [
                  stat(data.place ?? '–', tr('Place')),
                  stat(data.bib, tr('Bib')),
                  stat(data.pace ?? '–', tr('Avg pace')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BibOverlay extends StatelessWidget {
  const _BibOverlay({required this.data});
  final _FrameData data;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Amber race-number frame.
        Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(border: Border.all(color: RL.amber, width: 6), borderRadius: BorderRadius.circular(18)),
        ),
        Positioned(
          top: 26,
          left: 26,
          right: 26,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: RL.navy.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(99)),
                child: const RunLahMark(size: 13),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: RL.navy.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(data.headline, style: const TextStyle(color: RL.amber, fontWeight: FontWeight.w900, fontSize: 9.5, letterSpacing: 1.5)),
                    Text(data.big, style: const TextStyle(color: _white, fontWeight: FontWeight.w900, fontSize: 24, fontFeatures: _tab)),
                  ],
                ),
              ),
            ],
          ),
        ),
        // The paper bib, pinned on at a slight angle.
        Positioned(
          left: 30,
          right: 70,
          bottom: 34,
          child: Transform.rotate(
            angle: -0.06,
            child: Container(
              decoration: BoxDecoration(
                color: _white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 14, offset: Offset(0, 6))],
              ),
              child: Stack(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
                        decoration: const BoxDecoration(color: RL.amber, borderRadius: BorderRadius.vertical(top: Radius.circular(8))),
                        child: Text(
                          data.event.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _white, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.8),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: FittedBox(
                          child: Text(data.bib, style: const TextStyle(color: RL.navy, fontWeight: FontWeight.w900, fontSize: 64, height: 1.1, fontFeatures: _tab)),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
                        child: Text(
                          [data.distance, ?data.place].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: RL.slate, fontWeight: FontWeight.w800, fontSize: 10.5),
                        ),
                      ),
                    ],
                  ),
                  // Safety pins.
                  for (final a in const [Alignment.topLeft, Alignment.topRight, Alignment.bottomLeft, Alignment.bottomRight])
                    Positioned.fill(
                      child: Align(
                        alignment: a,
                        child: Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.all(7),
                          decoration: BoxDecoration(color: const Color(0xFFB4BCCB), shape: BoxShape.circle, border: Border.all(color: const Color(0xFF8A93A3))),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MinimalOverlay extends StatelessWidget {
  const _MinimalOverlay({required this.data});
  final _FrameData data;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(color: _white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(18)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(data.event, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: RL.navy, fontWeight: FontWeight.w900, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(
                      [data.big, ?data.place, tr('Bib {bib}', {'bib': data.bib})].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: RL.slate, fontWeight: FontWeight.w700, fontSize: 12, fontFeatures: _tab),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const RunLahMark(size: 14, showText: false),
            ],
          ),
        ),
      ),
    );
  }
}

/// Built-in background: KL skyline at dawn (twin towers + KL Tower) with the
/// course loop glowing in the sky.
class _SkylineBackground extends StatelessWidget {
  const _SkylineBackground();

  @override
  Widget build(BuildContext context) => const CustomPaint(painter: _SkylinePainter());
}

class _SkylinePainter extends CustomPainter {
  const _SkylinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1230), Color(0xFF2A2350), Color(0xFF8A3A7A), Color(0xFFF59E0B)],
          stops: [0, 0.38, 0.68, 1],
        ).createShader(rect),
    );
    // Stars.
    final r = math.Random(4);
    final star = Paint()..color = Colors.white.withValues(alpha: 0.7);
    for (var i = 0; i < 40; i++) {
      canvas.drawCircle(Offset(r.nextDouble() * w, r.nextDouble() * h * 0.4), r.nextDouble() * 1.2 + 0.3, star);
    }
    // Sun glow on the horizon.
    canvas.drawCircle(
      Offset(w * 0.7, h * 0.86),
      w * 0.45,
      Paint()..shader = RadialGradient(colors: [const Color(0xFFFFD27A).withValues(alpha: 0.75), const Color(0x00FFD27A)]).createShader(Rect.fromCircle(center: Offset(w * 0.7, h * 0.86), radius: w * 0.45)),
    );
    // Course loop in the sky.
    final loop = Path();
    for (var i = 0; i <= 80; i++) {
      final a = i / 80 * 2 * math.pi;
      final p = Offset(w * 0.52 + math.cos(a) * w * 0.3 + math.sin(a * 3) * w * 0.035, h * 0.3 + math.sin(a) * h * 0.11 + math.cos(a * 2) * h * 0.02);
      i == 0 ? loop.moveTo(p.dx, p.dy) : loop.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      loop,
      Paint()
        ..color = RL.amber.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      loop,
      Paint()
        ..color = RL.amber.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Skyline.
    final city = Paint()..color = const Color(0xFF14152E);
    final base = h * 0.98;
    final sky = Path()..moveTo(0, h);
    final blocks = [0.0, 0.62, 0.05, 0.7, 0.1, 0.66, 0.16, 0.74, 0.22, 0.69, 0.27, 0.78, 0.33, 0.72, 0.62, 0.76, 0.68, 0.7, 0.74, 0.75, 0.8, 0.68, 0.86, 0.73, 0.92, 0.66, 1.0, 0.7];
    for (var i = 0; i < blocks.length; i += 2) {
      sky.lineTo(blocks[i] * w, blocks[i + 1] * h);
      if (i + 2 < blocks.length) sky.lineTo(blocks[i + 2] * w, blocks[i + 1] * h);
    }
    sky
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(sky, city);
    // Twin towers.
    void tower(double cx) {
      final t = Path()
        ..moveTo(cx - w * 0.035, base)
        ..lineTo(cx - w * 0.035, h * 0.5)
        ..lineTo(cx - w * 0.025, h * 0.46)
        ..lineTo(cx - w * 0.018, h * 0.4)
        ..lineTo(cx - w * 0.008, h * 0.37)
        ..lineTo(cx - w * 0.002, h * 0.27)
        ..lineTo(cx + w * 0.002, h * 0.27)
        ..lineTo(cx + w * 0.008, h * 0.37)
        ..lineTo(cx + w * 0.018, h * 0.4)
        ..lineTo(cx + w * 0.025, h * 0.46)
        ..lineTo(cx + w * 0.035, h * 0.5)
        ..lineTo(cx + w * 0.035, base)
        ..close();
      canvas.drawPath(t, city);
    }

    tower(w * 0.43);
    tower(w * 0.53);
    canvas.drawRect(Rect.fromLTWH(w * 0.43, h * 0.56, w * 0.1, h * 0.012), city); // skybridge
    // KL Tower.
    final kl = Path()
      ..moveTo(w * 0.205, base)
      ..lineTo(w * 0.215, h * 0.5)
      ..lineTo(w * 0.225, h * 0.5)
      ..lineTo(w * 0.235, base)
      ..close();
    canvas.drawPath(kl, city);
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.22, h * 0.49), width: w * 0.06, height: h * 0.035), city);
    canvas.drawRect(Rect.fromLTWH(w * 0.218, h * 0.4, w * 0.004, h * 0.08), city);
    // Window lights.
    final lights = Paint()..color = const Color(0xFFFFE3A3).withValues(alpha: 0.55);
    for (var i = 0; i < 70; i++) {
      final x = r.nextDouble() * w, y = h * (0.74 + r.nextDouble() * 0.22);
      canvas.drawRect(Rect.fromLTWH(x, y, 1.6, 2.4), lights);
    }
  }

  @override
  bool shouldRepaint(_SkylinePainter old) => false;
}
