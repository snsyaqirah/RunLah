import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/l10n/i18n.dart';
import '../../../core/nav.dart';
import '../../../core/theme.dart';
import '../../../data/app_state.dart';
import '../../../data/models.dart';
import '../../../data/sim/race_sim.dart';
import '../../organizer/field_ticker.dart';
import '../home_data.dart';
import 'motion.dart';
import 'route_painter.dart';

const _heroText = Colors.white;
const _heroMuted = Color(0xB3FFFFFF);

/// Race-day hero: countdown before the gun, live clock and field while the
/// race is on, your result once it's closed.
class RaceHeroCard extends StatelessWidget {
  const RaceHeroCard({super.key, required this.ticker});
  final FieldTicker ticker;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final status = context.select<RaceSim, RaceStatus>((s) => s.status);
    final race = sim.race;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [RL.navy, Color(0xFF213F72)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: RL.navy.withValues(alpha: 0.28), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -36,
            top: -18,
            width: 220,
            height: 220,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.2,
                child: status == RaceStatus.live
                    ? ValueListenableBuilder<double>(
                        valueListenable: sim.clock,
                        builder: (_, t, _) => RouteSilhouette(route: race.route, strokeWidth: 3, glow: true, progress: sim.distanceAt(sim.youId, t)),
                      )
                    : RouteSilhouette(route: race.route, strokeWidth: 3, glow: true),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sim.event.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _heroMuted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  '${tr(race.name)} · ${fmtDistance(race.distanceM, Units.km)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _heroText, fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                AnimatedSize(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 450),
                    switchInCurve: Curves.easeOutCubic,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(a), child: child),
                    ),
                    layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
                    child: switch (status) {
                      RaceStatus.preRace => const _PreRace(key: ValueKey('pre')),
                      RaceStatus.live => _Live(key: const ValueKey('live'), ticker: ticker),
                      RaceStatus.closed => const _Closed(key: ValueKey('closed')),
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BigClock extends StatelessWidget {
  const _BigClock({required this.label, required this.builder});
  final String label;
  final String Function(double t) builder;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(color: _heroMuted, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        SizedBox(
          height: 54,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: ValueListenableBuilder<double>(
              valueListenable: sim.clock,
              builder: (_, t, _) => Text(
                builder(t),
                style: const TextStyle(color: _heroText, fontSize: 48, fontWeight: FontWeight.w900, height: 1, letterSpacing: -1, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroButtons extends StatelessWidget {
  const _HeroButtons({required this.primary, required this.secondary});
  final (String, IconData, VoidCallback) primary;
  final (String, IconData, VoidCallback) secondary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: primary.$3,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 46), padding: const EdgeInsets.symmetric(horizontal: 10)),
            icon: Icon(primary.$2, size: 18),
            label: Text(primary.$1, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: secondary.$3,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 46),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              side: const BorderSide(color: Color(0x55FFFFFF), width: 1.5),
            ),
            icon: Icon(secondary.$2, size: 18),
            label: Text(secondary.$1, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- pre-race

class _PreRace extends StatelessWidget {
  const _PreRace({super.key});

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Pill(tr('Race day'), color: RL.amber, filled: true, icon: Icons.bolt_rounded),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                tr('Gun {time} · {place}', {'time': fmtClock(sim.race.scheduledStart), 'place': sim.race.start.name}),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _heroMuted, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _BigClock(label: tr('Gun in'), builder: (t) => fmtDuration(t < 0 ? -t : 0, forceHours: true)),
        const SizedBox(height: 4),
        Text(
          tr('Bib {bib} · Corral {corral} · Wave 1', {'bib': sim.you.bib, 'corral': corralFor(sim, sim.youId)}),
          style: const TextStyle(color: _heroText, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(14)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.campaign_rounded, color: RL.amber, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr('The gun is fired by the organizer. Try the demo director (bottom-right) or the Organizer console.'),
                  style: const TextStyle(color: _heroMuted, fontSize: 12.5, height: 1.35),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _HeroButtons(
          primary: (tr('Start run'), Icons.directions_run_rounded, () => goToTab(context, AppTab.run)),
          secondary: (tr('Organizer'), Icons.admin_panel_settings_rounded, () => openOrganizer(context)),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------- live

class _Live extends StatelessWidget {
  const _Live({super.key, required this.ticker});
  final FieldTicker ticker;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: RL.red, borderRadius: BorderRadius.circular(999)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LiveBeat(listenable: sim.clock, color: Colors.white, size: 7),
                  const SizedBox(width: 6),
                  Text(tr('Live').toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                ],
              ),
            ),
            const Spacer(),
            const Icon(Icons.schedule_rounded, color: _heroMuted, size: 14),
            const SizedBox(width: 4),
            ValueListenableBuilder<double>(
              valueListenable: sim.clock,
              builder: (_, _, _) => Text(fmtClockSec(sim.now), style: const TextStyle(color: _heroMuted, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _BigClock(label: tr('Race clock'), builder: (t) => fmtDuration(t, forceHours: true)),
        const SizedBox(height: 12),
        ListenableBuilder(
          listenable: ticker,
          builder: (_, _) {
            final s = ticker.snapshot;
            return Row(
              children: [
                Expanded(child: _HeroStat(value: s.running, label: tr('On course'))),
                Expanded(child: _HeroStat(value: s.finished, label: tr('Finished'))),
                Expanded(child: _HeroStat(value: s.notStarted, label: tr('Still to start'))),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _YouPanel(ticker: ticker),
        const SizedBox(height: 14),
        _HeroButtons(
          primary: (tr('Open live run'), Icons.directions_run_rounded, () => goToTab(context, AppTab.run)),
          secondary: (tr('Cheer'), Icons.campaign_rounded, () => goToTab(context, AppTab.cheer)),
        ),
      ],
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 26,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: CountUpText(value, style: const TextStyle(color: _heroText, fontSize: 22, fontWeight: FontWeight.w900)),
            ),
          ),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _heroMuted, fontSize: 11.5)),
        ],
      );
}

/// Your own progress while the race is live.
class _YouPanel extends StatelessWidget {
  const _YouPanel({required this.ticker});
  final FieldTicker ticker;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final units = context.select<SettingsController, Units>((s) => s.units);
    final you = sim.youId;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(14)),
      child: ValueListenableBuilder<double>(
        valueListenable: sim.clock,
        builder: (context, t, _) {
          final state = sim.stateAt(you, t);
          if (state == RunnerState.finished) {
            return InkWell(
              onTap: () => openInsights(context, you),
              child: Row(
                children: [
                  const Icon(Icons.sports_score_rounded, color: RL.amber),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('You finished · {net} net', {'net': fmtDuration(sim.plan(you).netS)}),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _heroText, fontWeight: FontWeight.w800)),
                        Text(tr('Tap for your provisional Race Insights'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _heroMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: _heroMuted),
                ],
              ),
            );
          }
          if (state == RunnerState.notStarted) {
            return Row(
              children: [
                const Icon(Icons.groups_rounded, color: RL.amber),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr('You are in corral {c}, crossing the start line soon', {'c': corralFor(sim, you)}),
                    style: const TextStyle(color: _heroText, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            );
          }
          final d = sim.distanceAt(you, t);
          final frac = (d / sim.race.distanceM).clamp(0.0, 1.0);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(tr('You'), style: const TextStyle(color: RL.amber, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${fmtDistance(d, units, decimals: 2)} · ${fmtPace(sim.paceAt(you, t), units)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _heroText, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(value: frac, minHeight: 7, color: RL.amber, backgroundColor: Colors.white.withValues(alpha: 0.14)),
              ),
              const SizedBox(height: 6),
              ListenableBuilder(
                listenable: ticker,
                builder: (_, _) {
                  final place = ticker.snapshot.yourPlace;
                  return Text(
                    place == null ? tr('{pct} of the course done', {'pct': '${(frac * 100).round()}%'}) : tr('{place} on the road · {pct} done', {'place': ordinal(place), 'pct': '${(frac * 100).round()}%'}),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _heroMuted, fontSize: 12),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------------ closed

class _Closed extends StatelessWidget {
  const _Closed({super.key});

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final official = context.select<RaceSim, bool>((s) => s.official);
    final snap = context.watch<InsightsController>().snapshot;
    final r = snap.result(sim.youId);
    final finished = r.status == ResultStatus.finished && r.overall != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Pill(official ? tr('Official') : tr('Provisional'), color: official ? RL.green : RL.amber, filled: true, icon: official ? Icons.verified_rounded : Icons.hourglass_top_rounded),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                official ? tr('Results published by the organizer') : tr('Race closed · waiting for official results'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _heroMuted, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(tr('Your result').toUpperCase(), style: const TextStyle(color: _heroMuted, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        SizedBox(
          height: 54,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              finished ? fmtDuration(r.netS) : '–',
              style: const TextStyle(color: _heroText, fontSize: 48, fontWeight: FontWeight.w900, height: 1, letterSpacing: -1, fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
        ),
        const SizedBox(height: 4),
        if (finished) ...[
          Text(
            tr('{place} of {n} · net time', {'place': ordinal(r.overall!.place), 'n': fmtInt(r.overall!.of)}),
            style: const TextStyle(color: _heroText, fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (r.gender != null) Expanded(child: _MiniPlace(label: tr('Gender'), info: r.gender!)),
              if (r.category != null) Expanded(child: _MiniPlace(label: sim.race.categoryById(sim.you.categoryId).name, info: r.category!)),
              Expanded(
                child: _MiniStat(label: tr('Avg pace'), value: fmtPace(r.avgPaceSPerKm, context.select<SettingsController, Units>((s) => s.units))),
              ),
            ],
          ),
        ] else
          Text(tr('No finish recorded for you in this race.'), style: const TextStyle(color: _heroMuted)),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => openInsights(context, sim.youId),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            icon: const Icon(Icons.insights_rounded, size: 20),
            label: Text(tr('See your Race Insights'), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }
}

class _MiniPlace extends StatelessWidget {
  const _MiniPlace({required this.label, required this.info});
  final String label;
  final PlaceInfo info;

  @override
  Widget build(BuildContext context) => _MiniStat(label: label, value: '${fmtInt(info.place)}/${fmtInt(info.of)}');
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: const TextStyle(color: _heroText, fontWeight: FontWeight.w900, fontSize: 16, fontFeatures: [FontFeature.tabularFigures()])),
            ),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _heroMuted, fontSize: 11.5)),
          ],
        ),
      );
}
