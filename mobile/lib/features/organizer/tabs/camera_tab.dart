import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/l10n/i18n.dart';
import '../../../core/theme.dart';
import '../../../data/app_state.dart';
import '../../../data/models.dart';
import '../../../data/sim/race_sim.dart';
import '../../home/home_data.dart';
import '../../home/widgets/motion.dart';
import '../ocr/bib_scanner.dart';
import '../organizer_session.dart';

/// Checkpoint camera (F31): camera + OCR on device, keypad fallback,
/// review queue for doubtful reads, and the recent reads at a checkpoint.
class CameraTab extends StatefulWidget {
  const CameraTab({super.key});

  @override
  State<CameraTab> createState() => _CameraTabState();
}

class _Flash {
  const _Flash(this.id, this.bib, this.confidence, this.recorded, this.name);
  final int id;
  final String bib;
  final double confidence;
  final bool recorded;
  final String? name;
}

class _CameraTabState extends State<CameraTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final BibScanner _scanner = BibScanner.create();
  final Map<String, DateTime> _seen = {};
  _Flash? _flash;
  int _flashId = 0;

  // Keypad
  String _entry = '';
  String? _padMsg;
  bool _padError = false;
  int _shake = 0;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  OrganizerSession get _session => context.read<OrganizerSession>();

  void _submitOcr(String bib, double confidence) {
    final read = _session.submitOcr(bib, confidence);
    final p = context.read<RaceSim>().byBib(bib);
    setState(() => _flash = _Flash(++_flashId, bib, confidence, read != null, p?.name));
  }

  void _onCameraHits(List<OcrHit> hits) {
    if (!mounted) return;
    final now = DateTime.now();
    for (final h in hits.take(3)) {
      final key = '${h.bib}@${_session.checkpoint}';
      final last = _seen[key];
      if (last != null && now.difference(last) < const Duration(seconds: 20)) continue;
      _seen[key] = now;
      _submitOcr(h.bib, h.confidence);
    }
  }

  void _simulate() {
    final sim = context.read<RaceSim>();
    final r = _session.simulateCameraRead(_session.checkpoint);
    if (r == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(sim.status == RaceStatus.preRace
            ? tr('Nobody is on the course yet. Fire the gun first.')
            : tr('No runners near {cp} right now. Pick another checkpoint or move the race clock.', {'cp': sim.race.checkpoints[_session.checkpoint].name})),
      ));
      return;
    }
    _submitOcr(r.bib, r.confidence);
  }

  void _press(String k) {
    setState(() {
      _padMsg = null;
      if (k == '⌫') {
        if (_entry.isNotEmpty) _entry = _entry.substring(0, _entry.length - 1);
      } else if (_entry.length < 6) {
        _entry += k;
      }
    });
  }

  void _recordManual() {
    if (_entry.isEmpty) return;
    final sim = context.read<RaceSim>();
    final cp = sim.race.checkpoints[_session.checkpoint];
    final p = sim.byBib(_entry);
    setState(() {
      if (p == null) {
        _padError = true;
        _padMsg = tr('Bib {bib} is not on the start list', {'bib': _entry});
        _shake++;
      } else {
        sim.recordRead(_entry, cp.index, source: PassSource.manual, confidence: 1);
        _padError = false;
        _padMsg = tr('{bib} {name} recorded at {cp}', {'bib': _entry, 'name': p.firstName, 'cp': cpLabel(cp)});
        _entry = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final children = <Widget>[
      _checkpointPicker(context),
      _viewport(context),
      _keypad(context),
      const _ReviewQueue(),
      const _RecentReads(),
    ];
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (_, i) => FadeSlideIn(index: i, child: children[i]),
    );
  }

  Widget _checkpointPicker(BuildContext context) {
    final sim = context.read<RaceSim>();
    final session = context.watch<OrganizerSession>();
    final units = context.select<SettingsController, Units>((s) => s.units);
    final cp = sim.race.checkpoints[session.checkpoint];
    final reads = context.select<RaceSim, int>((s) => s.staffReads.where((r) => r.checkpointIndex == session.checkpoint).length);
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(tr('Checkpoint')),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: sim.race.checkpoints.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final c = sim.race.checkpoints[i];
                return ChoiceChip(
                  label: Text(cpLabel(c)),
                  selected: session.checkpoint == i,
                  onSelected: (_) => session.setCheckpoint(i),
                  selectedColor: RL.amber.withValues(alpha: 0.22),
                  labelStyle: TextStyle(fontWeight: FontWeight.w800, color: ink(context)),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.place_rounded, color: RL.amber, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${cp.name} · ${fmtDistance(cp.distanceM, units)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800, color: ink(context)),
                ),
              ),
              Text(tr('{n} reads', {'n': fmtInt(reads)}), style: TextStyle(color: muted(context), fontSize: 12.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _viewport(BuildContext context) {
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(tr('Bib camera')),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 11,
              child: ValueListenableBuilder<ScannerPhase>(
                valueListenable: _scanner.phase,
                builder: (context, phase, _) => Stack(
                  fit: StackFit.expand,
                  children: [
                    if (phase == ScannerPhase.running)
                      FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: SizedBox(width: 300, height: 400, child: _scanner.preview()))
                    else
                      _Placeholder(phase: phase, available: _scanner.available, error: _scanner.error),
                    const IgnorePointer(child: CustomPaint(painter: _FramePainter())),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (c, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(a), child: c)),
                        child: _flash == null ? const SizedBox.shrink() : _FlashChip(key: ValueKey(_flash!.id), flash: _flash!),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const Key('simulate-read'),
                  onPressed: _simulate,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: 10)),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 20),
                  label: Text(tr('Simulate a camera read'), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              if (_scanner.available) ...[
                const SizedBox(width: 10),
                ValueListenableBuilder<ScannerPhase>(
                  valueListenable: _scanner.phase,
                  builder: (_, phase, _) => IconButton.filled(
                    tooltip: phase == ScannerPhase.running ? tr('Stop camera') : tr('Open camera'),
                    style: IconButton.styleFrom(backgroundColor: RL.navy, minimumSize: const Size(48, 48)),
                    onPressed: phase == ScannerPhase.starting
                        ? null
                        : () => phase == ScannerPhase.running ? _scanner.stop() : _scanner.start(_onCameraHits),
                    icon: Icon(phase == ScannerPhase.running ? Icons.stop_rounded : Icons.photo_camera_rounded, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tr('Reads at {pct}% confidence or more are recorded straight away; the rest wait for a marshal below.', {'pct': (kOcrAcceptConfidence * 100).round()}),
            style: TextStyle(fontSize: 12, color: muted(context), height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _keypad(BuildContext context) {
    final cp = context.read<RaceSim>().race.checkpoints[context.select<OrganizerSession, int>((s) => s.checkpoint)];
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '⌫', '0', '✓'];
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(tr('Manual entry')),
          Shake(
            trigger: _shake,
            child: Container(
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0B1220) : RL.bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _padError ? RL.red : Colors.transparent, width: 1.5),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _entry.isEmpty ? tr('Bib number') : _entry,
                  style: TextStyle(
                    fontSize: _entry.isEmpty ? 18 : 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: _entry.isEmpty ? 0 : 3,
                    color: _entry.isEmpty ? muted(context) : ink(context),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _padMsg == null
                ? const SizedBox(height: 8, width: double.infinity)
                : Padding(
                    key: ValueKey(_padMsg),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(_padError ? Icons.error_outline_rounded : Icons.check_circle_rounded, size: 18, color: _padError ? RL.red : RL.green),
                        const SizedBox(width: 6),
                        Expanded(child: Text(_padMsg!, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _padError ? RL.red : RL.green))),
                      ],
                    ),
                  ),
          ),
          for (var r = 0; r < 4; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  for (var c = 0; c < 3; c++) ...[
                    Expanded(child: _Key(label: keys[r * 3 + c], onTap: () => keys[r * 3 + c] == '✓' ? _recordManual() : _press(keys[r * 3 + c]))),
                    if (c < 2) const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          Text(tr('Records a manual pass at {cp}.', {'cp': '${cp.name} (${cpLabel(cp)})'}), style: TextStyle(fontSize: 12, color: muted(context))),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accept = label == '✓';
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: accept ? RL.amber : (dark ? const Color(0xFF1F2937) : RL.bg),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: Key(accept ? 'pad-record' : 'pad-$label'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Center(
            child: label == '⌫'
                ? Icon(Icons.backspace_outlined, color: ink(context), size: 20)
                : accept
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 24)
                    : Text(label, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink(context))),
          ),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.phase, required this.available, required this.error});
  final ScannerPhase phase;
  final bool available;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final text = switch (phase) {
      ScannerPhase.starting => tr('Starting camera…'),
      ScannerPhase.error => tr('Camera unavailable: {e}', {'e': error ?? '?'}),
      _ => available
          ? tr('Tap the camera button and point it at the runners\' bibs.')
          : (kIsWeb ? tr('Camera OCR runs in the Android and iOS app. Use the keypad or simulate a read here.') : tr('No camera OCR on this device. Use the keypad or simulate a read.')),
    };
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0B1220), RL.navy], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 56),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            phase == ScannerPhase.starting
                ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: RL.amber))
                : Icon(phase == ScannerPhase.error ? Icons.no_photography_rounded : Icons.document_scanner_rounded, color: Colors.white54, size: 34),
            const SizedBox(height: 10),
            Flexible(
              child: Text(text, textAlign: TextAlign.center, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.3)),
            ),
          ],
        ),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  const _FramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromCenter(center: size.center(Offset.zero).translate(0, -14), width: size.width * 0.62, height: size.height * 0.42);
    final p = Paint()
      ..color = RL.amber
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const l = 18.0;
    for (final (o, dx, dy) in [(r.topLeft, 1.0, 1.0), (r.topRight, -1.0, 1.0), (r.bottomLeft, 1.0, -1.0), (r.bottomRight, -1.0, -1.0)]) {
      canvas.drawLine(o, o.translate(l * dx, 0), p);
      canvas.drawLine(o, o.translate(0, l * dy), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FlashChip extends StatelessWidget {
  const _FlashChip({super.key, required this.flash});
  final _Flash flash;

  @override
  Widget build(BuildContext context) {
    final color = flash.recorded ? RL.green : RL.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(14), border: Border.all(color: color, width: 1.5)),
      child: Row(
        children: [
          Text(flash.bib, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  flash.recorded ? tr('Recorded · {pct}%', {'pct': (flash.confidence * 100).round()}) : tr('To review · {pct}%', {'pct': (flash.confidence * 100).round()}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12.5),
                ),
                Text(flash.name ?? tr('Not in start list'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewQueue extends StatelessWidget {
  const _ReviewQueue();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<OrganizerSession>();
    final sim = context.read<RaceSim>();
    final items = session.review;
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(
            tr('Review queue'),
            trailing: items.isEmpty ? null : Pill('${items.length}', color: RL.amber, filled: true),
          ),
          if (items.isEmpty)
            Text(tr('Nothing to review. Low-confidence reads and unknown bibs land here.'), style: TextStyle(color: muted(context), fontSize: 13))
          else
            for (final item in items.take(8))
              Padding(
                key: ObjectKey(item),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: FadeSlideIn(child: _ReviewRow(item: item, sim: sim, session: session)),
              ),
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.item, required this.sim, required this.session});
  final ReviewItem item;
  final RaceSim sim;
  final OrganizerSession session;

  @override
  Widget build(BuildContext context) {
    final p = sim.byBib(item.bib);
    final unknown = item.reason == ReviewReason.notInStartList;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: (unknown ? RL.red : RL.amber).withValues(alpha: 0.13), borderRadius: BorderRadius.circular(12)),
          child: Icon(unknown ? Icons.help_outline_rounded : Icons.blur_on_rounded, color: unknown ? RL.red : RL.amber, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item.bib} · ${p?.firstName ?? tr('Not in start list')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w900, color: ink(context)),
              ),
              Text(
                tr('{pct}% · {cp} · {time}', {
                  'pct': (item.confidence * 100).round(),
                  'cp': cpLabel(sim.race.checkpoints[item.checkpointIndex]),
                  'time': fmtClockSec(sim.wallClockAt(item.raceTimeS)),
                }),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: muted(context)),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: unknown ? tr('Correct bib') : tr('Confirm'),
          onPressed: () => unknown ? _correct(context) : session.confirm(item),
          icon: Icon(unknown ? Icons.edit_rounded : Icons.check_circle_rounded, color: RL.green),
        ),
        IconButton(
          tooltip: tr('Reject'),
          onPressed: () => session.reject(item),
          icon: const Icon(Icons.cancel_rounded, color: RL.red),
        ),
      ],
    );
  }

  Future<void> _correct(BuildContext context) async {
    final controller = TextEditingController(text: item.bib);
    String? err;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(tr('Correct bib')),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: tr('Bib number'), errorText: err),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
            FilledButton(
              onPressed: () {
                if (session.confirm(item, correctedBib: controller.text)) {
                  Navigator.pop(ctx);
                } else {
                  setLocal(() => err = tr('Bib {bib} is not on the start list', {'bib': controller.text.trim()}));
                }
              },
              child: Text(tr('Save')),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }
}

