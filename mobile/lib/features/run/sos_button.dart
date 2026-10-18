import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';

/// SOS to the organizer (PRD F11). Hold the button for 2 s (a ring fills),
/// pick a reason, and your location goes to the organizer console. Then the
/// card shows "Organizer notified" with the alert's live status.
class SosCard extends StatefulWidget {
  const SosCard({super.key});

  @override
  State<SosCard> createState() => _SosCardState();
}

class _SosCardState extends State<SosCard> with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(vsync: this, duration: const Duration(seconds: 2))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _confirmed();
    });

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  void _down() {
    HapticFeedback.mediumImpact();
    _hold.forward();
  }

  void _up() {
    if (_hold.isCompleted) return;
    _hold.animateBack(0, duration: const Duration(milliseconds: 250));
  }

  Future<void> _confirmed() async {
    HapticFeedback.heavyImpact();
    final sim = context.read<RaceSim>();
    final reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _ReasonSheet(),
    );
    if (!mounted) return;
    _hold.value = 0;
    if (reason == null) return;
    sim.raiseSos(sim.youId, reason);
  }

  @override
  Widget build(BuildContext context) {
    final sim = context.watch<RaceSim>();
    SosAlert? mine;
    for (final a in sim.sosAlerts) {
      if (a.participantId == sim.youId && a.status != 'closed') {
        mine = a;
        break;
      }
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: mine == null ? _holdCard(context) : _NotifiedCard(key: ValueKey(mine.id), alert: mine),
    );
  }

  Widget _holdCard(BuildContext context) {
    return RLCard(
      key: const ValueKey('hold'),
      child: Row(
        children: [
          GestureDetector(
            onTapDown: (_) => _down(),
            onTapUp: (_) => _up(),
            onTapCancel: _up,
            child: Semantics(
              button: true,
              label: tr('SOS. Hold for 2 seconds'),
              child: SizedBox(
                width: 84,
                height: 84,
                child: AnimatedBuilder(
                  animation: _hold,
                  builder: (_, _) => CustomPaint(
                    painter: _RingPainter(_hold.value),
                    child: Center(
                      child: Transform.scale(
                        scale: 1 - 0.06 * _hold.value,
                        child: Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const RadialGradient(colors: [Color(0xFFEF6363), RL.red]),
                            boxShadow: [BoxShadow(color: RL.red.withValues(alpha: 0.35 + 0.3 * _hold.value), blurRadius: 12 + 10 * _hold.value)],
                          ),
                          alignment: Alignment.center,
                          child: const FittedBox(
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: Text('SOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Need help?'), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: ink(context))),
                const SizedBox(height: 3),
                Text(
                  tr('Hold the button for 2 seconds. Your location goes straight to the race organizer.'),
                  style: TextStyle(fontSize: 12.5, color: muted(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 4;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = RL.red.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    if (progress <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = RL.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.progress != progress;
}

class _ReasonSheet extends StatelessWidget {
  const _ReasonSheet();

  @override
  Widget build(BuildContext context) {
    final reasons = <(IconData, String)>[
      (Icons.personal_injury_rounded, tr('Injury, cannot continue')),
      (Icons.accessibility_new_rounded, tr('Cramp, cannot continue')),
      (Icons.thermostat_rounded, tr('Feeling dizzy or unwell (heat)')),
      (Icons.monitor_heart_rounded, tr('Chest pain or breathing trouble')),
      (Icons.wrong_location_rounded, tr('Lost or off course')),
      (Icons.sos_rounded, tr('Other emergency')),
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.sos_rounded, color: RL.red, size: 28),
                const SizedBox(width: 10),
                Expanded(child: Text(tr('What happened?'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: ink(context)))),
              ],
            ),
            const SizedBox(height: 4),
            Text(tr('Tap one. The organizer sees it with your location and bib.'), style: TextStyle(color: muted(context))),
            const SizedBox(height: 12),
            for (final (icon, label) in reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: RL.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.pop(context, label),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      child: Row(
                        children: [
                          Icon(icon, color: RL.red),
                          const SizedBox(width: 12),
                          Expanded(child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: ink(context)))),
                          Icon(Icons.chevron_right_rounded, color: muted(context)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel, I\'m fine'))),
          ],
        ),
      ),
    );
  }
}

class _NotifiedCard extends StatelessWidget {
  const _NotifiedCard({super.key, required this.alert});
  final SosAlert alert;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final acknowledged = alert.status == 'acknowledged';
    final d = sim.distanceAt(alert.participantId, alert.raceTimeS);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(RL.radius),
        gradient: const LinearGradient(colors: [Color(0xFFB83232), RL.red], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: RL.red.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  acknowledged ? tr('Help is on the way') : tr('Organizer notified'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ),
              Pill(acknowledged ? tr('Acknowledged') : tr('Sent'), color: Colors.white),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tr('"{reason}" sent at {time} from {dist}.', {
              'reason': alert.reason,
              'time': fmtClock(sim.wallClockAt(alert.raceTimeS)),
              'dist': fmtDistance(d, Units.km),
            }),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            tr('Stay where you are if you can. Marshals and medics see your live location.'),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70, width: 1.5), minimumSize: const Size(0, 42)),
              onPressed: () => sim.updateSos(alert, 'closed'),
              icon: const Icon(Icons.thumb_up_alt_rounded, size: 18),
              label: Text(tr('I\'m OK now, cancel SOS')),
            ),
          ),
        ],
      ),
    );
  }
}
