import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/sim/race_sim.dart';
import 'race3d_controller.dart';
import 'race3d_mode.dart';
import 'race3d_payload.dart';
import 'race3d_view.dart';

/// Scene colours, matching `three_src/src/runners.js`.
class Race3DColors {
  static const you = Color(0xFFFFC83D);
  static const friend = Color(0xFFFF5CA8);
  static const category = Color(0xFFFFAB1F);
  static const men = Color(0xFF4D8DFF);
  static const women = Color(0xFF2FD27E);
  static const course = Color(0xFF3FA9FF);
  static const checkpoint = Color(0xFF55C8FF);
  static const bg = Color(0xFF0B1220);
}

/// Full-screen three.js race scene with a translucent control overlay:
/// replay of the whole race, drone view at the finish, course flyover.
class Race3DScreen extends StatefulWidget {
  const Race3DScreen({super.key, required this.mode, this.focusParticipantId, this.atRaceTime});
  final Race3DMode mode;

  /// Runner the camera follows / highlights (defaults to you).
  final int? focusParticipantId;

  /// Race time to start the playback at (e.g. a "Where were you" moment).
  final double? atRaceTime;

  @override
  State<Race3DScreen> createState() => _Race3DScreenState();
}

class _Race3DScreenState extends State<Race3DScreen> {
  final _controller = Race3DController();
  StreamSubscription<Race3DEvent>? _sub;

  late RaceSim _sim;
  late int _focusId;
  late List<int> _friendIds;
  late Race3DMode _mode;
  late double _t;
  late double _speed;
  bool _playing = true;
  bool _scrubbing = false;
  bool _wasPlaying = false;
  double? _flyDistance;
  int? _followId;
  int? _pickedId;

  @override
  void initState() {
    super.initState();
    _sim = context.read<RaceSim>();
    _focusId = widget.focusParticipantId ?? _sim.youId;
    _friendIds = _readFriends();
    _mode = widget.mode;
    _t = Race3DPayload.initialTime(_sim, _mode, focusId: _focusId, atRaceTime: widget.atRaceTime);
    _speed = Race3DPayload.defaultSpeed(_mode);
    _sub = _controller.events.listen(_onEvent);
  }

