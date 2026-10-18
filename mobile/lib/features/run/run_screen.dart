import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/i18n.dart';
import '../../core/theme.dart';
import '../../data/app_state.dart';
import '../../data/sim/race_sim.dart';
import '../../services/tracking_service.dart';
import '../../services/voice_service.dart';
import 'finish_celebration.dart';
import 'free_run_view.dart';
import 'race_day_view.dart';
import 'race_run_controller.dart';
import 'run_history.dart';
import 'run_widgets.dart';

/// The Run tab: Race day (your bib in the demo half marathon) or Free run
/// (real or simulated GPS with a share link), with your run history below.
class RunScreen extends StatefulWidget {
  const RunScreen({super.key});

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen> {
  late final RaceRunController _race;
  late final VoiceService _voice;
  int _mode = 0; // 0 race day, 1 free run

  @override
  void initState() {
    super.initState();
    _voice = context.read<VoiceService>();
    _race = RaceRunController(sim: context.read<RaceSim>(), settings: context.read<SettingsController>(), voice: _voice);
    if (context.read<TrackingService>().active) _mode = 1;
  }

  @override
  void dispose() {
    _race.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // In the shell's IndexedStack every tab stays mounted: mute animations
    // and skip the heavy live stats while this tab is hidden.
    final visible = Visibility.of(context);
    _race.visible = visible;
    final freeActive = context.select<TrackingService, bool>((t) => t.active);
    return TickerMode(
      enabled: visible,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Run')),
          actions: [
            ValueListenableBuilder<RunPhase>(
              valueListenable: _race.phase,
              builder: (_, ph, _) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: (ph == RunPhase.running || ph == RunPhase.waitingStart) && _mode == 0
                    ? Padding(
                        key: const ValueKey('live'),
                        padding: const EdgeInsets.only(right: 12),
                        child: Pill(tr('Live'), color: RL.green, filled: true, icon: Icons.sensors_rounded),
                      )
                    : const SizedBox.shrink(key: ValueKey('none')),
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
              children: [
                SegmentSwitch(
                  index: _mode,
                  labels: [tr('Race day'), tr('Free run')],
                  icons: const [Icons.confirmation_number_rounded, Icons.route_rounded],
                  badges: {if (freeActive) 1},
                  onChanged: (i) => setState(() => _mode = i),
                ),
                const SizedBox(height: 14),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(begin: Offset(child.key == const ValueKey(1) ? 0.06 : -0.06, 0), end: Offset.zero).animate(a),
                      child: child,
                    ),
                  ),
                  layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous.map((w) => Positioned(left: 0, right: 0, top: 0, child: w)), ?current]),
                  child: KeyedSubtree(
                    key: ValueKey(_mode),
                    child: _mode == 0 ? RaceDayView(controller: _race) : const FreeRunView(),
                  ),
                ),
                const SizedBox(height: 24),
                RunHistorySection(phase: _race.phase),
              ],
            ),
            Positioned(left: 0, right: 0, top: 6, child: VoiceCaption(voice: _voice)),
            ValueListenableBuilder<bool>(
              valueListenable: _race.celebrate,
              builder: (_, on, _) => on
                  ? Positioned.fill(child: FinishCelebration(onClose: () => _race.celebrate.value = false))
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
