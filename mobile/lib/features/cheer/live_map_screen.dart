import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/course_map.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import 'cheer_live.dart';
import 'cheer_widgets.dart';
import 'runner_detail_screen.dart';
import 'runner_view.dart';

const _tabular = [FontFeature.tabularFigures()];

Future<void> openLiveMap(BuildContext context, {int? focus}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => LiveMapScreen(focus: focus)));

/// Full-screen live map of the people you follow. Dots glide every frame;
/// runners without GPS are hollow rings at their estimated position.
/// Optional crowd layer shows a sample of the whole field.
class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key, this.focus});
  final int? focus;

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> with SingleTickerProviderStateMixin {
  late final RaceSim _sim = context.read<RaceSim>();
  late final CheerLive _live = CheerLive.of(_sim);
  late final SmoothClock _clock = SmoothClock(_sim, this);
  final _map = MapController();
  StreamSubscription<MapEvent>? _mapSub;
  bool _field = false;
  bool _follow = false;
  bool _ready = false;
  int? _focus;

  @override
  void initState() {
    super.initState();
    _focus = widget.focus;
    _follow = _focus != null;
    _live.addListener(_onLive);
    _mapSub = _map.mapEventStream.listen((e) {
      if (e.source == MapEventSource.dragStart || e.source == MapEventSource.multiFingerGestureStart) {
        if (_follow && mounted) setState(() => _follow = false);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ready = true;
      if (_focus != null) _moveTo(_focus!, zoom: 15);
    });
  }

  @override
  void dispose() {
    if (_field) _live.wantField(false);
    _live.removeListener(_onLive);
    _mapSub?.cancel();
    _clock.dispose();
    _map.dispose();
    super.dispose();
  }

  void _onLive() {
    if (_follow && _focus != null) _moveTo(_focus!);
  }

  void _moveTo(int id, {double? zoom}) {
    if (!_ready || !mounted) return;
    final v = RunnerNow.of(_sim, context.read<InsightsController>().snapshot, id, _clock.value);
    try {
      _map.move(v.position, zoom ?? math.max(_map.camera.zoom, 14.5));
    } catch (_) {}
  }

  void _fitCourse() {
    final b = _sim.race.route.bounds;
    try {
      _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds(b.southWest, b.northEast), padding: const EdgeInsets.fromLTRB(28, 140, 28, 170)));
    } catch (_) {}
    setState(() {
      _focus = null;
      _follow = false;
    });
  }

  void _toggleField(bool on) {
    setState(() => _field = on);
    _live.wantField(on);
  }

  @override
  Widget build(BuildContext context) {
    final follows = context.watch<FollowsController>();
    final showMe = cheerShowMe(context.read<SettingsController>());
    final ids = cheerIds(_sim, follows.ids, showMe: showMe);
    final spot = _live.spot;
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: CourseMap(
              race: _sim.race,
              controller: _map,
              padding: EdgeInsets.fromLTRB(28, 140 + top, 28, 170 + bottom),
              extraLayers: [
                if (_field) FieldLayer(live: _live),
                if (spot != null)
                  MarkerLayer(markers: [PlacePin.marker(spot.point(_sim.race), icon: Icons.campaign_rounded, color: RL.navy, label: spot.name)]),
                RunnersLayer(
                  clock: _clock,
                  ids: ids,
                  highlight: _focus,
                  onTap: (id) => showRunnerQuickSheet(context, id),
                ),
              ],
            ),
          ),
          // ---- top bar
          Positioned(
            left: 12,
            right: 12,
            top: top + 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _RoundButton(icon: Icons.arrow_back_rounded, tooltip: tr('Back'), onTap: () => Navigator.of(context).maybePop()),
                    const SizedBox(width: 8),
                    Expanded(child: _ClockCard(sim: _sim, live: _live)),
                    const SizedBox(width: 8),
                    _RoundButton(icon: Icons.zoom_out_map_rounded, tooltip: tr('Whole course'), onTap: _fitCourse),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _MapChip(
                      selected: _field,
                      icon: Icons.groups_rounded,
                      label: tr('Show field'),
                      onTap: () => _toggleField(!_field),
                    ),
                    if (_focus != null)
                      _MapChip(
                        selected: _follow,
                        icon: Icons.my_location_rounded,
                        label: tr('Follow camera'),
                        onTap: () {
                          setState(() => _follow = !_follow);
                          if (_follow) _moveTo(_focus!);
                        },
                      ),
                    _Legend(field: _field),
                  ],
                ),
              ],
            ),
          ),
          // ---- runner strip
          Positioned(
            left: 0,
            right: 0,
            bottom: bottom + 12,
            child: SizedBox(
              height: 76,
              child: ids.isEmpty
                  ? Center(child: _Glass(child: Text(tr('Follow a runner to see them here'), style: TextStyle(color: ink(context), fontWeight: FontWeight.w700))))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      scrollDirection: Axis.horizontal,
                      itemCount: ids.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final id = ids[i];
                        return _RunnerChip(
                          id: id,
                          color: runnerColor(_sim, follows.ids, id),
                          selected: _focus == id,
                          onTap: () {
                            if (_focus == id) {
                              showRunnerQuickSheet(context, id);
                              return;
                            }
                            setState(() {
                              _focus = id;
                              _follow = true;
                            });
                            _moveTo(id, zoom: 15);
                          },
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

class _Glass extends StatelessWidget {
  const _Glass({required this.child, this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: (dark ? const Color(0xFF111827) : Colors.white).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 14, offset: Offset(0, 4))],
      ),
      child: child,
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, required this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: (dark ? const Color(0xFF111827) : Colors.white).withValues(alpha: 0.94),
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: Colors.black26,
      child: IconButton(tooltip: tooltip, onPressed: onTap, icon: Icon(icon, color: ink(context))),
    );
  }
}

