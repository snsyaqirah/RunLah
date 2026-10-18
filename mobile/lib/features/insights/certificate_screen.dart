import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import 'common.dart';

/// F33 e-certificate: an elegant, widget-drawn certificate for an official
/// finisher, shareable as a PNG (1080 × 1530).
class CertificateScreen extends StatefulWidget {
  const CertificateScreen({super.key, required this.participantId});
  final int participantId;

  @override
  State<CertificateScreen> createState() => _CertificateScreenState();
}

class _CertificateScreenState extends State<CertificateScreen> {
  final _boundary = GlobalKey();
  bool _busy = false;

  Future<void> _share(BuildContext buttonContext, String name, String bib, String event) async {
    final origin = originOf(buttonContext);
    setState(() => _busy = true);
    try {
      final bytes = await capturePng(_boundary, pixelRatio: 1080 / Certificate.size.width);
      if (bytes == null) throw StateError('no image');
      final ok = await sharePng(bytes, fileName: 'runlah-certificate-$bib.png', text: tr('{name}\'s finisher e-certificate from {event}', {'name': name, 'event': event}), origin: origin);
      if (!ok && mounted) showSnack(context, tr('Sharing isn\'t available on this device. Try again on your phone.'));
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
    context.watch<SettingsController>();
    final p = sim.participant(widget.participantId);
    final r = s.result(p.id);
    final finished = r.status == ResultStatus.finished;
    final name = nameOf(context, p);
    return Scaffold(
      appBar: AppBar(title: Text(tr('E-certificate'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (!finished || !s.official)
            StateCard(icon: Icons.lock_clock_rounded, title: tr('Not available yet'), message: tr('E-certificates are issued to finishers once the organizer publishes official results.'))
          else ...[
            Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 24, offset: const Offset(0, 10))],
                ),
                child: FittedBox(
                  child: RepaintBoundary(
                    key: _boundary,
                    child: Certificate(
                      name: name,
                      bib: p.bib,
                      event: sim.event.name,
                      race: '${tr(s.race.name)} · ${fmtDistance(s.race.distanceM, Units.km)}',
                      place: '${sim.event.city} · ${fmtDate(sim.event.date)}',
                      net: fmtDuration(r.netS),
                      gun: fmtDuration(r.gunS),
                      overall: '${ordinal(r.overall!.place)} / ${fmtInt(r.overall!.of)}',
                      category: '${ordinal(r.category!.place)} · ${categoryName(s.race, p)}',
                      verifyCode: p.verifyCode,
                      organizer: sim.event.organizer,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Builder(
              builder: (bc) => FilledButton.icon(
                onPressed: _busy ? null : () => _share(bc, name, p.bib, sim.event.name),
                icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)) : const Icon(Icons.ios_share_rounded),
                label: Text(tr('Share as image')),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.verified_user_rounded, size: 16, color: muted(context)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(tr('Anyone can verify this certificate with code {code} at runlah.app/verify.', {'code': p.verifyCode}), style: TextStyle(fontSize: 12.5, color: muted(context))),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The certificate artwork. Fixed colours: it's a document, not themed UI.
class Certificate extends StatelessWidget {
  const Certificate({
    super.key,
    required this.name,
    required this.bib,
    required this.event,
    required this.race,
    required this.place,
    required this.net,
    required this.gun,
    required this.overall,
    required this.category,
    required this.verifyCode,
    required this.organizer,
  });
  final String name, bib, event, race, place, net, gun, overall, category, verifyCode, organizer;

  static const size = Size(360, 510);
  static const ivory = Color(0xFFFFFCF4);
  static const gold = Color(0xFFC98A12);

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value) => Expanded(
      child: Column(
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            style: const TextStyle(fontSize: 7.5, letterSpacing: 1.4, fontWeight: FontWeight.w800, color: RL.slate),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: RL.navy, fontFeatures: tabular),
            ),
          ),
        ],
      ),
    );
    return MediaQuery.withNoTextScaling(
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: RL.navy, decoration: TextDecoration.none),
        textAlign: TextAlign.center,
        child: Container(
          width: size.width,
          height: size.height,
          decoration: const BoxDecoration(
            gradient: RadialGradient(center: Alignment(0, -0.3), radius: 1.1, colors: [Colors.white, ivory, Color(0xFFF7EFDC)]),
          ),
          child: CustomPaint(
            painter: const _CertificateFrame(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(34, 34, 34, 28),
              child: Column(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: size.width - 68,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(color: RL.amber, borderRadius: BorderRadius.circular(5)),
                                  child: const Icon(Icons.directions_run_rounded, size: 11, color: Colors.white),
                                ),
                                const SizedBox(width: 5),
                                const Text(
                                  'RunLah',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: RL.navy),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              event.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 8, letterSpacing: 1.6, fontWeight: FontWeight.w700, color: RL.slate),
                            ),
                            const SizedBox(height: 16),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                tr('Certificate').toUpperCase(),
                                style: const TextStyle(fontSize: 28, letterSpacing: 7, fontWeight: FontWeight.w900, color: RL.navy),
                              ),
                            ),
                            Text(
                              tr('of achievement').toUpperCase(),
                              style: const TextStyle(fontSize: 9.5, letterSpacing: 4, fontWeight: FontWeight.w800, color: gold),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              tr('This certifies that'),
                              style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: RL.slate),
                            ),
                            const SizedBox(height: 8),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                name,
                                maxLines: 1,
                                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, fontStyle: FontStyle.italic, color: RL.navy, letterSpacing: 0.3),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(width: 170, height: 1.4, color: gold),
                            const SizedBox(height: 4),
                            Text(
                              'BIB $bib',
                              style: const TextStyle(fontSize: 8.5, letterSpacing: 2, fontWeight: FontWeight.w800, color: RL.slate),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              tr('has successfully completed the'),
                              style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: RL.slate),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              race,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: RL.navy),
                            ),
                            Text(
                              place,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10, color: RL.slate),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                              decoration: BoxDecoration(
                                border: Border.symmetric(horizontal: BorderSide(color: gold.withValues(alpha: 0.5))),
                              ),
                              child: Row(children: [stat(tr('Net time'), net), stat(tr('Gun time'), gun), stat(tr('Overall'), overall)]),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              category,
                              maxLines: 1,
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: gold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const _Seal(),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Race Director',
                              style: TextStyle(fontSize: 15, fontStyle: FontStyle.italic, fontWeight: FontWeight.w300, color: RL.navySoft),
                            ),
                            Container(height: 1, color: RL.slate.withValues(alpha: 0.5), margin: const EdgeInsets.symmetric(vertical: 3)),
                            Text(
                              organizer,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 7.5, color: RL.slate),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          QrImageView(
                            data: 'https://runlah.app/verify/$verifyCode',
                            size: 56,
                            padding: EdgeInsets.zero,
                            eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: RL.navy),
                            dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: RL.navy),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            verifyCode,
                            style: const TextStyle(fontSize: 7, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: RL.slate),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Seal extends StatelessWidget {
  const _Seal();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 62,
    height: 62,
    child: CustomPaint(
      painter: const _SealPainter(),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_rounded, size: 18, color: Colors.white),
            Text(
              tr('Official').toUpperCase(),
              style: const TextStyle(fontSize: 6.5, letterSpacing: 1, fontWeight: FontWeight.w900, color: Colors.white),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SealPainter extends CustomPainter {
  const _SealPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    // Scalloped rosette.
    final path = Path();
    const n = 24;
    for (var i = 0; i <= n * 2; i++) {
      final a = i * math.pi / n;
      final rr = i.isEven ? r : r * 0.9;
      final o = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, Paint()..color = Certificate.gold);
    canvas.drawCircle(c, r * 0.78, Paint()..color = RL.amber);
    canvas.drawCircle(
      c,
      r * 0.7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(covariant _SealPainter old) => false;
}

class _CertificateFrame extends CustomPainter {
  const _CertificateFrame();

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Rect.fromLTWH(10, 10, size.width - 20, size.height - 20);
    final inner = outer.deflate(6);
    canvas.drawRect(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = RL.navy,
    );
    canvas.drawRect(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Certificate.gold,
    );
    // Corner ornaments.
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = Certificate.gold;
    final dot = Paint()..color = Certificate.gold;
    for (final (corner, dx, dy) in [(inner.topLeft, 1.0, 1.0), (inner.topRight, -1.0, 1.0), (inner.bottomLeft, 1.0, -1.0), (inner.bottomRight, -1.0, -1.0)]) {
      final o = corner + Offset(6 * dx, 6 * dy);
      canvas.drawPath(
        Path()
          ..moveTo(o.dx, o.dy + 22 * dy)
          ..lineTo(o.dx, o.dy)
          ..lineTo(o.dx + 22 * dx, o.dy),
        p,
      );
      canvas.drawArc(Rect.fromCircle(center: o + Offset(9 * dx, 9 * dy), radius: 6), 0, math.pi * 2, false, p..strokeWidth = 1);
      canvas.drawCircle(o + Offset(9 * dx, 9 * dy), 1.8, dot);
      p.strokeWidth = 1.6;
    }
    // Faint running track arcs behind the content.
    final arcs = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (var i = 0; i < 5; i++) {
      arcs.color = (i == 2 ? Certificate.gold : RL.navy).withValues(alpha: 0.05);
      canvas.drawCircle(Offset(size.width / 2, size.height * 1.15), size.width * 0.5 + i * 14, arcs);
    }
  }

  @override
  bool shouldRepaint(covariant _CertificateFrame old) => false;
}
