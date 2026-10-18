import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/course_map.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import 'add_runner_sheet.dart';
import 'cheer_live.dart';
import 'cheer_spots_screen.dart';
import 'cheer_widgets.dart';
import 'live_map_screen.dart';
import 'live_runner_card.dart';
import 'notifications_sheet.dart';
import 'ranking_screen.dart';
import 'runner_detail_screen.dart';

const _tabular = [FontFeature.tabularFigures()];

/// The Cheer tab: you as a supporter. Live cards for everyone you follow,
/// a live map, cheer spots with "leave now" alerts, the live ranking and
/// your notification feed.
class CheerScreen extends StatefulWidget {
  const CheerScreen({super.key});

  @override
  State<CheerScreen> createState() => _CheerScreenState();
}

class _CheerScreenState extends State<CheerScreen> with SingleTickerProviderStateMixin {
  late final RaceSim _sim = context.read<RaceSim>();
  late final CheerLive _live = CheerLive.of(_sim);
  late final SmoothClock _clock = SmoothClock(_sim, this);
  late bool _showMe = cheerShowMe(context.read<SettingsController>());

  @override
  void initState() {
    super.initState();
    // Keeps the live engine (and the leave-now alarms) running while the
    // tab exists, even when another tab is showing.
    _live.addListener(_noop);
  }

  void _noop() {}

  @override
  void dispose() {
    _live.removeListener(_noop);
    _clock.dispose();
    super.dispose();
  }

  void _toggleMe() {
    setState(() => _showMe = !_showMe);
    setCheerShowMe(context.read<SettingsController>(), _showMe);
  }

