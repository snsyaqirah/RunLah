import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../services/tracking_service.dart';
import 'activity_detail_screen.dart';
import 'glance_mode.dart';
import 'run_widgets.dart';

/// The "Free run" half of the Run tab (PRD F07–F10): start → share link
/// with family → stop → personal stats. No ranking, no Insights.
class FreeRunView extends StatelessWidget {
  const FreeRunView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.select<TrackingService, TrackingState>((t) => t.state);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOutCubic,
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous.map((w) => Positioned(left: 0, right: 0, top: 0, child: w)), ?current]),
      child: switch (state) {
        TrackingState.idle => const _Idle(key: ValueKey('idle')),
        TrackingState.starting => const _Starting(key: ValueKey('starting')),
        TrackingState.running || TrackingState.paused => const _Live(key: ValueKey('live')),
      },
    );
  }
}

// -------------------------------------------------------------------- idle

class _Idle extends StatelessWidget {
  const _Idle({super.key});

  @override
  Widget build(BuildContext context) {
    final tracking = context.watch<TrackingService>();
    final s = context.watch<SettingsController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FadeSlideIn(
          index: 0,
          child: HeroPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.route_rounded, color: RL.amber),
                    const SizedBox(width: 8),
                    Expanded(child: Text(tr('Free run'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
                    _WhiteChip(privacyStyle(s.privacy).$1, privacyStyle(s.privacy).$2),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  tr('No bib, no ranking. Just you, a live link for family, and your splits.'),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 22),
                const Center(child: _StartButton()),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    children: [
                      Icon(tracking.preferSimulated ? Icons.smart_toy_rounded : Icons.satellite_alt_rounded, color: RL.amber, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tracking.preferSimulated ? tr('Simulated GPS') : tr('Phone GPS'),
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              tracking.preferSimulated
                                  ? tr('Demo jog around KLCC Park at about 6:00/km.')
                                  : tr('A fix every {n} s, also with the screen off.', {'n': s.gpsIntervalS}),
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: tracking.preferSimulated,
                        activeTrackColor: RL.amber,
                        onChanged: (v) => tracking.preferSimulated = v,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const FadeSlideIn(index: 1, child: _QueueBanner()),
        FadeSlideIn(
          index: 2,
          child: RLCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionLabel(tr('Before you go')),
                ToggleRow(
                  icon: Icons.battery_saver_rounded,
                  color: RL.green,
                  title: tr('Battery saver'),
                  subtitle: s.batterySaver ? tr('GPS every 15 s. About 6% battery per hour.') : tr('GPS every 5 s. About 10% battery per hour.'),
                  value: s.batterySaver,
                  onChanged: (v) => s.batterySaver = v,
                ),
                ToggleRow(
                  icon: Icons.record_voice_over_rounded,
                  title: tr('Voice coach'),
                  subtitle: tr('Hear each kilometre split.'),
                  value: s.voiceCoach,
                  onChanged: (v) => s.voiceCoach = v,
                ),
                const SizedBox(height: 10),
                Text(tr('Who can follow you live'), style: TextStyle(fontWeight: FontWeight.w800, color: ink(context))),
                const SizedBox(height: 8),
                PrivacySelector(value: s.privacy, onChanged: (p) => s.privacy = p),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _WhiteChip extends StatelessWidget {
  const _WhiteChip(this.label, this.icon);
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
          ],
        ),
      );
}

class _StartButton extends StatefulWidget {
  const _StartButton();

  @override
  State<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<_StartButton> with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, child) => Container(
        width: 132,
        height: 132,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: RL.amber.withValues(alpha: 0.25 + 0.25 * _glow.value), blurRadius: 18 + 18 * _glow.value, spreadRadius: 2 + 6 * _glow.value)],
        ),
        child: child,
      ),
      child: Material(
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(gradient: RadialGradient(colors: [Color(0xFFF5B342), RL.amber])),
          child: InkWell(
            onTap: () => context.read<TrackingService>().start(),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 44),
                  FittedBox(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(tr('START'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 2)),
                    ),
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

class _Starting extends StatelessWidget {
  const _Starting({super.key});

  @override
  Widget build(BuildContext context) {
    return HeroPanel(
      child: SizedBox(
        height: 180,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: RL.amber),
            const SizedBox(height: 16),
            Text(tr('Getting a GPS fix…'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text(tr('Allow location when asked so family can follow you.'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            TextButton(onPressed: () => context.read<TrackingService>().discard(), child: Text(tr('Cancel'), style: const TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
  }
}

/// "N points queued, will upload when online" (PRD F09).
class _QueueBanner extends StatelessWidget {
  const _QueueBanner();

  @override
  Widget build(BuildContext context) {
    final tracking = context.read<TrackingService>();
    return ValueListenableBuilder<int>(
      valueListenable: tracking.queued,
      builder: (context, q, _) {
        if (q == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: RLCard(
            color: RL.amber.withValues(alpha: 0.12),
            child: InfoRow(
              icon: Icons.cloud_upload_rounded,
              color: RL.amber,
              title: tr('{n} points waiting to upload', {'n': fmtInt(q)}),
              subtitle: tr('Saved on this phone. They upload in batches when you\'re online.'),
              trailing: TextButton(onPressed: tracking.flush, child: Text(tr('Upload'))),
            ),
          ),
        );
      },
    );
  }
}

// -------------------------------------------------------------------- live

class _Live extends StatelessWidget {
  const _Live({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<TrackingService>();
    final s = context.watch<SettingsController>();
    final units = s.units;
    final paused = t.state == TrackingState.paused;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FadeSlideIn(
          index: 0,
          child: SizedBox(
            height: 250,
            child: Stack(
              children: [
                Positioned.fill(
                  child: TrackMap(points: [for (final p in t.track) p.latLng], follow: true, live: !paused),
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  right: 10,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _MapChip(
                        icon: t.simulated ? Icons.smart_toy_rounded : Icons.satellite_alt_rounded,
                        label: t.simulated
                            ? tr('Simulated GPS')
                            : t.weakSignal
                                ? tr('Weak GPS')
                                : tr('GPS ±{m} m', {'m': t.track.isEmpty ? '–' : t.track.last.acc.round()}),
                        color: t.weakSignal ? RL.red : RL.green,
                      ),
                      if (paused) _MapChip(icon: Icons.pause_rounded, label: tr('Paused'), color: RL.amber),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FadeSlideIn(
          index: 1,
          child: HeroPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    LiveDot(color: paused ? RL.amber : const Color(0xFF34D399)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        paused ? tr('PAUSED') : tr('FREE RUN · RECORDING'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 11.5, letterSpacing: 1),
                      ),
                    ),
                    IconButton(
                      tooltip: tr('Glance mode'),
                      onPressed: () => _openGlance(context, t, units),
                      icon: const Icon(Icons.fullscreen_rounded, color: Colors.white),
                    ),
                  ],
                ),
                Metric(value: fmtDuration(t.movingS, forceHours: true), label: tr('Moving time'), size: 56, color: Colors.white, labelColor: Colors.white60),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Metric(
                        value: fmtDistance(t.distanceM, units, decimals: 2, withUnit: false),
                        unit: distUnit(units),
                        label: tr('Distance'),
                        size: 24,
                        color: Colors.white,
                        labelColor: Colors.white60,
                      ),
                    ),
                    Expanded(
                      child: Metric(
                        value: fmtPace(t.currentPaceSPerKm, units, withUnit: false),
                        unit: paceUnit(units),
                        label: tr('Current pace'),
                        size: 24,
                        color: RL.amber,
                        labelColor: Colors.white60,
                      ),
                    ),
                    Expanded(
                      child: Metric(
                        value: fmtPace(t.avgPaceSPerKm, units, withUnit: false),
                        unit: paceUnit(units),
                        label: tr('Avg pace'),
                        size: 24,
                        color: Colors.white,
                        labelColor: Colors.white60,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _RoundButton(
                      icon: Icons.stop_rounded,
                      label: tr('Finish'),
                      color: RL.red,
                      size: 60,
                      onTap: () => _confirmStop(context),
                    ),
                    const SizedBox(width: 22),
                    _RoundButton(
                      icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      label: paused ? tr('Resume') : tr('Pause'),
                      color: RL.amber,
                      size: 76,
                      onTap: paused ? t.resume : t.pause,
                    ),
                  ],
                ),
                if (t.simulated) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: Text(tr('Demo speed'), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12.5))),
                      for (final x in TrackingService.simSpeeds)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: ChoiceChip(
                            label: Text('${x.round()}×'),
                            selected: t.simSpeed == x,
                            onSelected: (_) => t.simSpeed = x,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ],
                  ),
                ],
                if (t.sourceNote != null) ...[
                  const SizedBox(height: 10),
                  Text(t.sourceNote!, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const FadeSlideIn(index: 2, child: _UploadCard()),
        const SizedBox(height: 12),
        FadeSlideIn(
          index: 3,
          child: ShareLinkCard(url: t.shareUrl, privacy: s.privacy, onPrivacy: (p) => s.privacy = p),
        ),
        const SizedBox(height: 12),
        FadeSlideIn(
          index: 4,
          child: RLCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionLabel(tr('Km splits')),
                KmSplitsList(splitsS: t.splitsS, units: units, maxRows: 6),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static void _openGlance(BuildContext context, TrackingService t, Units units) {
    GlanceModeScreen.open(
      context,
      listenable: t,
      hero: () => GlanceMetric(fmtDuration(t.movingS, forceHours: true), tr('Moving time')),
      metrics: () => [
        GlanceMetric(fmtDistance(t.distanceM, units, decimals: 2, withUnit: false), tr('Distance ({unit})', {'unit': distUnit(units)})),
        GlanceMetric(fmtPace(t.currentPaceSPerKm, units, withUnit: false), tr('Pace {unit}', {'unit': paceUnit(units)}), color: RL.amber),
        GlanceMetric(fmtPace(t.avgPaceSPerKm, units, withUnit: false), tr('Avg pace')),
        GlanceMetric('${t.splitsS.length}', tr('Km done')),
      ],
      footer: () => t.state == TrackingState.paused ? tr('Paused') : '',
    );
  }

  static Future<void> _confirmStop(BuildContext context) async {
    final t = context.read<TrackingService>();
    final units = context.read<SettingsController>().units;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Finish this run?')),
        content: Text(tr('{dist} in {time}.', {'dist': fmtDistance(t.distanceM, units, decimals: 2), 'time': fmtDuration(t.movingS)})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), style: TextButton.styleFrom(foregroundColor: RL.red), child: Text(tr('Discard'))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Keep going'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), style: FilledButton.styleFrom(minimumSize: const Size(64, 44)), child: Text(tr('Save'))),
        ],
      ),
    );
    if (!context.mounted) return;
    if (choice == 'discard') {
      t.discard();
    } else if (choice == 'save') {
      final a = t.stop();
      if (a != null && context.mounted) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ActivityDetailScreen(activityId: a.id, justFinished: true)));
      }
    }
  }
}

class _MapChip extends StatelessWidget {
  const _MapChip({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: RL.navy.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
          ],
        ),
      );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.color, required this.size, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: color,
            shape: const CircleBorder(),
            elevation: 4,
            shadowColor: color.withValues(alpha: 0.5),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(width: size, height: size, child: Icon(icon, color: Colors.white, size: size * 0.5)),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      );
}

/// Upload status and the demo "no signal" switch (PRD F09 offline queue).
class _UploadCard extends StatelessWidget {
  const _UploadCard();

  @override
  Widget build(BuildContext context) {
    final t = context.watch<TrackingService>();
    final online = t.online;
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(
            tr('Live upload'),
            trailing: Pill(online ? tr('Online') : tr('Offline'), color: online ? RL.green : RL.red, icon: online ? Icons.wifi_rounded : Icons.wifi_off_rounded),
          ),
          ValueListenableBuilder<int>(
            valueListenable: t.queued,
            builder: (context, q, _) => InfoRow(
              icon: q == 0 ? Icons.cloud_done_rounded : (online ? Icons.cloud_upload_rounded : Icons.cloud_off_rounded),
              color: q == 0 ? RL.green : (online ? RL.teal : RL.amber),
              title: q == 0
                  ? tr('All points uploaded')
                  : online
                      ? tr('{n} points in the next batch', {'n': fmtInt(q)})
                      : tr('{n} points queued, will upload when online', {'n': fmtInt(q)}),
              subtitle: t.uploadedBatches == 0
                  ? tr('Batches of up to 500 points every 15 s to {server}.', {'server': t.sink.label})
                  : tr('{n} points sent in {b} batches to {server}, last at {time}.', {
                      'n': fmtInt(t.uploadedPoints),
                      'b': t.uploadedBatches,
                      'server': t.sink.label,
                      'time': t.lastUploadAt == null ? '–' : fmtClockSec(t.lastUploadAt!),
                    }),
              trailing: t.uploading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
            ),
          ),
          if (t.lastUploadError != null) ...[
            const SizedBox(height: 6),
            Text(tr('Last upload failed. Points stay queued and retry automatically.'), style: const TextStyle(color: RL.red, fontSize: 12)),
          ],
          const SizedBox(height: 4),
          ToggleRow(
            icon: Icons.signal_cellular_connected_no_internet_0_bar_rounded,
            color: RL.red,
            title: tr('Simulate no signal'),
            subtitle: tr('Demo: points pile up on the phone, then upload in order when the signal is back.'),
            value: t.simulateOffline,
            onChanged: (v) => t.simulateOffline = v,
          ),
        ],
      ),
    );
  }
}
