import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/l10n/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../core/widgets/course_map.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import 'cheer_live.dart';
import 'cheer_widgets.dart';
import 'live_map_screen.dart';
import 'live_runner_card.dart';
import 'runner_view.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Opens the runner detail screen (live mini map, splits, cheer, meet up).
Future<void> openRunnerDetail(BuildContext context, int id, {bool scrollToMeet = false}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => RunnerDetailScreen(participantId: id, scrollToMeet: scrollToMeet)));

/// Ready-made cheers (shown translated, sent as shown).
List<String> quickCheers() => [
      tr('Go go go! 💪'),
      tr('Jangan give up!'),
      tr('You got this 🔥'),
      tr('Lagi sikit je! 🏁'),
      tr('Proud of you ❤️'),
      tr('Steady pace, steady!'),
    ];

/// Public link that opens a runner's live page (and works as a follow QR).
String shareLinkFor(Participant p) => 'https://runlah.app/r/${p.bib}';

class RunnerDetailScreen extends StatefulWidget {
  const RunnerDetailScreen({super.key, required this.participantId, this.scrollToMeet = false});
  final int participantId;
  final bool scrollToMeet;

  @override
  State<RunnerDetailScreen> createState() => _RunnerDetailScreenState();
}

class _RunnerDetailScreenState extends State<RunnerDetailScreen> with SingleTickerProviderStateMixin {
  late final RaceSim _sim = context.read<RaceSim>();
  late final CheerLive _live = CheerLive.of(_sim);
  late final SmoothClock _clock = SmoothClock(_sim, this);
  final _map = MapController();
  final _meetKey = GlobalKey();
  bool _mapReady = false;

  int get id => widget.participantId;