  @override
  Widget build(BuildContext context) {
    final follows = context.watch<FollowsController>();
    final status = context.select<RaceSim, RaceStatus>((s) => s.status);
    final ids = cheerIds(_sim, follows.ids, showMe: _showMe);
    final followed = follows.ids.where((i) => i != _sim.youId).length;

    return Scaffold(
      body: TickerMode(
        // Hidden tabs in the shell's IndexedStack stay mounted: stop their animations.
        enabled: Visibility.of(context),
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('Cheer'), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: ink(context), height: 1.1)),
                            Text(
                              _sim.event.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, color: muted(context), fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      const NotificationBell(),
                      IconButton(
                        tooltip: tr('Add runner'),
                        onPressed: () => showAddRunnerSheet(context),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 90 + MediaQuery.of(context).padding.bottom),
                sliver: SliverList.list(
                  children: [
                    Appear(child: _RaceStatusCard(sim: _sim, live: _live)),
                    if (status == RaceStatus.live) ...[
                      const SizedBox(height: 12),
                      Appear(index: 1, child: LeadersStrip(live: _live, onTap: () => openRanking(context))),
                    ],
                    const SizedBox(height: 12),
                    Appear(index: 1, child: _MapPreview(clock: _clock, ids: ids)),
                    const SizedBox(height: 12),
                    Appear(index: 2, child: const _QuickActions()),
                    const SizedBox(height: 22),
                    SectionLabel(
                      tr('Following · {n}', {'n': followed}),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ShowMeChip(on: _showMe, onTap: _toggleMe),
                          const SizedBox(width: 4),
                          TextButton.icon(
                            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                            onPressed: () => showAddRunnerSheet(context),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: Text(tr('Add')),
                          ),
                        ],
                      ),
                    ),
                    if (ids.isEmpty) const _EmptyFollowing(),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < ids.length; i++)
                            Appear(
                              key: ValueKey(ids[i]),
                              index: i + 2,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: LiveRunnerCard(id: ids[i], live: _live),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const _CheerFeed(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- race card

class _RaceStatusCard extends StatelessWidget {
  const _RaceStatusCard({required this.sim, required this.live});
  final RaceSim sim;
  final CheerLive live;

  @override
  Widget build(BuildContext context) {
    final status = context.select<RaceSim, RaceStatus>((s) => s.status);
    final official = context.select<RaceSim, bool>((s) => s.official);
    final race = sim.race;
    final (label, color) = switch (status) {
      RaceStatus.preRace => (tr('Pre-race'), RL.amber),
      RaceStatus.live => (tr('Live'), RL.red),
      RaceStatus.closed => (official ? tr('Official') : tr('Closed'), official ? RL.green : RL.slate),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(RL.radius),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [RL.navy, RL.navySoft]),
        boxShadow: [BoxShadow(color: RL.navy.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            bottom: -18,
            child: Icon(Icons.directions_run_rounded, size: 110, color: Colors.white.withValues(alpha: 0.05)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(4, 2, 10, 2),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (status == RaceStatus.live) LiveDot(color: color, size: 7) else const SizedBox(width: 6),
                        Text(label.toUpperCase(), style: TextStyle(color: color == RL.slate ? Colors.white70 : color, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.8)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr('{dist} · {race}', {'dist': fmtDistance(race.distanceM, Units.km), 'race': race.name}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<double>(
                valueListenable: sim.clock,
                builder: (_, t, _) => Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          status == RaceStatus.preRace ? fmtDuration(-t) : fmtDuration(t, forceHours: true),
                          style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w900, height: 1, fontFeatures: _tabular),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        status == RaceStatus.preRace ? tr('to the gun') : fmtClock(sim.now),
                        style: const TextStyle(color: RL.amber, fontSize: 14, fontWeight: FontWeight.w800, fontFeatures: _tabular),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: live,
                builder: (_, _) => Text(
                  switch (status) {
                    RaceStatus.preRace => tr('Gun at {time} · {place}', {'time': fmtClock(sim.gunWallClock), 'place': race.start.name}),
                    RaceStatus.live => tr('{run} on course · {fin} finished · {ns} yet to start', {
                        'run': fmtInt(live.running),
                        'fin': fmtInt(live.finished),
                        'ns': fmtInt(live.notStarted),
                      }),
                    RaceStatus.closed => tr('{fin} finishers · results {kind}', {
                        'fin': fmtInt(live.finished),
                        'kind': official ? tr('official') : tr('provisional'),
                      }),
                  },
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- map card

class _MapPreview extends StatelessWidget {
  const _MapPreview({required this.clock, required this.ids});
  final SmoothClock clock;
  final List<int> ids;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    return SizedBox(
      height: 210,
      child: Stack(
        children: [
          Positioned.fill(
            child: CourseMap(
              race: sim.race,
              interactive: false,
              showLandmarks: false,
              padding: const EdgeInsets.all(22),
              extraLayers: [RunnersLayer(clock: clock, ids: ids, size: 24)],
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(RL.radius),
                onTap: () => openLiveMap(context),
              ),
            ),
          ),
          Positioned(
            left: 10,
            top: 10,
            child: IgnorePointer(child: Pill(tr('Live map'), color: RL.navy, filled: true, icon: Icons.map_rounded)),
          ),
          Positioned(
            left: 10,
            bottom: 10,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: RL.amber, borderRadius: BorderRadius.circular(999)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr('Open'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                    const SizedBox(width: 2),
                    const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 14),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ quick actions

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, Color, VoidCallback)>[
      (Icons.place_rounded, tr('Cheer spots'), RL.teal, () => openCheerSpots(context)),
      (Icons.leaderboard_rounded, tr('Ranking'), RL.amber, () => openRanking(context)),
      (Icons.qr_code_scanner_rounded, tr('Add runner'), RL.series[1], () => showAddRunnerSheet(context)),
      (Icons.ios_share_rounded, tr('My QR'), RL.series[4], () => showMyQr(context)),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: RLCard(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              onTap: items[i].$4,
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: items[i].$3.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                    child: Icon(items[i].$1, color: items[i].$3, size: 22),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    items[i].$2,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: ink(context), height: 1.15),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ShowMeChip extends StatelessWidget {
  const _ShowMeChip({required this.on, required this.onTap});
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tr('Show my own run here too'),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: on ? RL.amber.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: on ? RL.amber : muted(context).withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(on ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 14, color: on ? RL.amber : muted(context)),
                const SizedBox(width: 4),
                Text(tr('Me'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: on ? RL.amber : muted(context))),
              ],
            ),
          ),
        ),
      );
}

class _EmptyFollowing extends StatelessWidget {
  const _EmptyFollowing();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: RLCard(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: RL.amber.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: const Icon(Icons.campaign_rounded, color: RL.amber, size: 32),
              ),
              const SizedBox(height: 12),
              Text(tr('Cheer someone on'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: ink(context))),
              const SizedBox(height: 4),
              Text(
                tr('Follow a friend by name, bib or QR to see them live, get checkpoint alerts and send cheers.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: muted(context), fontSize: 13),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => showAddRunnerSheet(context),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(tr('Add runner')),
              ),
            ],
          ),
        ),
      );
}

// --------------------------------------------------------------- cheer feed

class _CheerFeed extends StatelessWidget {
  const _CheerFeed();

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final count = context.select<RaceSim, int>((s) => s.cheers.length);
    if (count == 0) return const SizedBox.shrink();
    final latest = sim.cheers.take(4).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(tr('Cheer wall')),
          RLCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (var i = 0; i < latest.length; i++)
                  Appear(
                    key: ValueKey(latest[i]),
                    child: _CheerTile(message: latest[i]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheerTile extends StatelessWidget {
  const _CheerTile({required this.message});
  final CheerMessage message;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final to = message.toParticipantId == null ? null : sim.participant(message.toParticipantId!);
    final toName = to == null ? '' : (to.id == sim.youId ? tr('you') : to.firstName);
    return ListTile(
      onTap: to == null ? null : () => openRunnerDetail(context, to.id),
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFEC4899).withValues(alpha: 0.15),
        child: Text(
          message.from.isEmpty ? '?' : message.from[0].toUpperCase(),
          style: const TextStyle(color: Color(0xFFEC4899), fontWeight: FontWeight.w900),
        ),
      ),
      title: Text(message.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: ink(context), fontSize: 14)),
      subtitle: Text(
        tr('{from} → {to} · {time}', {'from': message.from, 'to': toName, 'time': fmtClock(message.at)}),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