class _RecentReads extends StatelessWidget {
  const _RecentReads();

  @override
  Widget build(BuildContext context) {
    final sim = context.watch<RaceSim>();
    final reads = sim.staffReads.take(15).toList();
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(tr('Recent reads'), trailing: Text(tr('{n} total', {'n': fmtInt(sim.staffReads.length)}), style: TextStyle(fontSize: 12, color: muted(context)))),
          if (reads.isEmpty)
            Text(tr('No reads yet at any checkpoint.'), style: TextStyle(color: muted(context), fontSize: 13))
          else
            for (final r in reads)
              Padding(
                key: ObjectKey(r),
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: FadeSlideIn(child: _ReadRow(read: r, sim: sim)),
              ),
        ],
      ),
    );
  }
}

class _ReadRow extends StatelessWidget {
  const _ReadRow({required this.read, required this.sim});
  final StaffRead read;
  final RaceSim sim;

  @override
  Widget build(BuildContext context) {
    final ocr = read.source == PassSource.ocr;
    final p = read.participantId == null ? null : sim.participant(read.participantId!);
    final conf = read.confidence;
    final confColor = conf >= kOcrAcceptConfidence ? RL.green : RL.amber;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: (ocr ? RL.teal : RL.navy).withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(ocr ? Icons.photo_camera_rounded : Icons.keyboard_rounded, size: 18, color: ocr ? RL.teal : ink(context)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${read.bib} · ${p?.displayName ?? tr('Not in start list')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: ink(context))),
              Text(
                '${ocr ? tr('Camera') : tr('Manual')} · ${cpLabel(sim.race.checkpoints[read.checkpointIndex])} · ${fmtClockSec(sim.wallClockAt(read.raceTimeS))}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: muted(context)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Pill('${(conf * 100).round()}%', color: confColor),
      ],
    );
  }
}
