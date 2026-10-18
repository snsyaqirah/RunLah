import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/sim/race_sim.dart';
import '../../services/tracking_service.dart';
import 'run_widgets.dart';

enum _Check { checking, ok, warn, bad, info }

/// Pre-race check (PRD 8, runner event day): location permission set to
/// Always, battery above 50%, GPS lock. Runs when the card first becomes
/// visible; every plugin call is guarded and times out, so on web, desktop
/// and in tests it degrades to "not available" instead of failing.
class PreRaceCheckCard extends StatefulWidget {
  const PreRaceCheckCard({super.key});

  @override
  State<PreRaceCheckCard> createState() => _PreRaceCheckCardState();
}

class _PreRaceCheckCardState extends State<PreRaceCheckCard> {
  final _timers = <Timer>{};
  bool _started = false;

  LocationReadiness? _loc;
  int? _battery;
  bool _batteryDone = false;
  double? _gpsAccuracy;
  bool _gpsDone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && Visibility.of(context)) {
      _started = true;
      _runChecks();
    }
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  /// Runs [f] with a timeout whose timer dies with this widget.
  Future<T?> _guard<T>(Future<T> Function() f, Duration timeout) {
    final c = Completer<T?>();
    late final Timer timer;
    timer = Timer(timeout, () {
      _timers.remove(timer);
      if (!c.isCompleted) c.complete(null);
    });
    _timers.add(timer);
    () async {
      try {
        final v = await f();
        if (!c.isCompleted) c.complete(v);
      } catch (_) {
        if (!c.isCompleted) c.complete(null);
      } finally {
        timer.cancel();
        _timers.remove(timer);
      }
    }();
    return c.future;
  }

  Future<void> _runChecks({bool request = false}) async {
    final tracking = context.read<TrackingService>();
    setState(() {
      _loc = null;
      _gpsDone = false;
      _batteryDone = false;
    });
    final loc = await _guard(() => tracking.locationReadiness(request: request), Duration(seconds: request ? 60 : 6));
    if (!mounted) return;
    setState(() => _loc = loc ?? LocationReadiness.unsupported);

    final battery = await _guard(tracking.batteryLevel, const Duration(seconds: 4));
    if (!mounted) return;
    setState(() {
      _battery = battery;
      _batteryDone = true;
    });

    if (_loc == LocationReadiness.always || _loc == LocationReadiness.whileInUse) {
      final fix = await _guard(tracking.gpsFix, const Duration(seconds: 16));
      if (!mounted) return;
      setState(() {
        _gpsAccuracy = fix?.accuracy;
        _gpsDone = true;
      });
    } else {
      setState(() => _gpsDone = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = <(_Check, IconData, String, String, Widget?)>[
      _locationRow(context),
      _batteryRow(),
      _gpsRow(),
    ];
    final ready = rows.where((r) => r.$1 == _Check.ok || r.$1 == _Check.info).length;
    final checking = rows.any((r) => r.$1 == _Check.checking);
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(
            tr('Pre-race check'),
            trailing: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: checking
                  ? Pill(tr('Checking'), key: const ValueKey('c'), color: RL.slate)
                  : Pill(
                      tr('{n} of {total} ready', {'n': ready, 'total': rows.length}),
                      key: ValueKey(ready),
                      color: ready == rows.length ? RL.green : RL.amber,
                      icon: ready == rows.length ? Icons.check_rounded : Icons.priority_high_rounded,
                    ),
            ),
          ),
          for (final (i, r) in rows.indexed) ...[
            if (i > 0) const Divider(height: 18),
            _CheckRow(state: r.$1, icon: r.$2, title: r.$3, subtitle: r.$4, action: r.$5),
          ],
        ],
      ),
    );
  }

  (_Check, IconData, String, String, Widget?) _locationRow(BuildContext context) {
    final tracking = context.read<TrackingService>();
    Widget button(String label, VoidCallback onTap) => TextButton(onPressed: onTap, child: Text(label));
    return switch (_loc) {
      null => (_Check.checking, Icons.my_location_rounded, tr('Location permission'), tr('Checking…'), null),
      LocationReadiness.always => (_Check.ok, Icons.my_location_rounded, tr('Location: Always'), tr('Tracking keeps going with the screen off.'), null),
      LocationReadiness.whileInUse => (
          _Check.warn,
          Icons.my_location_rounded,
          tr('Location: While using'),
          kIsWeb ? tr('Keep this tab open while you run.') : tr('Set it to Always so tracking survives a locked screen.'),
          kIsWeb ? null : button(tr('Fix'), () => _runChecks(request: true)),
        ),
      LocationReadiness.denied => (_Check.bad, Icons.location_disabled_rounded, tr('Location is off for RunLah'), tr('Allow location so family can follow you live.'), button(tr('Allow'), () => _runChecks(request: true))),
      LocationReadiness.deniedForever => (
          _Check.bad,
          Icons.location_disabled_rounded,
          tr('Location blocked'),
          tr('Turn it on in Settings › RunLah › Location.'),
          button(tr('Settings'), tracking.openLocationSettings),
        ),
      LocationReadiness.serviceOff => (_Check.bad, Icons.location_off_rounded, tr('Location services are off'), tr('Turn on location in your phone settings.'), button(tr('Retry'), _runChecks)),
      LocationReadiness.unsupported => (_Check.info, Icons.my_location_rounded, tr('Location: demo mode'), tr('No GPS here, so the demo race moves you along the course.'), null),
    };
  }

  (_Check, IconData, String, String, Widget?) _batteryRow() {
    if (!_batteryDone) return (_Check.checking, Icons.battery_std_rounded, tr('Battery'), tr('Checking…'), null);
    final b = _battery;
    if (b == null) return (_Check.info, Icons.battery_unknown_rounded, tr('Battery level unknown'), tr('Aim for at least 50% before the gun.'), null);
    final ok = b >= 50;
    return (
      ok ? _Check.ok : _Check.warn,
      ok ? Icons.battery_full_rounded : Icons.battery_3_bar_rounded,
      tr('Battery {n}%', {'n': b}),
      ok ? tr('Enough for the whole race.') : tr('Below 50%. Charge up or turn on battery saver.'),
      null,
    );
  }

  (_Check, IconData, String, String, Widget?) _gpsRow() {
    if (!_gpsDone) return (_Check.checking, Icons.satellite_alt_rounded, tr('GPS lock'), tr('Searching for satellites…'), null);
    final loc = _loc;
    if (loc != LocationReadiness.always && loc != LocationReadiness.whileInUse) {
      return (_Check.info, Icons.satellite_alt_rounded, tr('GPS: simulated'), tr('Demo race: your position comes from the race simulator.'), null);
    }
    final acc = _gpsAccuracy;
    if (acc == null) return (_Check.warn, Icons.satellite_alt_rounded, tr('No GPS lock yet'), tr('Step away from tall buildings and wait a moment.'), TextButton(onPressed: _runChecks, child: Text(tr('Retry'))));
    return (
      acc <= 20 ? _Check.ok : _Check.warn,
      Icons.satellite_alt_rounded,
      tr('GPS locked ±{m} m', {'m': acc.round()}),
      acc <= 20 ? tr('Good signal.') : tr('Weak signal. It improves in open sky.'),
      null,
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.state, required this.icon, required this.title, required this.subtitle, this.action});
  final _Check state;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _Check.checking => RL.slate,
      _Check.ok => RL.green,
      _Check.warn => RL.amber,
      _Check.bad => RL.red,
      _Check.info => RL.teal,
    };
    final badge = switch (state) {
      _Check.checking => SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: color)),
      _Check.ok => Icon(Icons.check_circle_rounded, color: color, size: 22),
      _Check.warn => Icon(Icons.error_rounded, color: color, size: 22),
      _Check.bad => Icon(Icons.cancel_rounded, color: color, size: 22),
      _Check.info => Icon(Icons.info_rounded, color: color, size: 22),
    };
    return InfoRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      color: color,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [?action, AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: KeyedSubtree(key: ValueKey(state), child: badge))]),
    );
  }
}