  @override
  void initState() {
    super.initState();
    _live.track(id);
    _live.addListener(_follow);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapReady = true;
      _follow();
      if (widget.scrollToMeet) _scrollToMeet();
    });
  }

  @override
  void dispose() {
    _live.removeListener(_follow);
    _live.untrack(id);
    _clock.dispose();
    _map.dispose();
    super.dispose();
  }

  /// Keep the mini map centred on the runner (≤ 1 Hz).
  void _follow() {
    if (!_mapReady || !mounted) return;
    final v = RunnerNow.of(_sim, context.read<InsightsController>().snapshot, id, _clock.value);
    try {
      _map.move(v.position, 15);
    } catch (_) {
      // Map not laid out yet (first frame / tests).
    }
  }

  void _scrollToMeet() {
    final c = _meetKey.currentContext;
    if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic, alignment: 0.1);
  }

  @override
  Widget build(BuildContext context) {
    final p = _sim.participant(id);
    final you = id == _sim.youId;
    final follows = context.watch<FollowsController>();
    final color = runnerColor(_sim, follows.ids, id);
    final cat = _sim.race.categoryById(p.categoryId).name;

    return Scaffold(
      appBar: AppBar(
        title: Text(you ? tr('You') : shortName(p)),
        actions: [
          IconButton(
            tooltip: tr('Share live link'),
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => shareRunnerLink(context, p),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 90 + MediaQuery.of(context).padding.bottom),
        children: [
          // ---- header
          Row(
            children: [
              Hero(tag: avatarHeroTag(id), child: RunnerAvatar(participant: p, color: color, size: 68)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: ink(context), height: 1.15),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tr('Bib {bib} · {cat} · {nation}', {'bib': p.bib, 'cat': cat, 'nation': p.nation}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: muted(context)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        RunnerStateBuilder(id: id, builder: (_, s) => StatusChip(s)),
                        Pill(
                          p.hasGps ? tr('Live GPS') : tr('Checkpoint estimate'),
                          color: p.hasGps ? RL.teal : RL.slate,
                          icon: p.hasGps ? Icons.gps_fixed_rounded : Icons.flag_circle_outlined,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ---- mini map
          SizedBox(
            height: 210,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CourseMap(
                    race: _sim.race,
                    controller: _map,
                    interactive: false,
                    showLandmarks: false,
                    extraLayers: [
                      TrailLayer(clock: _clock, id: id, color: color),
                      RunnersLayer(clock: _clock, ids: [id], highlight: id, size: 28),
                    ],
                  ),
                ),
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(RL.radius),
                      onTap: () => openLiveMap(context, focus: id),
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  child: Pill(tr('Open live map'), color: RL.navy, filled: true, icon: Icons.open_in_full_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ---- live numbers
          _LiveNumbers(id: id, live: _live, color: color),
          const SizedBox(height: 12),

          // ---- finished / meet me after
          RunnerStateBuilder(
            id: id,
            builder: (context, state) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state == RunnerState.finished) ...[
                  Appear(child: _FinishedCard(id: id)),
                  const SizedBox(height: 12),
                ],
                if (!you)
                  KeyedSubtree(
                    key: _meetKey,
                    child: _MeetCard(id: id, state: state),
                  ),
                if (!you) const SizedBox(height: 12),
              ],
            ),
          ),

          // ---- cheers
          if (you) _ReceivedCheers(id: id) else _CheerComposer(id: id, color: color),
          const SizedBox(height: 12),

          // ---- splits
          _Splits(id: id),
          const SizedBox(height: 12),

          // ---- follow settings
          if (!you) _FollowSettings(id: id),
        ],
      ),
    );
  }
}

/// Share a runner's live page; falls back to the clipboard.
Future<void> shareRunnerLink(BuildContext context, Participant p) async {
  final url = shareLinkFor(p);
  final text = tr('Follow {name} live at {race}: {url}', {'name': p.firstName, 'race': context.read<RaceSim>().event.name, 'url': url});
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await SharePlus.instance.share(ShareParams(text: text, subject: tr('RunLah live tracking')));
  } catch (_) {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {}
    messenger?.showSnackBar(SnackBar(content: Text(tr('Link copied: {url}', {'url': url}))));
  }
}

// ------------------------------------------------------------ live numbers

class _LiveNumbers extends StatelessWidget {
  const _LiveNumbers({required this.id, required this.live, required this.color});
  final int id;
  final CheerLive live;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final units = context.select<SettingsController, Units>((s) => s.units);
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(tr('Live')),
          ValueListenableBuilder<double>(
            valueListenable: sim.clock,
            builder: (context, t, _) {
              final v = RunnerNow.of(sim, context.read<InsightsController>().snapshot, id, t);
              final race = sim.race;
              final ticks = [for (final c in race.checkpoints) c.distanceM / race.distanceM];
              final projected = v.finishEta == null ? null : v.finishEta! - sim.plan(id).startDelayS;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CourseProgressBar(fraction: v.fraction, checkpointFractions: ticks, color: color, estimated: v.estimated, passedUpTo: v.lastCp),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: MiniStat(
                          label: tr('Distance'),
                          value: '${v.estimated ? '≈' : ''}${fmtDistance(v.distanceM, units)}',
                          size: 20,
                        ),
                      ),
                      Expanded(child: MiniStat(label: tr('Pace'), value: fmtPace(v.paceSPerKm, units), size: 20)),
                      Expanded(child: MiniStat(label: tr('Elapsed'), value: fmtDuration(v.elapsedS), size: 20)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: MiniStat(
                          label: v.state == RunnerState.finished ? tr('Finished at') : tr('Finish ETA'),
                          value: v.finishEta == null ? '–' : fmtClock(sim.wallClockAt(v.finishEta!)),
                          sub: projected == null ? null : '${v.state == RunnerState.finished ? '' : '≈ '}${fmtDuration(projected)}',
                          size: 20,
                        ),
                      ),
                      Expanded(
                        child: ListenableBuilder(
                          listenable: live,
                          builder: (context, _) {
                            final c = live.counts(id);
                            return MiniStat(label: tr('On the road'), value: c.roadPlace == 0 ? '–' : '#${fmtInt(c.roadPlace)}', size: 20);
                          },
                        ),
                      ),
                      Expanded(
                        child: ListenableBuilder(
                          listenable: live,
                          builder: (context, _) {
                            final c = live.counts(id);
                            final cp = c.lastCp >= 0 ? cpLabel(race.checkpoints[c.lastCp]) : '–';
                            return MiniStat(
                              label: tr('Passed since {cp}', {'cp': cp}),
                              value: '▲ ${fmtInt(c.passed)}',
                              sub: c.passedBy > 0 ? tr('▼ {n} passed them', {'n': fmtInt(c.passedBy)}) : null,
                              color: RL.green,
                              size: 20,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- finished

class _FinishedCard extends StatelessWidget {
  const _FinishedCard({required this.id});
  final int id;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final snap = context.watch<InsightsController>().snapshot;
    final r = snap.result(id);
    final p = sim.participant(id);
    final cat = sim.race.categoryById(p.categoryId).name;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(RL.radius),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [RL.navy, RL.navySoft]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sports_score_rounded, color: RL.amber, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tr('Finished! 🎉'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              Pill(snap.official ? tr('Official') : tr('Provisional'), color: snap.official ? RL.green : RL.amber, filled: true),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              fmtDuration(r.netS ?? sim.plan(id).netS),
              style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900, fontFeatures: _tabular, height: 1),
            ),
          ),
          Text(tr('net time'), style: const TextStyle(color: Colors.white60, fontSize: 12)),
          if (r.overall != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _WhiteStat(value: ordinal(r.overall!.place), label: tr('of {n} overall', {'n': fmtInt(r.overall!.of)}))),
                Expanded(child: _WhiteStat(value: ordinal(r.category!.place), label: cat)),
                Expanded(child: _WhiteStat(value: tr('Top {pct}', {'pct': fmtPct(math.max(0.1, r.overall!.topPct))}), label: tr('of finishers'))),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => openInsights(context, id),
                  icon: const Icon(Icons.insights_rounded),
                  label: FittedBox(fit: BoxFit.scaleDown, child: Text(tr('See Race Insights'))),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: tr('Share card'),
                style: IconButton.styleFrom(minimumSize: const Size(52, 52), backgroundColor: Colors.white.withValues(alpha: 0.14)),
                onPressed: () => openShareCard(context, id),
                icon: const Icon(Icons.share_rounded, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WhiteStat extends StatelessWidget {
  const _WhiteStat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, fontFeatures: _tabular)),
          ),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ],
      );
}

// ---------------------------------------------------------- meet me after

class _MeetCard extends StatefulWidget {
  const _MeetCard({required this.id, required this.state});
  final int id;
  final RunnerState state;

  @override
  State<_MeetCard> createState() => _MeetCardState();
}

class _MeetCardState extends State<_MeetCard> {
  final _map = MapController();

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _zoom(MeetingPoint m) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _map.move(m.location, 16.6);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final p = sim.participant(widget.id);
    final m = MeetingPoint.forRunner(p);
    final finished = widget.state == RunnerState.finished;
    final finishT = sim.crossingTime(widget.id, sim.race.distanceM);
    final walkMin = math.max(1, (haversine(sim.race.finish.location, m.location) * 1.3 / 80).round());

    if (!finished) {
      return RLCard(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: RL.teal.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.handshake_rounded, color: RL.teal),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Meet me after'), style: TextStyle(fontWeight: FontWeight.w800, color: ink(context))),
                  const SizedBox(height: 2),
                  Text(
                    widget.state == RunnerState.dnf
                        ? tr('{name} stopped early. Call them to find each other.', {'name': p.firstName})
                        : tr('{name}\'s meeting point shows up here when they cross the finish.', {'name': p.firstName}),
                    style: TextStyle(fontSize: 12.5, color: muted(context)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    _zoom(m);
    final there = finishT == null ? null : sim.wallClockAt(finishT + 12 * 60);
    return RLCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: RL.teal, borderRadius: BorderRadius.circular(14)),
                  child: Text(m.code, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Meet me after'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: RL.teal, letterSpacing: 0.4)),
                      Text(
                        tr('Meeting point {code} · {name}', {'code': m.code, 'name': tr(m.name)}),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ink(context)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 170,
            child: CourseMap(
              race: sim.race,
              controller: _map,
              interactive: false,
              showLandmarks: false,
              showCheckpoints: false,
              padding: const EdgeInsets.all(60),
              extraLayers: [
                MarkerLayer(markers: [
                  PlacePin.marker(sim.race.finish.location, icon: Icons.sports_score_rounded, color: RL.amber),
                  PlacePin.marker(m.location, icon: Icons.handshake_rounded, color: RL.teal, label: tr('Point {code}', {'code': m.code})),
                ]),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.directions_walk_rounded, size: 18, color: muted(context)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    there == null
                        ? tr('About {n} min walk from the finish arch', {'n': walkMin})
                        : tr('About {n} min walk from the finish arch · {name} will be there around {time}', {
                            'n': walkMin,
                            'name': p.firstName,
                            'time': fmtClock(there),
                          }),
                    style: TextStyle(fontSize: 12.5, color: muted(context)),
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

// ---------------------------------------------------------------- cheering

class _CheerComposer extends StatefulWidget {
  const _CheerComposer({required this.id, required this.color});
  final int id;
  final Color color;

  @override
  State<_CheerComposer> createState() => _CheerComposerState();
}

class _CheerComposerState extends State<_CheerComposer> with SingleTickerProviderStateMixin {
  final _text = TextEditingController();
  late final AnimationController _sent = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));

  @override
  void dispose() {
    _text.dispose();
    _sent.dispose();
    super.dispose();
  }

  void _send(String body) {
    final msg = body.trim();
    if (msg.isEmpty) return;
    final sim = context.read<RaceSim>();
    sim.sendCheer(toParticipantId: widget.id, from: context.read<SettingsController>().displayName, body: msg);
    _text.clear();
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
    _sent.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final p = sim.participant(widget.id);
    context.select<RaceSim, int>((s) => s.cheers.length);
    final sent = sim.cheersFor(widget.id);
    return RLCard(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionLabel(tr('Send a cheer')),
              Text(
                tr('{name} sees it on their lock screen and hears it read aloud mid-run.', {'name': p.firstName}),
                style: TextStyle(fontSize: 12.5, color: muted(context)),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final q in quickCheers())
                    ActionChip(
                      label: Text(q),
                      onPressed: () => _send(q),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      maxLength: 140,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      decoration: InputDecoration(
                        hintText: tr('Write your own…'),
                        counterText: '',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedBuilder(
                    animation: _sent,
                    builder: (_, _) => IconButton.filled(
                      tooltip: tr('Send'),
                      style: IconButton.styleFrom(backgroundColor: _sent.isAnimating ? RL.green : RL.amber, minimumSize: const Size(50, 50)),
                      onPressed: () => _send(_text.text),
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                        child: Icon(
                          _sent.isAnimating ? Icons.check_rounded : Icons.send_rounded,
                          key: ValueKey(_sent.isAnimating),
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (sent.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final m in sent.take(4)) _CheerBubble(message: m, color: widget.color),
              ],
            ],
          ),
          // Flying "sent" confirmation.
          Positioned(
            right: 0,
            top: -6,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _sent,
                builder: (_, _) {
                  final v = _sent.value;
                  if (!_sent.isAnimating) return const SizedBox.shrink();
                  final opacity = v < 0.15 ? v / 0.15 : (v > 0.75 ? (1 - v) / 0.25 : 1.0);
                  return Transform.translate(
                    offset: Offset(0, -24 * Curves.easeOut.transform(v)),
                    child: Transform.scale(
                      scale: 0.8 + 0.2 * Curves.elasticOut.transform(math.min(1, v * 2.5)),
                      child: Opacity(
                        opacity: opacity.clamp(0.0, 1.0),
                        child: Pill(tr('Cheer sent!'), color: RL.green, filled: true, icon: Icons.campaign_rounded),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheerBubble extends StatelessWidget {
  const _CheerBubble({required this.message, required this.color});
  final CheerMessage message;
  final Color color;

  @override
  Widget build(BuildContext context) => Appear(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.campaign_rounded, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(14),
                      bottomLeft: Radius.circular(14),
                      bottomRight: Radius.circular(14),
                      topLeft: Radius.circular(4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(message.body, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: ink(context))),
                      const SizedBox(height: 2),
                      Text(
                        '${message.from} · ${fmtClock(message.at)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: muted(context)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _ReceivedCheers extends StatelessWidget {
  const _ReceivedCheers({required this.id});
  final int id;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    context.select<RaceSim, int>((s) => s.cheers.length);
    final got = sim.cheersFor(id);
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(tr('Cheers you received')),
          if (got.isEmpty)
            Text(tr('No cheers yet. Your friends can send them from their Cheer tab.'), style: TextStyle(fontSize: 13, color: muted(context)))
          else
            for (final m in got.take(6)) _CheerBubble(message: m, color: RL.series[3]),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ splits

class _Splits extends StatelessWidget {
  const _Splits({required this.id});
  final int id;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final units = context.select<SettingsController, Units>((s) => s.units);
    final race = sim.race;
    final table = sim.crossingTable;
    final i = table.indexOf[id]!;
    final start = sim.plan(id).startDelayS;
    return RLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(tr('Splits so far')),
          ValueListenableBuilder<double>(
            valueListenable: sim.clock,
            builder: (context, t, _) {
              final st = sim.stateAt(id, t);
              return Column(
                children: [
                  for (var k = 1; k < race.checkpoints.length; k++)
                    () {
                      final cp = race.checkpoints[k];
                      final x = table.times[k][i];
                      final passed = !x.isNaN && x <= t && sim.status != RaceStatus.preRace;
                      final prev = table.times[k - 1][i];
                      final split = passed && !prev.isNaN ? (x - prev) / ((cp.distanceM - race.checkpoints[k - 1].distanceM) / 1000) : null;
                      final eta = passed || st == RunnerState.dnf || st == RunnerState.finished ? null : sim.etaToDistance(id, cp.distanceM, t);
                      return _SplitRow(
                        label: cpLabel(cp),
                        name: cp.name,
                        passed: passed,
                        clock: passed ? fmtClock(sim.wallClockAt(x)) : (eta == null ? '–' : fmtClock(sim.wallClockAt(eta))),
                        net: passed ? fmtDuration(x - start) : null,
                        pace: split == null ? null : fmtPace(split, units),
                        last: k == race.checkpoints.length - 1,
                      );
                    }(),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({required this.label, required this.name, required this.passed, required this.clock, this.net, this.pace, this.last = false});
  final String label;
  final String name;
  final bool passed;
  final String clock;
  final String? net;
  final String? pace;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = passed ? ink(context) : muted(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(passed ? Icons.check_circle_rounded : (last ? Icons.sports_score_rounded : Icons.radio_button_unchecked_rounded), size: 18, color: passed ? RL.green : muted(context)),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: c, fontSize: 13)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c, fontWeight: FontWeight.w600)),
                if (pace != null) Text(pace!, maxLines: 1, style: TextStyle(fontSize: 11, color: muted(context), fontFeatures: _tabular)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                passed ? clock : tr('ETA {time}', {'time': clock}),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c, fontFeatures: _tabular),
              ),
              if (net != null) Text(net!, style: TextStyle(fontSize: 11, color: muted(context), fontFeatures: _tabular)),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------- follow settings

class _FollowSettings extends StatelessWidget {
  const _FollowSettings({required this.id});
  final int id;

  @override
  Widget build(BuildContext context) {
    final follows = context.watch<FollowsController>();
    final sim = context.read<RaceSim>();
    final p = sim.participant(id);
    final following = follows.isFollowing(id);
    if (!following) {
      return FilledButton.icon(
        onPressed: () {
          follows.follow(id);
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('Following {name}', {'name': shortName(p)}))));
        },
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(tr('Follow {name}', {'name': shortName(p)})),
      );
    }
    return RLCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          SwitchListTile(
            value: follows.notifies(id),
            onChanged: (v) => follows.setNotify(id, v),
            secondary: const Icon(Icons.notifications_active_rounded),
            title: Text(tr('Notifications'), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(tr('Checkpoints and finish')),
          ),
          const Divider(indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.person_remove_rounded, color: RL.red),
            title: Text(tr('Unfollow {name}', {'name': shortName(p)}), style: const TextStyle(color: RL.red, fontWeight: FontWeight.w700)),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: Text(tr('Unfollow {name}?', {'name': shortName(p)})),
                  content: Text(tr('You will stop getting their checkpoint alerts.')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancel'))),
                    TextButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Unfollow'))),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                follows.unfollow(id);
                Navigator.of(context).maybePop();
              }
            },
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ quick sheet

/// Compact runner sheet (from a map dot): live line, quick cheers, details.
Future<void> showRunnerQuickSheet(BuildContext context, int id) => showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _QuickSheet(id: id),
    );

class _QuickSheet extends StatelessWidget {
  const _QuickSheet({required this.id});
  final int id;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final follows = context.watch<FollowsController>();
    final units = context.select<SettingsController, Units>((s) => s.units);
    final p = sim.participant(id);
    final you = id == sim.youId;
    final color = runnerColor(sim, follows.ids, id);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                RunnerAvatar(participant: p, color: color, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(you ? tr('You') : p.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ink(context))),
                      Text(tr('Bib {bib}', {'bib': p.bib}), style: TextStyle(fontSize: 12.5, color: muted(context))),
                    ],
                  ),
                ),
                RunnerStateBuilder(id: id, builder: (_, s) => StatusChip(s)),
              ],
            ),
            const SizedBox(height: 14),
            ValueListenableBuilder<double>(
              valueListenable: sim.clock,
              builder: (context, t, _) {
                final v = RunnerNow.of(sim, context.read<InsightsController>().snapshot, id, t);
                return Row(
                  children: [
                    Expanded(child: MiniStat(label: tr('Distance'), value: '${v.estimated ? '≈' : ''}${fmtDistance(v.distanceM, units)}')),
                    Expanded(child: MiniStat(label: tr('Pace'), value: fmtPace(v.paceSPerKm, units))),
                    Expanded(
                      child: MiniStat(
                        label: v.state == RunnerState.finished ? tr('Finished at') : tr('Finish ETA'),
                        value: v.finishEta == null ? '–' : fmtClock(sim.wallClockAt(v.finishEta!)),
                      ),
                    ),
                  ],
                );
              },
            ),
            if (!you) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final q in quickCheers())
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: const Icon(Icons.campaign_rounded, size: 16),
                          label: Text(q),
                          onPressed: () {
                            sim.sendCheer(toParticipantId: id, from: context.read<SettingsController>().displayName, body: q);
                            HapticFeedback.lightImpact();
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                              SnackBar(content: Text(tr('Cheer sent to {name}!', {'name': shortName(p)})), duration: const Duration(seconds: 2)),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () {
                final nav = Navigator.of(context);
                nav.pop();
                nav.push(MaterialPageRoute(builder: (_) => RunnerDetailScreen(participantId: id)));
              },
              icon: const Icon(Icons.person_search_rounded),
              label: Text(tr('Full details')),
            ),
          ],
        ),
      ),
    );
  }
}