  List<int> _readFriends() {
    try {
      final follows = context.read<FollowsController>().ids;
      return [for (final id in {..._sim.friendIds, ...follows}) if (id != _sim.youId) id];
    } catch (_) {
      return _sim.friendIds;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onEvent(Race3DEvent e) {
    if (!mounted) return;
    switch (e) {
      case Race3DTime():
        if (_scrubbing) return;
        setState(() {
          _t = e.t;
          _playing = e.playing;
          _flyDistance = e.distance;
        });
      case Race3DPick():
        setState(() => _pickedId = e.id);
      case Race3DReady():
      case Race3DError():
        break;
    }
  }

  // ------------------------------------------------------------- payload

  Map<String, Object?> _initPayload() {
    final media = MediaQuery.maybeOf(context);
    final pad = media?.padding ?? EdgeInsets.zero;
    String label(int id) {
      final p = _sim.participant(id);
      if (id == _sim.youId) return '${tr('You')} · ${p.bib}';
      return '${p.firstName} · ${p.bib}';
    }

    final data = Race3DPayload.build(
      _sim,
      mode: _mode,
      focusId: _focusId,
      friendIds: _friendIds,
      t0: _t,
      speed: _speed,
      followId: _followId,
      labels: {for (final id in {_sim.youId, ..._friendIds, _focusId}) '$id': label(id)},
      strings: {
        'start': tr('START'),
        'finish': tr('FINISH'),
        'km': tr('KM'),
        'you': tr('You'),
        'event': _sim.event.name,
        'noWebgl': tr('3D needs WebGL 2, which this device does not support.'),
        'lost': tr('The 3D view was paused by the system. Reopen it to continue.'),
      },
    );
    data['playing'] = _playing;
    // Where Flutter's bars sit, so the scene frames the space between them.
    data['insets'] = {'top': pad.top + 104, 'bottom': pad.bottom + 176};
    return data;
  }

  // ------------------------------------------------------------- actions

  ({double start, double end}) get _range => Race3DPayload.range(_sim, _mode, _focusId);

  void _setMode(Race3DMode m) {
    if (m == _mode) return;
    final t = Race3DPayload.initialTime(_sim, m, focusId: _focusId, atRaceTime: m == Race3DMode.flyover ? null : (_mode == Race3DMode.replay ? _t : widget.atRaceTime));
    setState(() {
      _mode = m;
      _t = t;
      _speed = Race3DPayload.defaultSpeed(m);
      _playing = true;
      _pickedId = null;
      _flyDistance = null;
    });
    _controller.setMode(m, t: t, speed: _speed);
    _controller.play();
  }

  void _togglePlay() {
    setState(() => _playing = !_playing);
    _playing ? _controller.play() : _controller.pause();
  }

  void _setSpeed(double x) {
    setState(() => _speed = x);
    _controller.setSpeed(x);
  }

  void _follow(int? id) {
    setState(() => _followId = id);
    _controller.follow(id);
  }

  // ------------------------------------------------------------- build

  String get _title => switch (_mode) {
        Race3DMode.replay => tr('Race replay'),
        Race3DMode.drone => tr('Drone view'),
        Race3DMode.flyover => tr('Course flyover'),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Race3DColors.bg,
      body: Stack(
        children: [
          Positioned.fill(child: Race3DView(controller: _controller, initPayload: _initPayload)),
          Positioned(left: 0, right: 0, top: 0, child: _topBar(context)),
          Positioned(left: 0, right: 0, bottom: 0, child: _bottomPanel(context)),
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Race3DColors.bg.withValues(alpha: 0.92), Race3DColors.bg.withValues(alpha: 0)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          _sim.event.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Pill('3D', color: RL.amber, filled: true),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _ModeSwitch(mode: _mode, onChanged: _setMode),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomPanel(BuildContext context) {
    final r = _range;
    final flyover = _mode == Race3DMode.flyover;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Race3DColors.bg.withValues(alpha: 0), Race3DColors.bg.withValues(alpha: 0.88), Race3DColors.bg.withValues(alpha: 0.96)],
          stops: const [0, 0.28, 1],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 22, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_pickedId != null && !flyover) ...[_pickedCard(_pickedId!), const SizedBox(height: 8)],
              _legend(),
              const SizedBox(height: 6),
              Row(
                children: [
                  _PlayButton(playing: _playing, onPressed: _togglePlay),
                  const SizedBox(width: 10),
                  Expanded(child: _timeReadout()),
                  if (_mode == Race3DMode.replay) _followToggle(),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: RL.amber,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                  overlayColor: RL.amber.withValues(alpha: 0.2),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                ),
                child: SizedBox(
                  height: 30,
                  child: Slider(
                    value: _t.clamp(r.start, r.end).toDouble(),
                    min: r.start,
                    max: r.end,
                    semanticFormatterCallback: (v) => flyover ? fmtDuration(v) : fmtDuration(v, forceHours: true),
                    onChangeStart: (_) {
                      _scrubbing = true;
                      _wasPlaying = _playing;
                      if (_playing) _controller.pause();
                    },
                    onChanged: (v) {
                      setState(() => _t = v);
                      _controller.seek(v);
                    },
                    onChangeEnd: (v) {
                      _scrubbing = false;
                      _controller.seek(v);
                      if (_wasPlaying) _controller.play();
                    },
                  ),
                ),
              ),
              _speedRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timeReadout() {
    if (_mode == Race3DMode.flyover) {
      final total = _sim.race.distanceM;
      final d = _flyDistance ?? (_t / Race3DPayload.flyoverDurationS * total);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${tr('KM')} ${(d.clamp(0, total) / 1000).toStringAsFixed(1)} / ${(total / 1000).toStringAsFixed(1)}',
            style: _bigTime,
          ),
          Text(tr('Course preview · loops'), style: _smallLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      );
    }
    final wall = fmtClockSec(_sim.wallClockAt(_t));
    String? rel;
    if (_mode == Race3DMode.drone) {
      final f = Race3DPayload.finishTime(_sim, _focusId);
      if (f != null) rel = tr('Finish {gap}', {'gap': fmtDuration(_t - f, signed: true)});
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(fmtDuration(_t, forceHours: true), style: _bigTime),
        Text(
          rel == null ? '${tr('Race time')} · $wall' : '$wall · $rel',
          style: _smallLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  static const _bigTime = TextStyle(
    color: Colors.white,
    fontSize: 20,
    fontWeight: FontWeight.w800,
    height: 1.1,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const _smallLabel = TextStyle(color: Colors.white60, fontSize: 11.5, fontFeatures: [FontFeature.tabularFigures()]);

  Widget _followToggle() {
    final on = _followId == _sim.youId;
    return Tooltip(
      message: tr('Follow you'),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _follow(on ? null : _sim.youId),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: on ? RL.amber : Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: on ? RL.amber : Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(on ? Icons.my_location_rounded : Icons.location_searching_rounded, size: 15, color: Colors.white),
              const SizedBox(width: 5),
              Text(tr('Follow you'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _speedRow() {
    if (_mode == Race3DMode.flyover) {
      return Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2),
        child: Text(
          tr('A {s}-second flight along the whole course, before race day.', {'s': Race3DPayload.flyoverDurationS.round()}),
          style: _smallLabel,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    final speeds = Race3DPayload.speeds(_mode);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Icon(_mode == Race3DMode.drone ? Icons.slow_motion_video_rounded : Icons.speed_rounded, size: 16, color: Colors.white54),
          const SizedBox(width: 6),
          for (final s in speeds)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _SpeedChip(label: '${s.round()}×', selected: s == _speed, onTap: () => _setSpeed(s)),
            ),
        ],
      ),
    );
  }

  Widget _legend() {
    final items = <(Color, String)>[];
    final catName = _sim.race.categoryById(_sim.participant(_focusId).categoryId).name;
    switch (_mode) {
      case Race3DMode.replay:
        items.addAll([
          (Race3DColors.you, tr('You')),
          (Race3DColors.friend, tr('Friends')),
          (Race3DColors.category, catName),
          (Race3DColors.men, tr('Men')),
          (Race3DColors.women, tr('Women')),
        ]);
      case Race3DMode.drone:
        items.addAll([
          (Race3DColors.you, _focusId == _sim.youId ? tr('You') : _sim.participant(_focusId).firstName),
          (Race3DColors.category, catName),
          (Race3DColors.men, tr('Other men')),
          (Race3DColors.women, tr('Women')),
        ]);
      case Race3DMode.flyover:
        items.addAll([
          (Race3DColors.course, tr('Course')),
          (Race3DColors.checkpoint, tr('Checkpoints')),
          (Race3DColors.you, tr('Start / finish')),
        ]);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (c, label) in items)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle, boxShadow: [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 6)]),
                  ),
                  const SizedBox(width: 5),
                  Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _pickedCard(int id) {
    final p = _sim.participant(id);
    final plan = _sim.plan(id);
    final cat = _sim.race.categoryById(p.categoryId).name;
    final dnf = plan.dnfAtM != null;
    final color = id == _sim.youId
        ? Race3DColors.you
        : _friendIds.contains(id)
            ? Race3DColors.friend
            : p.gender == Gender.f
                ? Race3DColors.women
                : Race3DColors.men;
    final following = _followId == id;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF16213A).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  id == _sim.youId ? '${p.displayName} (${tr('You')})' : p.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                ),
                Text(
                  '${tr('Bib')} ${p.bib} · $cat · ${dnf ? tr('DNF') : fmtDuration(plan.netS)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          if (_mode == Race3DMode.replay)
            TextButton(
              onPressed: () => _follow(following ? null : id),
              style: TextButton.styleFrom(foregroundColor: RL.amber, visualDensity: VisualDensity.compact),
              child: Text(following ? tr('Unfollow') : tr('Follow')),
            ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
            onPressed: () => setState(() => _pickedId = null),
          ),
        ],
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onChanged});
  final Race3DMode mode;
  final ValueChanged<Race3DMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Race3DMode.replay, Icons.public_rounded, tr('Replay')),
      (Race3DMode.drone, Icons.videocam_rounded, tr('Drone view')),
      (Race3DMode.flyover, Icons.flight_takeoff_rounded, tr('Flyover')),
    ];
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          for (final (m, icon, label) in items)
            Expanded(
              child: Semantics(
                selected: m == mode,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(m),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: m == mode ? RL.amber : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 15, color: m == mode ? Colors.white : Colors.white70),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: m == mode ? Colors.white : Colors.white70,
                              fontSize: 12.5,
                              fontWeight: m == mode ? FontWeight.w800 : FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.onPressed});
  final bool playing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      tooltip: playing ? tr('Pause') : tr('Play'),
      onPressed: onPressed,
      style: IconButton.styleFrom(backgroundColor: RL.amber, foregroundColor: Colors.white, fixedSize: const Size(46, 46)),
      icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 26),
    );
  }
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? Colors.white : Colors.white24),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? RL.navy : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