/// Race-day settings: voice coach, cheers aloud, battery saver, privacy and
/// target time. All persist through [SettingsController].
class RunSettingsCard extends StatelessWidget {
  const RunSettingsCard({super.key, this.showTarget = true});
  final bool showTarget;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final sim = context.read<RaceSim>();
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(tr('Run settings')),
          if (showTarget) ...[
            _TargetRow(targetS: s.targetTimeS, distanceM: sim.race.distanceM, units: s.units),
            const Divider(height: 18),
          ],
          ToggleRow(
            icon: Icons.record_voice_over_rounded,
            title: tr('Voice coach'),
            subtitle: tr('Splits and projected finish read out every km.'),
            value: s.voiceCoach,
            onChanged: (v) => s.voiceCoach = v,
          ),
          ToggleRow(
            icon: Icons.campaign_rounded,
            color: const Color(0xFFEC4899),
            title: tr('Read cheers aloud'),
            subtitle: tr('Hear messages from friends while you run.'),
            value: s.readCheers,
            onChanged: (v) => s.readCheers = v,
          ),
          ToggleRow(
            icon: Icons.battery_saver_rounded,
            color: RL.green,
            title: tr('Battery saver'),
            subtitle: s.batterySaver ? tr('GPS every 15 s. About 6% battery per hour.') : tr('GPS every 5 s. About 10% battery per hour.'),
            value: s.batterySaver,
            onChanged: (v) => s.batterySaver = v,
          ),
          const SizedBox(height: 10),
          Text(tr('Who can follow you live'), style: TextStyle(fontWeight: FontWeight.w800, color: ink(context))),
          const SizedBox(height: 8),
          PrivacySelector(value: s.privacy, onChanged: (p) => s.privacy = p),
        ],
      ),
    );
  }
}

