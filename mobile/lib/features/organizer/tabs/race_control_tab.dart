import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/l10n/i18n.dart';
import '../../../core/theme.dart';
import '../../../data/models.dart';
import '../../../data/sim/race_sim.dart';
import '../../../services/weather_service.dart';
import '../../home/widgets/motion.dart';
import '../../home/widgets/weather_card.dart' show heatColor, heatLabel;
import '../field_ticker.dart';
import '../organizer_widgets.dart';

/// Gun, clocks, live field stats, finish rate, close race (F05).
class RaceControlTab extends StatelessWidget {
  const RaceControlTab({super.key, required this.ticker, required this.onOpenTab});
  final FieldTicker ticker;
  final void Function(int tab) onOpenTab;

  @override
  Widget build(BuildContext context) {
    final status = context.select<RaceSim, RaceStatus>((s) => s.status);
    return OrgTabList(
      children: [
        const _ClockCard(),
        if (status == RaceStatus.preRace) const _GunCard() else _LiveControls(onOpenTab: onOpenTab),
        _FieldCard(ticker: ticker),
        if (status != RaceStatus.preRace) _FinishRateCard(ticker: ticker),
        _AlertsRow(onOpenTab: onOpenTab),
      ],
    );
  }
}

class _ClockCard extends StatelessWidget {
  const _ClockCard();

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final status = context.select<RaceSim, RaceStatus>((s) => s.status);
    final official = context.select<RaceSim, bool>((s) => s.official);
    final (label, color) = switch (status) {
      RaceStatus.preRace => (tr('Pre-race'), RL.amber),
      RaceStatus.live => (tr('Live'), RL.red),
      RaceStatus.closed => (official ? tr('Official') : tr('Closed'), official ? RL.green : RL.slate),
    };
    const muted = Color(0xB3FFFFFF);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [RL.navy, Color(0xFF213F72)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Pill(label, color: color, filled: true, icon: status == RaceStatus.live ? Icons.circle : null),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${tr(sim.race.name)} · ${fmtDistance(sim.race.distanceM, Units.km)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ValueListenableBuilder<double>(
            valueListenable: sim.clock,
            builder: (_, t, _) => Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text((status == RaceStatus.preRace ? tr('Gun in') : tr('Race clock')).toUpperCase(),
                          style: const TextStyle(color: muted, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
                      SizedBox(
                        height: 48,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            fmtDuration(t.abs(), forceHours: true),
                            style: const TextStyle(color: Colors.white, fontSize: 42, height: 1, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()]),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(tr('Wall clock').toUpperCase(), style: const TextStyle(color: muted, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          fmtClockSec(sim.now),
                          style: const TextStyle(color: RL.amber, fontSize: 22, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()]),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            status == RaceStatus.preRace
                ? tr('Scheduled gun {time} · cutoff {cut}', {'time': fmtClock(sim.race.scheduledStart), 'cut': fmtDuration(sim.race.cutoffS)})
                : tr('Gun fired at {time} · cutoff {cut}', {'time': fmtClockSec(sim.gunWallClock), 'cut': fmtClock(sim.wallClockAt(sim.race.cutoffS.toDouble()))}),
            style: const TextStyle(color: muted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _GunCard extends StatefulWidget {
  const _GunCard();

  @override
  State<_GunCard> createState() => _GunCardState();
}

class _GunCardState extends State<_GunCard> with SingleTickerProviderStateMixin {
  // A few breaths of the ring, then it rests (so tests can settle).
  late final AnimationController _ring = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(count: 6);

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  Future<void> _fire() async {
    final sim = context.read<RaceSim>();
    final ok = await confirmAction(
      context,
      title: tr('Fire the gun?'),
      body: tr('This starts the race clock for the {race} and notifies {n} runners and everyone following them.', {'race': tr(sim.race.name), 'n': fmtInt(sim.participants.length)}),
      confirm: tr('Fire gun'),
      confirmKey: const Key('confirm-gun'),
    );
    if (ok && mounted) context.read<RaceSim>().fireGun();
  }

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    return RLCard(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
      child: Column(
        children: [
          SizedBox(
            width: 190,
            height: 190,
            child: AnimatedBuilder(
              animation: _ring,
              builder: (_, child) => Stack(
                alignment: Alignment.center,
                children: [
                  for (final phase in const [0.0, 0.5])
                    Builder(builder: (_) {
                      final v = (_ring.value + phase) % 1;
                      return Container(
                        width: 150 + 40 * v,
                        height: 150 + 40 * v,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: RL.amber.withValues(alpha: 0.22 * (1 - v))),
                      );
                    }),
                  child!,
                ],
              ),
              child: Material(
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                elevation: 8,
                shadowColor: RL.amber.withValues(alpha: 0.6),
                child: Ink(
                  width: 150,
                  height: 150,
                  decoration: const BoxDecoration(gradient: RadialGradient(colors: [Color(0xFFF6B347), RL.amber, Color(0xFFC77406)], stops: [0, 0.6, 1])),
                  child: InkWell(
                    key: const Key('gun-button'),
                    onTap: _fire,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.flag_rounded, color: Colors.white, size: 34),
                        Text(tr('GUN'), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 2)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(tr('Tap when the {race} starts', {'race': tr(sim.race.name)}), textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: ink(context))),
          const SizedBox(height: 4),
          Text(
            tr('Saves the gun time and broadcasts it. Net times start when each runner crosses the start line.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: muted(context), fontSize: 12.5, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _LiveControls extends StatelessWidget {
  const _LiveControls({required this.onOpenTab});
  final void Function(int tab) onOpenTab;

  @override
  Widget build(BuildContext context) {
    final sim = context.watch<RaceSim>();
    final live = sim.status == RaceStatus.live;
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(tr('Race control')),
          Row(
            children: [
              Icon(live ? (sim.playing ? Icons.play_circle_rounded : Icons.pause_circle_rounded) : Icons.lock_clock_rounded, color: live ? RL.green : RL.slate, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  live
                      ? (sim.playing ? tr('Race running · demo speed {x}×', {'x': sim.speed.round()}) : tr('Race running · demo clock paused'))
                      : (sim.official ? tr('Race closed · official results published') : tr('Race closed · results are provisional')),
                  style: TextStyle(fontWeight: FontWeight.w800, color: ink(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (live)
            OutlinedButton.icon(
              key: const Key('close-race'),
              style: OutlinedButton.styleFrom(foregroundColor: RL.red, side: BorderSide(color: RL.red.withValues(alpha: 0.5), width: 1.5)),
              onPressed: () async {
                final ok = await confirmAction(
                  context,
                  title: tr('Close the race?'),
                  body: tr('Runners still on course will be marked DNF and the results become provisional. Do this after the cutoff.'),
                  confirm: tr('Close race'),
                  color: RL.red,
                  icon: Icons.lock_clock_rounded,
                );
                if (ok && context.mounted) context.read<RaceSim>().closeRace();
              },
              icon: const Icon(Icons.lock_clock_rounded),
              label: Text(tr('Close race')),
            )
          else
            FilledButton.icon(
              onPressed: () => onOpenTab(4),
              icon: const Icon(Icons.emoji_events_rounded),
              label: Text(sim.official ? tr('View results') : tr('Import timing & publish')),
            ),
        ],
      ),
    );
  }
}

class _FieldCard extends StatelessWidget {
  const _FieldCard({required this.ticker});
  final FieldTicker ticker;

  @override
  Widget build(BuildContext context) {
    return RLCard(
      child: ListenableBuilder(
        listenable: ticker,
        builder: (context, _) {
          final s = ticker.snapshot;
          final total = s.total == 0 ? 1 : s.total;
          final parts = [(s.notStarted, RL.slate), (s.running, RL.teal), (s.finished, RL.green), (s.dnf, RL.red)];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionLabel(tr('Live field'), trailing: Text(tr('{n} runners', {'n': fmtInt(s.total)}), style: TextStyle(fontSize: 12, color: muted(context), fontWeight: FontWeight.w700))),
              Row(
                children: [
                  Expanded(child: OrgCountTile(value: s.notStarted, label: tr('Not started'), color: RL.slate, icon: Icons.hourglass_empty_rounded)),
                  const SizedBox(width: 10),
                  Expanded(child: OrgCountTile(value: s.running, label: tr('On course'), color: RL.teal, icon: Icons.directions_run_rounded)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: OrgCountTile(value: s.finished, label: tr('Finished'), color: RL.green, icon: Icons.sports_score_rounded)),
                  const SizedBox(width: 10),
                  Expanded(child: OrgCountTile(value: s.dnf, label: tr('DNF'), color: RL.red, icon: Icons.do_not_disturb_on_rounded)),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: SizedBox(
                  height: 10,
                  child: LayoutBuilder(
                    builder: (_, c) => Row(
                      children: [
                        for (final (n, color) in parts)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 600),
                            curve: Curves.easeOutCubic,
                            width: c.maxWidth * n / total,
                            color: color,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr('Updated every second from the timing feed'),
                style: TextStyle(fontSize: 11.5, color: muted(context)),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FinishRateCard extends StatelessWidget {
  const _FinishRateCard({required this.ticker});
  final FieldTicker ticker;

  @override
  Widget build(BuildContext context) {
    return RLCard(
      child: ListenableBuilder(
        listenable: ticker,
        builder: (context, _) {
          final s = ticker.snapshot;
          final rate = s.finishersPerMin;
          final now = rate.isEmpty ? 0 : rate.last;
          final peak = rate.isEmpty ? 0 : rate.reduce((a, b) => a > b ? a : b);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionLabel(tr('Finishers per minute'), trailing: Text(tr('last {n} min', {'n': FieldTicker.rateWindowMin}), style: TextStyle(fontSize: 12, color: muted(context)))),
              SparkBars(values: rate),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _Mini(value: now, label: tr('Now / min'), color: RL.green)),
                  Expanded(child: _Mini(value: peak, label: tr('Peak / min'), color: ink(context))),
                  Expanded(child: _Mini(value: s.finished, label: tr('Total finished'), color: ink(context))),
                ],
              ),
              if (s.finished == 0) ...[
                const SizedBox(height: 8),
                Text(tr('The first finishers usually arrive about 65 minutes after the gun.'), style: TextStyle(fontSize: 12, color: muted(context))),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.value, required this.label, required this.color});
  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(fit: BoxFit.scaleDown, child: CountUpText(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color))),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: muted(context))),
        ],
      );
}

class _AlertsRow extends StatelessWidget {
  const _AlertsRow({required this.onOpenTab});
  final void Function(int tab) onOpenTab;

  @override
  Widget build(BuildContext context) {
    final open = context.select<RaceSim, int>((s) => s.sosAlerts.where((a) => a.status == 'open').length);
    final weather = context.watch<WeatherService>().now;
    final risk = weather.risk;
    return Row(
      children: [
        Expanded(
          child: RLCard(
            padding: const EdgeInsets.all(12),
            onTap: () => onOpenTab(2),
            color: open > 0 ? RL.red.withValues(alpha: 0.08) : null,
            child: Row(
              children: [
                Icon(Icons.sos_rounded, color: open > 0 ? RL.red : muted(context)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    open == 0 ? tr('No open SOS') : tr('{n} open SOS', {'n': open}),
                    maxLines: 2,
                    style: TextStyle(fontWeight: FontWeight.w800, color: open > 0 ? RL.red : ink(context), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: RLCard(
            padding: const EdgeInsets.all(12),
            color: heatColor(risk).withValues(alpha: 0.08),
            child: Row(
              children: [
                Icon(Icons.thermostat_rounded, color: heatColor(risk)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('Heat {level} · {f}°', {'level': heatLabel(risk), 'f': weather.feelsLikeC.round()}),
                    maxLines: 2,
                    style: TextStyle(fontWeight: FontWeight.w800, color: heatColor(risk), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