class _ClockCard extends StatelessWidget {
  const _ClockCard({required this.sim, required this.live});
  final RaceSim sim;
  final CheerLive live;

  @override
  Widget build(BuildContext context) => _Glass(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (sim.status == RaceStatus.live) const LiveDot(color: RL.red, size: 7) else Icon(Icons.timer_rounded, size: 16, color: muted(context)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<double>(
                    valueListenable: sim.clock,
                    builder: (_, t, _) => Text(
                      sim.status == RaceStatus.preRace ? tr('Gun in {t}', {'t': fmtDuration(-t)}) : '${fmtDuration(t, forceHours: true)} · ${fmtClock(sim.now)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: ink(context), fontFeatures: _tabular),
                    ),
                  ),
                  ListenableBuilder(
                    listenable: live,
                    builder: (_, _) => Text(
                      sim.status == RaceStatus.preRace
                          ? sim.event.name
                          : tr('{run} on course · {fin} finished', {'run': fmtInt(live.running), 'fin': fmtInt(live.finished)}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: muted(context)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _MapChip extends StatelessWidget {
  const _MapChip({required this.selected, required this.icon, required this.label, required this.onTap});
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = selected ? RL.navy : (dark ? const Color(0xFF111827) : Colors.white).withValues(alpha: 0.94);
    final fg = selected ? Colors.white : ink(context);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      elevation: 2,
      shadowColor: Colors.black26,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? Icons.check_rounded : icon, size: 16, color: selected ? RL.amber : fg),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.field});
  final bool field;

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, {bool hollow = false}) => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hollow ? Colors.white : c,
            border: Border.all(color: c, width: hollow ? 2.5 : 0),
          ),
        );
    final style = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: muted(context));
    return _Glass(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          dot(RL.series[1]),
          Text(tr('GPS'), style: style),
          dot(RL.series[2], hollow: true),
          Text(tr('Estimated'), style: style),
          if (field) ...[
            dot(RL.female.withValues(alpha: 0.6)),
            Text(tr('Women'), style: style),
            dot(RL.male.withValues(alpha: 0.6)),
            Text(tr('Men'), style: style),
          ],
        ],
      ),
    );
  }
}

class _RunnerChip extends StatelessWidget {
  const _RunnerChip({required this.id, required this.color, required this.selected, required this.onTap});
  final int id;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sim = context.read<RaceSim>();
    final units = context.select<SettingsController, Units>((s) => s.units);
    final p = sim.participant(id);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 196,
      decoration: BoxDecoration(
        color: (dark ? const Color(0xFF111827) : Colors.white).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: selected ? color : Colors.transparent, width: 2),
        boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                RunnerAvatar(participant: p, color: color, size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: ValueListenableBuilder<double>(
                    valueListenable: sim.clock,
                    builder: (context, t, _) {
                      final v = RunnerNow.of(sim, context.read<InsightsController>().snapshot, id, t);
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            id == sim.youId ? tr('You') : shortName(p),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w800, color: ink(context)),
                          ),
                          Text(
                            switch (v.state) {
                              RunnerState.running => '${v.estimated ? '≈' : ''}${fmtDistance(v.distanceM, units)} · ${fmtPace(v.paceSPerKm, units)}',
                              RunnerState.finished => tr('Finished {time}', {'time': fmtDuration(v.finishNetS)}),
                              _ => stateLabel(v.state),
                            },
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: muted(context), fontFeatures: _tabular),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