class _TargetRow extends StatelessWidget {
  const _TargetRow({required this.targetS, required this.distanceM, required this.units});
  final int targetS;
  final double distanceM;
  final Units units;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showTargetPicker(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: InfoRow(
          icon: Icons.flag_circle_rounded,
          color: RL.amber,
          title: tr('Target {time}', {'time': fmtDuration(targetS)}),
          subtitle: tr('{pace} average. Alerts if your projection slips behind.', {'pace': fmtPace(targetS / (distanceM / 1000), units)}),
          trailing: Icon(Icons.edit_rounded, size: 18, color: muted(context)),
        ),
      ),
    );
  }
}

/// Bottom sheet to pick the target time (presets + ±1 min).
Future<void> showTargetPicker(BuildContext context) => showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _TargetSheet(),
    );

class _TargetSheet extends StatelessWidget {
  const _TargetSheet();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final dist = context.read<RaceSim>().race.distanceM;
    const presets = [5400, 6000, 6300, 7200, 8100, 9000];
    final t = s.targetTimeS;
    void set(int v) => s.targetTimeS = v.clamp(3600, 4 * 3600 + 30 * 60);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Target time'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink(context))),
            const SizedBox(height: 4),
            Text(tr('Half marathon, 21.1 km'), style: TextStyle(color: muted(context))),
            const SizedBox(height: 16),
            Row(
              children: [
                IconButton.filledTonal(onPressed: () => set(t - 60), icon: const Icon(Icons.remove_rounded)),
                Expanded(
                  child: Column(
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          fmtDuration(t, forceHours: true),
                          style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: ink(context), fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                      ),
                      Text(fmtPace(t / (dist / 1000), s.units), style: TextStyle(color: muted(context), fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                IconButton.filledTonal(onPressed: () => set(t + 60), icon: const Icon(Icons.add_rounded)),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final p in presets)
                  ChoiceChip(
                    label: Text(tr('Sub {time}', {'time': fmtDuration(p)})),
                    selected: t == p,
                    onSelected: (_) => set(p),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Done'))),
          ],
        ),
      ),
    );
  }
}
