import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../core/widgets/course_map.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import '../three/race3d_mode.dart';
import 'home_data.dart';
import 'widgets/join_with_bib.dart';
import 'widgets/motion.dart';
import 'widgets/route_painter.dart';

/// Event page: cover, about, course, schedule, checkpoints, join with bib.
class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({super.key, this.focusJoin = false});

  /// Scroll straight to the "Join with bib" card (from the Home bib card).
  final bool focusJoin;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  final _joinKey = GlobalKey();

  static const _coverHeight = 236.0;

  @override
  void initState() {
    super.initState();
    if (widget.focusJoin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _joinKey.currentContext;
        if (ctx != null && mounted) {
          Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic, alignment: 0.08);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final event = sim.event;
    final race = sim.race;
    final units = context.select<SettingsController, Units>((s) => s.units);
    final sections = <Widget>[
      _Facts(race: race, runners: sim.participants.length),
      _About(event: event),
      KeyedSubtree(key: _joinKey, child: const JoinWithBibCard()),
      _Course(race: race),
      _Schedule(event: event, race: race),
      _Checkpoints(race: race, units: units),
      const _CheerCta(),
    ];
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: _coverHeight,
            backgroundColor: RL.navy,
            foregroundColor: Colors.white,
            flexibleSpace: LayoutBuilder(
              builder: (context, c) {
                final top = MediaQuery.of(context).padding.top;
                final t = ((c.maxHeight - kToolbarHeight - top) / (_coverHeight - kToolbarHeight)).clamp(0.0, 1.0);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(opacity: t, child: _Cover(event: event, race: race)),
                    Positioned(
                      left: 56,
                      right: 16,
                      top: top,
                      height: kToolbarHeight,
                      child: Opacity(
                        opacity: (1 - t * 2).clamp(0.0, 1.0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(event.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            sliver: SliverList.separated(
              itemCount: sections.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (_, i) => FadeSlideIn(index: i, child: sections[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.event, required this.race});
  final RaceEvent event;
  final Race race;

  @override
  Widget build(BuildContext context) {
    final status = context.select<RaceSim, RaceStatus>((s) => s.status);
    final official = context.select<RaceSim, bool>((s) => s.official);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [RL.navy, Color(0xFF26467E)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: 30,
            bottom: 10,
            width: 230,
            child: Opacity(opacity: 0.32, child: RouteSilhouette(route: race.route, strokeWidth: 3.5, glow: true, padding: 16)),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    switch (status) {
                      RaceStatus.preRace => Pill(tr('Today'), color: RL.amber, filled: true),
                      RaceStatus.live => Pill(tr('Live'), color: RL.red, filled: true, icon: Icons.circle),
                      RaceStatus.closed => Pill(official ? tr('Official') : tr('Provisional'), color: official ? RL.green : RL.amber, filled: true),
                    },
                    if (event.isDemo) Pill(tr('Demo event'), color: Colors.white),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  event.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 24, height: 1.1, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  '${fmtDate(event.date)} · ${fmtClock(race.scheduledStart)} · ${event.city}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xCCFFFFFF), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.race, required this.runners});
  final Race race;
  final int runners;

  @override
  Widget build(BuildContext context) {
    final units = context.select<SettingsController, Units>((s) => s.units);
    Widget fact(String v, String l) => Expanded(
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: ink(context), fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              const SizedBox(height: 2),
              Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: muted(context))),
            ],
          ),
        );
    return RLCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Row(
        children: [
          fact(fmtDistance(race.distanceM, units), tr('Distance')),
          fact(fmtInt(runners), tr('Runners')),
          fact(fmtDuration(race.cutoffS), tr('Cutoff')),
          fact('${race.checkpoints.length - 1}', tr('Checkpoints')),
        ],
      ),
    );
  }
}

class _About extends StatelessWidget {
  const _About({required this.event});
  final RaceEvent event;

  @override
  Widget build(BuildContext context) {
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(tr('About')),
          Text(
            tr('A 21.1 km loop from Dataran Merdeka past KLCC, Bukit Bintang and Lake Gardens. Demo event with a simulated field of 11,760 runners.'),
            style: TextStyle(color: ink(context), height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.apartment_rounded, size: 18, color: muted(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr('Organised by {org}', {'org': event.organizer}), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted(context), fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 18, color: muted(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr('Chip-free timing: phone GPS, LTE watches and checkpoint cameras'), style: TextStyle(color: muted(context), fontSize: 13)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Course extends StatelessWidget {
  const _Course({required this.race});
  final Race race;

  @override
  Widget build(BuildContext context) {
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(tr('Course')),
          SizedBox(height: 240, child: CourseMap(race: race, interactive: false, padding: const EdgeInsets.all(18))),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => openRace3D(context, Race3DMode.flyover),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: 10)),
                  icon: const Icon(Icons.threed_rotation_rounded, size: 20),
                  label: Text(tr('3D flyover'), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _FullMap(race: race))),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
                  icon: const Icon(Icons.map_rounded, size: 20),
                  label: Text(tr('Full map'), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FullMap extends StatelessWidget {
  const _FullMap({required this.race});
  final Race race;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('Course map'))),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: CourseMap(race: race),
        ),
      );
}

class _Schedule extends StatelessWidget {
  const _Schedule({required this.event, required this.race});
  final RaceEvent event;
  final Race race;

  @override
  Widget build(BuildContext context) {
    final gun = race.scheduledStart;
    final cutoff = gun.add(Duration(seconds: race.cutoffS));
    final kit1 = DateTime(event.date.year, event.date.month, event.date.day).subtract(const Duration(days: 2));
    final kit2 = kit1.add(const Duration(days: 1));
    final items = <(IconData, String, String, String)>[
      (Icons.badge_rounded, tr('Kit collection'), '${fmtDate(kit1)} – ${fmtDate(kit2)}', tr('10:00–20:00 · Dataran Merdeka pavilion. Show your bib QR.')),
      (Icons.groups_rounded, tr('Corrals open'), fmtClock(gun.subtract(const Duration(minutes: 45))), tr('Corral A to E, seeded by expected finish time')),
      (Icons.flag_rounded, tr('Gun'), fmtClock(gun), tr('Fired by the organizer; your net time starts at the start line')),
      (Icons.lock_clock_rounded, tr('Cutoff'), fmtClock(cutoff), tr('{h} after the gun. The course reopens to traffic.', {'h': fmtDuration(race.cutoffS)})),
      (Icons.emoji_events_rounded, tr('Results'), tr('Live'), tr('Provisional during the race, official once the organizer publishes')),
    ];
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(tr('Schedule')),
          for (var i = 0; i < items.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 34,
                    child: Column(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(color: (i == 2 ? RL.amber : RL.navy).withValues(alpha: 0.12), shape: BoxShape.circle),
                          child: Icon(items[i].$1, size: 16, color: i == 2 ? RL.amber : ink(context)),
                        ),
                        if (i < items.length - 1) Expanded(child: Container(width: 2, color: Theme.of(context).dividerColor)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: i < items.length - 1 ? 14 : 0, top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(items[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: ink(context))),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  items[i].$3,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontWeight: FontWeight.w900, color: i == 2 ? RL.amber : ink(context), fontFeatures: const [FontFeature.tabularFigures()]),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(items[i].$4, style: TextStyle(color: muted(context), fontSize: 12.5, height: 1.3)),
                        ],
                      ),
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

class _Checkpoints extends StatelessWidget {
  const _Checkpoints({required this.race, required this.units});
  final Race race;
  final Units units;

  @override
  Widget build(BuildContext context) {
    return RLCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(tr('Checkpoints'), trailing: Text(tr('Camera + GPS'), style: TextStyle(fontSize: 11.5, color: muted(context), fontWeight: FontWeight.w700))),
          for (final c in race.checkpoints)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.type == CheckpointType.split ? Colors.transparent : (c.type == CheckpointType.finish ? RL.amber : RL.navy),
                      shape: BoxShape.circle,
                      border: Border.all(color: c.type == CheckpointType.split ? CourseMap.routeGreen : Colors.transparent, width: 2),
                    ),
                    child: c.type == CheckpointType.split
                        ? Text('${c.index}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: ink(context)))
                        : Icon(c.type == CheckpointType.start ? Icons.flag_rounded : Icons.sports_score_rounded, size: 16, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: ink(context))),
                        Text(cpLabel(c), style: TextStyle(fontSize: 12, color: muted(context))),
                      ],
                    ),
                  ),
                  Text(
                    fmtDistance(c.distanceM, units),
                    style: TextStyle(fontWeight: FontWeight.w800, color: ink(context), fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CheerCta extends StatelessWidget {
  const _CheerCta();

  @override
  Widget build(BuildContext context) {
    return RLCard(
      color: const Color(0xFFEC4899).withValues(alpha: 0.08),
      onTap: () => goToTab(context, AppTab.cheer),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: const Color(0xFFEC4899).withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.campaign_rounded, color: Color(0xFFEC4899)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Cheer someone in this race'), style: TextStyle(fontWeight: FontWeight.w900, color: ink(context))),
                const SizedBox(height: 2),
                Text(tr('Find a runner by name, bib or QR. Live map, ETA and a push at every checkpoint.'), style: TextStyle(color: muted(context), fontSize: 12.5)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: muted(context)),
        ],
      ),
    );
  }
}
